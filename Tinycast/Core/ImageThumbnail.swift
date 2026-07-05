import AppKit
import ImageIO

/// Downsampled, memory-capped image loading for the clipboard UI.
///
/// Clipboard images on disk can be full-resolution screenshots. Decoding those at full size just to
/// draw a 32pt row thumbnail wastes RAM and CPU, so we ask ImageIO for a thumbnail at the exact pixel
/// size we need and cache the results in an `NSCache` (which the system evicts under memory pressure).
enum ImageThumbnail {
    /// `NSCache` is documented thread-safe ("you can add, remove, and query items in the cache from
    /// different threads without having to lock the cache yourself") but is not annotated `Sendable`,
    /// so shared-across-threads use — a decode on a detached task populating what the main actor
    /// reads — needs the guarantee asserted once, here.
    private final class ImageCache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// Small row thumbnails (≤ `rowThreshold` px on the longest edge). These are cheap to keep, so the
    /// cache survives palette dismissals — reopening the clipboard list then draws instantly with no
    /// decode flash. Bounded by *bytes* so it can't drift.
    private static let rowCache: ImageCache = {
        let cache = ImageCache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    /// Large previews (> `rowThreshold` px). A single full-screen screenshot preview decodes to a
    /// multi-MB bitmap, so this is bounded by *bytes* — not object count, which was the leak: 80 huge
    /// bitmaps were all "allowed" — and is purged the moment the palette closes (see `purgePreviews`).
    /// Byte-bounding is what keeps browsing memory flat no matter how many items the user clicks.
    private static let previewCache: ImageCache = {
        let cache = ImageCache()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Longest-edge size at or below which a decode is a "row" thumbnail; larger is a "preview".
    private static let rowThreshold: CGFloat = 128

    private static func pick(_ maxPixel: CGFloat) -> NSCache<NSString, NSImage> {
        maxPixel <= rowThreshold ? rowCache : previewCache
    }

    private static func cacheKey(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    /// Frees the large preview bitmaps — called when the palette is dismissed so idle RAM drops back
    /// near baseline. The row-thumbnail cache is intentionally left warm for an instant re-open.
    static func purgePreviews() {
        previewCache.removeAllObjects()
    }

    /// Cache-only lookup — never touches disk. Lets views render an already-decoded thumbnail on the
    /// same frame (no flash) while reserving the disk decode for the async path below.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        pick(maxPixel).object(forKey: cacheKey(url, maxPixel))
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
        let cache = pick(maxPixel)
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
        // Cost = the decoded bitmap's real byte footprint, so `totalCostLimit` bounds actual RAM.
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
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
