import Foundation

enum TMDBError: LocalizedError {
    case missingToken
    case badResponse(status: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No TMDB access token set. Add one in Secrets.swift (see Secrets.example.swift)."
        case .badResponse(let status):
            return "TMDB request failed (HTTP \(status))."
        }
    }
}

/// Thin async client for the TMDB v3 REST API, authenticated with a v4
/// Read Access Token (Bearer).
actor TMDBClient {
    static let shared = TMDBClient()

    private let base = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Cached provider directory (stable per app session).
    private var providerDirectory: [TMDBProvider]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Endpoints

    func searchTV(_ query: String) async throws -> [TMDBShow] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let page: TMDBPage<TMDBShow> = try await get(
            "/search/tv",
            query: [URLQueryItem(name: "query", value: query)]
        )
        return page.results
    }

    func showDetails(id: Int) async throws -> TMDBShowDetail {
        try await get("/tv/\(id)")
    }

    func season(showID: Int, season: Int) async throws -> TMDBSeason {
        try await get("/tv/\(showID)/season/\(season)")
    }

    func watchProviders(showID: Int) async throws -> TMDBWatchProviders {
        try await get("/tv/\(showID)/watch/providers")
    }

    /// The region's full provider directory (memoized) — used to find a network's
    /// own tile when a show's watch providers don't list it (e.g. ABC).
    func watchProviderDirectory() async throws -> [TMDBProvider] {
        if let providerDirectory { return providerDirectory }
        let region = Locale.current.region?.identifier ?? "US"
        let list: TMDBProviderList = try await get(
            "/watch/providers/tv",
            query: [URLQueryItem(name: "watch_region", value: region)]
        )
        providerDirectory = list.results
        return list.results
    }

    // MARK: Request plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let token = Secrets.tmdbAccessToken
        guard !token.isEmpty else { throw TMDBError.missingToken }

        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query
        items.append(URLQueryItem(name: "language", value: "en-US"))
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TMDBError.badResponse(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TMDBError.badResponse(status: http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}
