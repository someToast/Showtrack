import Foundation

/// Generic paged TMDB response wrapper.
struct TMDBPage<Element: Decodable & Sendable>: Decodable, Sendable {
    let results: [Element]
}

/// A search result / list entry for a TV series.
struct TMDBShow: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
}

/// Full detail for a single series.
struct TMDBShowDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let networks: [TMDBNetwork]?
    let seasons: [TMDBSeasonSummary]?
    let lastEpisodeToAir: TMDBEpisode?
    let nextEpisodeToAir: TMDBEpisode?
}

struct TMDBNetwork: Decodable, Sendable {
    let id: Int
    let name: String
    let logoPath: String?
}

// MARK: Watch providers (JustWatch, via TMDB)

/// `/tv/{id}/watch/providers` — `results` is keyed by ISO country code.
struct TMDBWatchProviders: Decodable, Sendable {
    let results: [String: TMDBWatchRegion]
}

struct TMDBWatchRegion: Decodable, Sendable {
    let flatrate: [TMDBProvider]?
    let free: [TMDBProvider]?
    let ads: [TMDBProvider]?
    let buy: [TMDBProvider]?
    let rent: [TMDBProvider]?
}

/// A streaming provider. `logoPath` is a uniform square app-icon tile.
struct TMDBProvider: Decodable, Sendable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?
}

/// `/watch/providers/tv` — the full provider directory for a region.
struct TMDBProviderList: Decodable, Sendable {
    let results: [TMDBProvider]
}

struct TMDBSeasonSummary: Decodable, Sendable {
    let seasonNumber: Int?
    let episodeCount: Int?
}

/// A season with its episode list (`/tv/{id}/season/{n}`).
struct TMDBSeason: Decodable, Sendable {
    let seasonNumber: Int?
    let episodes: [TMDBEpisode]?
}

struct TMDBEpisode: Decodable, Sendable {
    let id: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airDate: String?
    /// "standard", "premiere", "mid_season", or "finale". TMDB tags finales
    /// reliably but often leaves openers as "standard" — derive premieres from
    /// `episodeNumber == 1` instead.
    let episodeType: String?

    /// Parses TMDB's `YYYY-MM-DD` string into a `Date` (UTC noon to dodge
    /// timezone-boundary surprises).
    var airDateValue: Date? {
        guard let airDate, !airDate.isEmpty else { return nil }
        return DateFormatter.tmdbDay.date(from: airDate)
    }
}

extension DateFormatter {
    static let tmdbDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
