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
        static let clipboardMaxItems = "clipboardMaxItems"
    }

    @Published var clipboardMaxItems: Int {
        didSet { defaults.set(clipboardMaxItems, forKey: Key.clipboardMaxItems) }
    }

    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    init() {
        clipboardMaxItems = defaults.object(forKey: Key.clipboardMaxItems) as? Int ?? 500
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
