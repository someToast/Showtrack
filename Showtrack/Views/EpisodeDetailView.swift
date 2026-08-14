import SwiftUI
import SwiftData

/// Detail for a tapped card. A single episode shows one page; a group of
/// same-day episodes shows swipeable cards with hard stops at the first and last.
struct EpisodeDetailView: View {
    let episodes: [Episode]

    var body: some View {
        Group {
            if episodes.isEmpty {
                ContentUnavailableView("No episode", systemImage: "tv")
            } else {
                EpisodePager(episodes: episodes)
            }
        }
        .navigationTitle(episodes.first?.show?.name ?? "Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Horizontally-paged carousel over a group's episodes, hard-stopping at both
/// ends. Pages load lazily (a `LazyHStack` in a paging `ScrollView`), so a large
/// same-day group doesn't build and decode every episode's header image up
/// front. The provider badge and pagination dots are pinned over the header
/// image so they stay fixed while pages swipe behind them horizontally — but they
/// still track the active page's vertical scroll, so pushing the content up
/// carries them up too (sliding under the nav bar along with the header image).
private struct EpisodePager: View {
    let episodes: [Episode]
    @State private var currentID: Int?
    /// Vertical scroll offset (≤ 0) of each page, keyed by index.
    @State private var offsets: [Int: CGFloat] = [:]

    private var index: Int { currentID ?? 0 }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(episodes.indices, id: \.self) { i in
                    EpisodeDetailPage(
                        episode: episodes[i],
                        pagePosition: episodes.count > 1 ? (i + 1, episodes.count) : nil
                    ) { offset in
                        offsets[i] = offset
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) {
            HeaderBadges(
                show: episodes.first?.show,
                pageCount: episodes.count,
                pageIndex: index
            )
            .offset(y: offsets[index] ?? 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The overlay's top edge sits at the header image's top (just below
            // the nav bar). Clipping there hides the badges as they scroll up past
            // it, so they read as passing behind the bar.
            .clipped()
        }
    }
}

/// Provider badge and (for a group) pagination dots, pinned over the header image
/// band so they stay fixed while episode pages swipe behind them.
private struct HeaderBadges: View {
    let show: Show?
    let pageCount: Int
    let pageIndex: Int

    var body: some View {
        Color.clear
            .frame(height: 220)
            .overlay(alignment: .bottomLeading) {
                if show?.providerLogoPath != nil || show?.providerName != nil {
                    // Lower-left of the header image, 200% of the base badge size.
                    ProviderBadge(
                        logoPath: show?.providerLogoPath,
                        name: show?.providerName,
                        size: 48,
                        isNetworkLogo: show?.providerIsNetworkLogo ?? false
                    )
                    .padding(12)
                }
            }
            .overlay(alignment: .bottom) {
                if pageCount > 1 {
                    PaginationDots(count: pageCount, index: pageIndex)
                        .padding(.bottom, 8)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Page-indicator dots for the paged episode header.
private struct PaginationDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(i == index ? 0.95 : 0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())
    }
}

/// One episode's detail page (header image + metadata), with pagination dots on
/// the header when it's part of a multi-episode group.
private struct EpisodeDetailPage: View {
    let episode: Episode
    /// Position within a same-day group ("2 of 4"), or nil for single-episode
    /// detail (no label shown).
    var pagePosition: (number: Int, count: Int)? = nil
    /// Reports vertical scroll offset (≤ 0, negative as content moves up) so the
    /// pinned header badges can track it.
    var onScroll: (CGFloat) -> Void = { _ in }

    private var show: Show? { episode.show }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topImage

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let show {
                                Text(show.name).font(.title2.bold())
                            }
                            if let pagePosition {
                                Spacer(minLength: 8)
                                Text("\(pagePosition.number) of \(pagePosition.count)")
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(episode.seasonEpisodeCode)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let day = episode.localAirDay {
                                Text(day, format: .dateTime.weekday(.abbreviated).month().day())
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !episode.name.isEmpty {
                        Text(episode.name)
                            .font(.title3.bold())
                            .padding(.top, 12)
                    }

                    if !synopsis.isEmpty {
                        Text(synopsis)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    if show?.providerName != nil {
                        Text("Streaming data by JustWatch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, scrolled in
            onScroll(-scrolled)
        }
    }

    private var synopsis: String {
        episode.overview.isEmpty ? (show?.overview ?? "") : episode.overview
    }

    /// Episode still first, then show backdrop, then poster.
    private var topImageURL: URL? {
        TMDBImage.still(episode.stillPath, size: "w780")
            ?? TMDBImage.backdrop(show?.backdropPath, size: "w780")
            ?? TMDBImage.poster(show?.posterPath, size: "w780")
    }

    private var topImage: some View {
        CachedAsyncImage(url: topImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where topImageURL != nil:
                ZStack { Rectangle().fill(.quaternary); ProgressView() }
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if let milestone = episode.episodeMilestone {
                EpisodeTypeChit(text: milestone).padding(12)
            }
        }
    }
}

/// Series detail: series artwork + description, then the dates of all known
/// upcoming episodes.
struct ShowDetailView: View {
    let show: Show

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topImage

                VStack(alignment: .leading, spacing: 10) {
                    Text(show.name).font(.title2.bold())

                    if !show.overview.isEmpty {
                        Text(show.overview).font(.body)
                    }

                    upcomingSection

                    if show.providerName != nil {
                        Text("Streaming data by JustWatch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var upcomingSection: some View {
        Text("Upcoming")
            .font(.title2.bold())
            .padding(.top, 16)

        if upcomingByDay.isEmpty {
            Text("No upcoming episodes scheduled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(upcomingByDay, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.dateLabel(for: group.day))
                            .font(.headline.weight(.medium))
                        ForEach(group.episodes) { episode in
                            HStack(spacing: 10) {
                                Text(subtitle(for: episode))
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                if let milestone = episode.episodeMilestone {
                                    EpisodeTypeChit(text: milestone)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    /// Upcoming episodes grouped by local air day (days ascending), each day's
    /// episodes ordered lowest → highest.
    private var upcomingByDay: [(day: Date, episodes: [Episode])] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: show.upcomingEpisodes) { ep in
            ep.localAirDay.map { cal.startOfDay(for: $0) } ?? .distantFuture
        }
        return buckets
            .map { (day: $0.key, episodes: $0.value.sorted {
                ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
            }) }
            .sorted { $0.day < $1.day }
    }

    private func subtitle(for episode: Episode) -> String {
        episode.name.isEmpty
            ? episode.seasonEpisodeCode
            : "\(episode.seasonEpisodeCode) · \(episode.name)"
    }

    /// "Thursday, August 13" — year appended only when beyond the current year.
    private static func dateLabel(for date: Date) -> String {
        let cal = Calendar.current
        let beyondThisYear = cal.component(.year, from: date) > cal.component(.year, from: .now)
        let formatter = DateFormatter()
        formatter.dateFormat = beyondThisYear ? "EEEE, MMMM d, yyyy" : "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private var topImageURL: URL? {
        TMDBImage.backdrop(show.backdropPath, size: "w780")
            ?? TMDBImage.poster(show.posterPath, size: "w780")
    }

    private var topImage: some View {
        CachedAsyncImage(url: topImageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty where topImageURL != nil:
                ZStack { Rectangle().fill(.quaternary); ProgressView() }
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "tv").font(.largeTitle).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if show.providerLogoPath != nil || show.providerName != nil {
                ProviderBadge(
                    logoPath: show.providerLogoPath,
                    name: show.providerName,
                    size: 48,
                    isNetworkLogo: show.providerIsNetworkLogo
                )
                .padding(12)
            }
        }
    }
}

/// Sample data for previews, backed by a retained in-memory container so the
/// model objects stay valid. Exposed as plain values so `#Preview` bodies can be
/// bare view expressions — nothing type-erased (like a `PreviewModifier`) or
/// wrapping (like `.modelContainer`) in front of the previewed view, so Xcode's
/// canvas "Selectable" mode can drill into it.
enum PreviewSample {
    @MainActor static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Show.self, Episode.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        let show = Show(
            tmdbID: 1,
            name: "Neon District",
            overview: "A burnt-out detective works the rain-slicked underbelly of a city that never sleeps, chasing a case that keeps rewriting itself."
        )
        show.providerName = "Netflix"
        context.insert(show)

        // E5 and E6 drop the same day (a two-episode release) to exercise grouping.
        let seed: [(Int, Int, String, String, Int, String?)] = [
            (2, 5, "Static", "", 0, nil),
            (2, 6, "Ghost Signal", "", 0, nil),
            (2, 7, "Blackout", "", 14, nil),
            (2, 8, "Last Call",
             "The case closes the only way it can — an old debt comes due under the neon.",
             21, "finale"),
        ]
        for (s, e, title, overview, days, type) in seed {
            let episode = Episode(
                tmdbID: s * 100 + e, seasonNumber: s, episodeNumber: e,
                name: title, overview: overview,
                airDate: cal.date(byAdding: .day, value: days, to: today)
            )
            episode.episodeType = type
            episode.show = show
            context.insert(episode)
        }
        return container
    }()

    @MainActor static var show: Show {
        (try? container.mainContext.fetch(FetchDescriptor<Show>()))?.first
            ?? Show(tmdbID: 0, name: "Sample")
    }

    @MainActor static var standardEpisode: Episode { show.upcomingEpisodes.first ?? finaleEpisode }

    @MainActor static var finaleEpisode: Episode {
        show.upcomingEpisodes.first { $0.episodeType == "finale" }
            ?? show.upcomingEpisodes.last
            ?? Episode(tmdbID: 0, seasonNumber: 1, episodeNumber: 1)
    }

    /// The same-day episode group (E5 + E6), lowest → highest.
    @MainActor static var episodes: [Episode] {
        let cal = Calendar.current
        return show.upcomingEpisodes
            .filter { $0.localAirDay.map { cal.isDateInToday($0) } ?? false }
            .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
    }
}

#Preview("Episode detail (from Shows)") {
    NavigationStack {
        EpisodeDetailView(episodes: PreviewSample.episodes)
    }
}

#Preview("Show detail (from Library)") {
    NavigationStack {
        ShowDetailView(show: PreviewSample.show)
    }
}
