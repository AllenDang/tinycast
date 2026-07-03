import SwiftUI

/// UserDefaults keys shared between `@AppStorage` call sites (scene state that isn't part of the
/// `AppSettings` model), so the App and the Settings UI bind to the same key.
enum SettingsKey {
    /// Menu-bar icon visibility — read by `MenuBarExtra(isInserted:)` and the Settings toggle.
    static let showInMenuBar = "showInMenuBar"
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardDisabledApps = "clipboardDisabledApps"
    }

    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }

    /// Bundle IDs whose clipboard changes are never recorded. Ordered so the Settings list is stable.
    @Published var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps) }
    }

    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    init() {
        // integer(forKey:) returns 0 when unset, which no case matches — falls through to 1 Month.
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention)) ?? .month
        // Password managers are excluded out of the box; the defaults apply only until the user
        // first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
