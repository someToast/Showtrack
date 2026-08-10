import Foundation
import SwiftData

/// Imports a TMDB search result into the local library: creates the `Show` and
/// pulls the episodes of its most recent season so the Home shelves have
/// something to bucket by air date.
@MainActor
struct ShowImporter {
    /// Bump when the metadata logic changes so existing shows get re-backfilled.
    /// v1: prefer the first-run network as provider. v2: capture episode_type.
    /// v3: network-aware provider selection (core > tier > reseller).
    /// v4: fall back to the provider directory for a network's own tile.
    /// v5: exact-name match first (keep AMC/AMC+/NBC/Peacock distinct).
    /// v6: negated network wordmark tile when no provider tile (FOX, CBS).
    /// v7: exact-only provider match (FOX≠Fox One; HBO now uses its wordmark).
    static let metadataVersion = 7

    let context: ModelContext

    func importShow(_ result: TMDBShow) async throws {
        // Skip if already tracked.
        let tmdbID = result.id
        let existing = try context.fetch(
            FetchDescriptor<Show>(predicate: #Predicate { $0.tmdbID == tmdbID })
        )
        guard existing.isEmpty else { return }

        let detail = try await TMDBClient.shared.showDetails(id: tmdbID)
        let show = Show(
            tmdbID: detail.id,
            name: detail.name,
            overview: detail.overview ?? "",
            posterPath: detail.posterPath
        )
        let providers = try? await TMDBClient.shared.watchProviders(showID: tmdbID)
        let directory = (try? await TMDBClient.shared.watchProviderDirectory()) ?? []
        Self.applyMetadata(to: show, detail: detail, providers: providers, directory: directory)
        show.metadataVersion = Self.metadataVersion
        context.insert(show)

        await Self.syncEpisodes(show: show, detail: detail, context: context)

        try context.save()
    }

    /// Fetch the show's current season and upsert its episodes (by TMDB id),
    /// including `episodeType`. Used by both import and backfill; also picks up
    /// newly-aired episodes for shows already tracked.
    static func syncEpisodes(show: Show, detail: TMDBShowDetail, context: ModelContext) async {
        guard let seasonNumber = currentSeasonNumber(for: detail),
              let season = try? await TMDBClient.shared.season(showID: detail.id, season: seasonNumber)
        else { return }

        let existing = show.episodes ?? []
        for ep in season.episodes ?? [] {
            if let match = existing.first(where: { $0.tmdbID == ep.id }) {
                match.seasonNumber = ep.seasonNumber ?? match.seasonNumber
                match.episodeNumber = ep.episodeNumber ?? match.episodeNumber
                match.name = ep.name ?? match.name
                match.overview = ep.overview ?? match.overview
                match.stillPath = ep.stillPath
                match.airDate = ep.airDateValue
                match.episodeType = ep.episodeType
            } else {
                let episode = Episode(
                    tmdbID: ep.id,
                    seasonNumber: ep.seasonNumber ?? seasonNumber,
                    episodeNumber: ep.episodeNumber ?? 0,
                    name: ep.name ?? "",
                    overview: ep.overview ?? "",
                    stillPath: ep.stillPath,
                    airDate: ep.airDateValue
                )
                episode.episodeType = ep.episodeType
                episode.show = show
                context.insert(episode)
            }
        }
    }

    /// Populate backdrop + provider on a show.
    ///
    /// Picks the best watch-provider *tile* (uniform square colored logo) for the
    /// show's originating network, ranking **core service > paid tier > reseller**
    /// ("… Channel"). If only resellers — or nothing — match the network, falls
    /// back to the network *name* as a text chip (network logos aren't square
    /// tiles). No per-provider special cases. Verified against real TMDB data:
    ///  • FOX/ABC (no own tile) → name chip
    ///  • NBC / HBO→HBO Max / AMC→AMC+ → matching provider tile
    ///  • Paramount+ / AMC+ tier & reseller variants → the core service's tile
    static func applyMetadata(
        to show: Show,
        detail: TMDBShowDetail,
        providers: TMDBWatchProviders?,
        directory: [TMDBProvider]
    ) {
        show.backdropPath = detail.backdropPath
        let choice = chooseProvider(networks: detail.networks, providers: providers, directory: directory)
        show.providerName = choice.name
        show.providerLogoPath = choice.logoPath
        show.providerIsNetworkLogo = choice.isNetworkLogo
    }

    private static func chooseProvider(
        networks: [TMDBNetwork]?,
        providers: TMDBWatchProviders?,
        directory: [TMDBProvider]
    ) -> (name: String?, logoPath: String?, isNetworkLogo: Bool) {
        let pool = regionProviders(providers)

        if let network = networks?.first {
            let networkName = network.name
            let networkKey = normalizedProviderName(networkName)

            // 1. Best non-reseller provider the show streams on whose name
            //    EXACTLY matches the network (after tier/reseller stripping). Exact
            //    only, so distinct services aren't merged — AMC≠AMC+, NBC≠Peacock,
            //    FOX≠Fox One. A network with no exact provider tile (FOX, HBO)
            //    falls through to its own wordmark below.
            let matches = pool.compactMap { provider -> (rank: Int, dp: Int, provider: TMDBProvider)? in
                let (base, rank) = classify(provider.providerName)
                guard rank < 2, !base.isEmpty, base == networkKey else { return nil }   // exact, skip resellers
                return (rank, provider.displayPriority ?? .max, provider)
            }
            if let best = matches.min(by: { ($0.rank, $0.dp) < ($1.rank, $1.dp) }) {
                return (best.provider.providerName, best.provider.logoPath, false)
            }

            // 2. The network's own tile from the directory, matched EXACTLY by
            //    name (ABC, NBC, The CW, PBS). Exact match avoids grabbing a
            //    same-prefix service (network "FOX" won't match "FOX One").
            let dirMatches = directory.compactMap { provider -> (rank: Int, provider: TMDBProvider)? in
                let (base, rank) = classify(provider.providerName)
                guard rank < 2, base == networkKey, !base.isEmpty else { return nil }
                return (rank, provider)
            }
            if let best = dirMatches.min(by: { $0.rank < $1.rank }) {
                return (best.provider.providerName, best.provider.logoPath, false)
            }

            // 3. No provider tile → the network's own wordmark, rendered negated
            //    (light) on a dark square. Needs a raster (PNG) logo; if there's
            //    none, fall back to the network name as a text square.
            if let logo = network.logoPath, !logo.lowercased().hasSuffix(".svg") {
                return (networkName, logo, true)
            }
            return (networkName, nil, false)
        }

        // No network info: best non-reseller tile by rank then display priority.
        let ranked = pool.compactMap { provider -> (rank: Int, dp: Int, provider: TMDBProvider)? in
            let (_, rank) = classify(provider.providerName)
            guard rank < 2 else { return nil }
            return (rank, provider.displayPriority ?? .max, provider)
        }
        guard let best = ranked.min(by: { ($0.rank, $0.dp) < ($1.rank, $1.dp) }) else { return (nil, nil, false) }
        return (best.provider.providerName, best.provider.logoPath, false)
    }

    private static func regionProviders(_ providers: TMDBWatchProviders?) -> [TMDBProvider] {
        let region = Locale.current.region?.identifier ?? "US"
        guard let bucket = providers?.results[region] ?? providers?.results["US"] else { return [] }
        var pool: [TMDBProvider] = []
        pool.append(contentsOf: bucket.flatrate ?? [])
        pool.append(contentsOf: bucket.ads ?? [])
        pool.append(contentsOf: bucket.free ?? [])
        return pool
    }

    /// Normalized brand `base` + rank for a provider name:
    /// 0 = core service, 1 = paid tier (Premium/Essential/…), 2 = reseller
    /// (name contains "Channel", e.g. "… Amazon Channel", "… on The Roku Channel").
    private static func classify(_ name: String) -> (base: String, rank: Int) {
        var base = name.lowercased()
        let isReseller = base.contains("channel")
        if isReseller {
            for phrase in ["amazon channel", "apple tv channel", "roku premium channel",
                           "premium channel", "channel"] {
                if let range = base.range(of: phrase) {
                    base = String(base[..<range.lowerBound])
                    break
                }
            }
        }
        base = base.trimmingCharacters(in: .whitespaces)

        var isTier = false
        for tier in ["premium plus", "premium", "essential", "standard with ads",
                     "with ads", "basic", "ad-free"] {
            if base.hasSuffix(tier) {
                base = String(base.dropLast(tier.count)).trimmingCharacters(in: .whitespaces)
                isTier = true
                break
            }
        }
        let rank = isReseller ? 2 : (isTier ? 1 : 0)
        return (normalizedProviderName(base), rank)
    }

    /// Normalize provider/network names for comparison: lowercase, "plus" → "+",
    /// strip spaces/punctuation. So "Paramount Plus" == "Paramount+".
    private static func normalizedProviderName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "plus", with: "+")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    /// Prefer the season of the last/next aired episode; fall back to the
    /// highest-numbered real season (ignoring "Specials" == season 0).
    private static func currentSeasonNumber(for detail: TMDBShowDetail) -> Int? {
        if let n = detail.nextEpisodeToAir?.seasonNumber { return n }
        if let n = detail.lastEpisodeToAir?.seasonNumber { return n }
        return detail.seasons?
            .compactMap(\.seasonNumber)
            .filter { $0 > 0 }
            .max()
    }
}

/// Backfills provider/backdrop metadata and episode data for shows below the
/// current `ShowImporter.metadataVersion`, so a version bump re-processes every
/// show once (a show whose fetch fails — e.g. no token — is retried next launch).
@MainActor
enum MetadataBackfiller {
    static func run(context: ModelContext) async {
        let current = ShowImporter.metadataVersion
        let descriptor = FetchDescriptor<Show>(
            predicate: #Predicate { $0.metadataVersion < current }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        let directory = (try? await TMDBClient.shared.watchProviderDirectory()) ?? []
        for show in pending {
            let id = show.tmdbID
            guard let detail = try? await TMDBClient.shared.showDetails(id: id) else { continue }
            let providers = try? await TMDBClient.shared.watchProviders(showID: id)
            ShowImporter.applyMetadata(to: show, detail: detail, providers: providers, directory: directory)
            await ShowImporter.syncEpisodes(show: show, detail: detail, context: context)
            show.metadataVersion = current
        }

        try? context.save()
    }
}
