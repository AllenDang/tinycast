import SwiftUI

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
