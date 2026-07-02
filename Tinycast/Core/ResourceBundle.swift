import Foundation

extension Bundle {
    /// The SwiftPM-generated `Tinycast_Tinycast.bundle` (holding bundled resources like the
    /// changelog), resolved from wherever the app actually ships it.
    ///
    /// We deliberately avoid SwiftPM's `Bundle.module`: `swift build` generates an accessor that only
    /// checks `Bundle.main.bundleURL/<name>.bundle` (the `.app` root, where nothing signable lives)
    /// and a hardcoded build-directory path (present only on the build machine). Inside our
    /// hand-assembled `.app` — where `Packaging/make-app.sh` copies the bundle into
    /// `Contents/Resources` — both lookups miss and `Bundle.module` `fatalError`s. This searches the
    /// standard app resource locations instead, and degrades to `.main` rather than crashing.
    static let tinycastResources: Bundle = {
        let bundleName = "Tinycast_Tinycast.bundle"
        let candidates = [
            Bundle.main.resourceURL,                    // Tinycast.app/Contents/Resources
            Bundle.main.bundleURL,                      // Tinycast.app  (and CLI adjacency)
            Bundle(for: BundleFinder.self).resourceURL,
            Bundle(for: BundleFinder.self).bundleURL,
        ]
        for base in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: base.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        return .main
    }()
}

private final class BundleFinder {}
