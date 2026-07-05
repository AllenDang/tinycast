import Foundation

extension Bundle {
    /// The app's channel-aware display name — "Tinycast", "Tinycast Alpha", "Tinycast Beta".
    /// Driven by CFBundleDisplayName/CFBundleName in the generated Info.plist (see
    /// Packaging/make-app.sh), so UI chrome reflects which channel is running.
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Tinycast"
    }
}
