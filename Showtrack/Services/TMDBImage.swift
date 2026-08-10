import Foundation

/// Builds TMDB image URLs. Portrait posters use the `w500` size by default;
/// episode stills use `w300`.
enum TMDBImage {
    private static let base = URL(string: "https://image.tmdb.org/t/p")!

    static func poster(_ path: String?, size: String = "w500") -> URL? {
        url(path, size: size)
    }

    static func still(_ path: String?, size: String = "w300") -> URL? {
        url(path, size: size)
    }

    static func backdrop(_ path: String?, size: String = "w780") -> URL? {
        url(path, size: size)
    }

    static func logo(_ path: String?, size: String = "w92") -> URL? {
        url(path, size: size)
    }

    /// A network *wordmark* logo, negated (dark → light) via TMDB's image
    /// `negate` filter so it reads as a light logo suitable for a dark tile.
    /// `path` must be a raster (PNG/JPG); the parens/commas can't be percent-
    /// encoded, so the URL is built by hand.
    static func negatedNetworkLogo(_ path: String?, height: Int = 100) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/h\(height)_filter(negate,000,666)\(path)")
    }

    private static func url(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return base.appending(path: size).appending(path: path)
    }
}
