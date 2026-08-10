import Foundation
import SwiftData

/// A TV series the user is tracking.
///
/// CloudKit-backed SwiftData requires every stored property to have a default
/// value and relationships to be optional — do not add `.unique` constraints.
@Model
final class Show {
    var tmdbID: Int = 0
    var name: String = ""
    var overview: String = ""
    var posterPath: String? = nil
    var backdropPath: String? = nil
    var providerName: String? = nil
    var providerLogoPath: String? = nil
    /// True when `providerLogoPath` is a network *wordmark* logo (wide, on
    /// transparent) rather than a square provider tile — it's rendered negated
    /// (light) on a dark square instead of as an opaque tile.
    var providerIsNetworkLogo: Bool = false
    var addedAt: Date = Date.now
    var isTracking: Bool = true
    /// Version of the provider/backdrop metadata logic applied to this show.
    /// Shows below `ShowImporter.metadataVersion` get (re)backfilled — bumping
    /// that constant re-processes everyone when the selection logic changes.
    var metadataVersion: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    var episodes: [Episode]? = nil

    init(
        tmdbID: Int,
        name: String,
        overview: String = "",
        posterPath: String? = nil,
        isTracking: Bool = true
    ) {
        self.tmdbID = tmdbID
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.addedAt = .now
        self.isTracking = isTracking
    }

    /// Episodes airing today or later, soonest first.
    var upcomingEpisodes: [Episode] {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return (episodes ?? [])
            .filter { ($0.localAirDay ?? .distantPast) >= startOfToday }
            .sorted { ($0.localAirDay ?? .distantFuture) < ($1.localAirDay ?? .distantFuture) }
    }
}
