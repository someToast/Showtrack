import Foundation
import SwiftUI
import ImageIO
import UIKit

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

    private static func url(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return base.appending(path: size).appending(path: path)
    }
}

/// Process-wide cache of decoded, downsampled images. `NSCache` is bounded and
/// evicts under memory pressure, so image memory can't grow without limit.
private final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 80 * 1024 * 1024   // ~80 MB of decoded pixels
    }

    func image(for key: NSString) -> UIImage? { cache.object(forKey: key) }

    func insert(_ image: UIImage, cost: Int, for key: NSString) {
        cache.setObject(image, forKey: key, cost: cost)
    }
}

/// Carries a decoded `UIImage` across the concurrency boundary; the image is
/// immutable once decoded, so this is safe.
private struct DecodedImage: @unchecked Sendable { let image: UIImage }

/// Drop-in replacement for `AsyncImage(url:content:)` that decodes each image
/// *downsampled to its display size* (via ImageIO) and caches the decoded
/// result — instead of decoding every image at full resolution and re-decoding
/// on each reuse. Exposes `AsyncImagePhase`, so `switch phase` call sites port
/// over unchanged.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let maxPixel = Self.maxPixel(for: proxy.size, scale: displayScale)
            content(phase)
                // GeometryReader pins content top-leading; fill and center so
                // aspect-fit logos sit in the middle of the tile like AsyncImage.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: RequestKey(url: url, maxPixel: maxPixel)) {
                    await load(maxPixel: maxPixel)
                }
        }
    }

    @MainActor
    private func load(maxPixel: Int) async {
        guard let url, maxPixel > 0 else {
            phase = .empty
            return
        }
        let key = "\(url.absoluteString)|\(maxPixel)" as NSString
        if let cached = ImageMemoryCache.shared.image(for: key) {
            phase = .success(Image(uiImage: cached))
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try await Task.detached(priority: .utility) {
                try downsampleImage(data: data, maxPixel: maxPixel)
            }.value
            let cost = decoded.image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            ImageMemoryCache.shared.insert(decoded.image, cost: cost, for: key)
            phase = .success(Image(uiImage: decoded.image))
        } catch is CancellationError {
            // Superseded by a newer request (size/url changed); keep current phase.
        } catch {
            phase = .failure(error)
        }
    }

    /// Longest edge in pixels, rounded up to a step so small layout jitters don't
    /// re-trigger a decode.
    private static func maxPixel(for size: CGSize, scale: CGFloat) -> Int {
        let longest = max(size.width, size.height) * scale
        guard longest > 0 else { return 0 }
        let step: CGFloat = 32
        return Int((longest / step).rounded(.up) * step)
    }
}

private struct RequestKey: Equatable {
    let url: URL?
    let maxPixel: Int
}

private enum ImageDecodeError: Error { case failed }

/// Decodes `data` to a `UIImage` no larger than `maxPixel` on its longest edge.
/// File-scope (not a generic method) so the background task doesn't capture a
/// non-Sendable generic metatype.
private func downsampleImage(data: Data, maxPixel: Int) throws -> DecodedImage {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        throw ImageDecodeError.failed
    }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw ImageDecodeError.failed
    }
    return DecodedImage(image: UIImage(cgImage: cgImage))
}
