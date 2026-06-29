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

    /// A thumbnail no larger than `maxPixel` on its longest edge. Cached per (path, size).
    static func load(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    /// Pixel dimensions read from image metadata — no full decode.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
