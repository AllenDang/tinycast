import AppKit
import ImageIO

/// Downsampled, memory-capped image loading for the clipboard UI.
///
/// Clipboard images on disk can be full-resolution screenshots. Decoding those at full size just to
/// draw a 32pt row thumbnail wastes RAM and CPU, so we ask ImageIO for a thumbnail at the exact pixel
/// size we need and cache the results in an `NSCache` (which the system evicts under memory pressure).
enum ImageThumbnail {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        return cache
    }()

    private static func cacheKey(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    /// Cache-only lookup — never touches disk. Lets views render an already-decoded thumbnail on the
    /// same frame (no flash) while reserving the disk decode for the async path below.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.object(forKey: cacheKey(url, maxPixel))
    }

    /// Decodes off the main thread, then returns the result read back from the (thread-safe) cache on
    /// the caller. Decoding a full-res clipboard screenshot is expensive, so doing it inline in a view
    /// body would stall the UI when the clipboard first appears; this keeps that work off the main
    /// actor. The `NSImage` itself never crosses the actor boundary — the detached task only populates
    /// the cache — so it stays clean under strict concurrency.
    static func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        await Task.detached(priority: .userInitiated) {
            _ = load(url, maxPixel: maxPixel)
        }.value
        return cached(url, maxPixel: maxPixel)
    }

    /// A thumbnail no larger than `maxPixel` on its longest edge. Cached per (path, size). Decodes
    /// synchronously — call off the main thread (see `loadAsync`) for anything user-facing.
    static func load(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = cacheKey(url, maxPixel)
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    /// Pixel dimensions read from image metadata — no full decode.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
