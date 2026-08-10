import Foundation
import SwiftData

/// A single episode belonging to a tracked `Show`.
@Model
final class Episode {
    var tmdbID: Int = 0
    var seasonNumber: Int = 0
    var episodeNumber: Int = 0
    var name: String = ""
    var overview: String = ""
    var stillPath: String? = nil
    var airDate: Date? = nil
    /// TMDB `episode_type`: "standard" / "premiere" / "mid_season" / "finale".
    var episodeType: String? = nil

    var show: Show? = nil

    init(
        tmdbID: Int,
        seasonNumber: Int,
        episodeNumber: Int,
        name: String = "",
        overview: String = "",
        stillPath: String? = nil,
        airDate: Date? = nil
    ) {
        self.tmdbID = tmdbID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.stillPath = stillPath
        self.airDate = airDate
    }

    /// Formatted as `S2 E5`.with a thin space
    var seasonEpisodeCode: String {
        String(format: "S%d E%d", seasonNumber, episodeNumber)
    }

    /// A premiere/finale milestone label to badge, or nil for standard episodes.
    /// Premieres are derived from the episode number (TMDB doesn't reliably tag
    /// them); finales come from `episodeType`.
    var episodeMilestone: String? {
        if seasonNumber == 1 && episodeNumber == 1 { return "Series premiere" }
        if episodeNumber == 1 { return "Season premiere" }
        switch episodeType {
        case "finale": return "Season finale"
        case "mid_season": return "Mid-season finale"
        default: return nil
        }
    }

    /// The broadcast calendar day, at **local** midnight.
    ///
    /// Air dates come from TMDB as a bare `YYYY-MM-DD` and are stored at UTC
    /// midnight. To bucket by the device's local day (Today / This Week) without
    /// timezone skew, recover the Y/M/D in UTC (matching how it was stored) and
    /// rebuild it in the current calendar/timezone.
    var localAirDay: Date? {
        guard let airDate else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let ymd = utc.dateComponents([.year, .month, .day], from: airDate)
        return Calendar.current.date(
            from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day)
        )
    }
}
