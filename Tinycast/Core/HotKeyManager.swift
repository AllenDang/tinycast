import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePalette = Self("togglePalette")
    static let toggleClipboard = Self("toggleClipboard")
    static func app(_ bundleID: String) -> Self { Self("appHotkey." + bundleID) }
}

@MainActor
final class HotKeyManager: ObservableObject {
    var onTogglePalette: (() -> Void)?
    var onToggleClipboard: (() -> Void)?

    private let boundKey = "boundAppBundleIDs"
    private var registered = Set<String>()

    func start() {
        KeyboardShortcuts.onKeyDown(for: .togglePalette) { [weak self] in
            MainActor.assumeIsolated { self?.onTogglePalette?() }
        }
        KeyboardShortcuts.onKeyDown(for: .toggleClipboard) { [weak self] in
            MainActor.assumeIsolated { self?.onToggleClipboard?() }
        }
        for bundleID in boundBundleIDs { registerAppHandler(bundleID) }
    }

    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// Called by the per-app settings recorder when a shortcut is set or cleared. Publishing here
    /// lets the launcher list re-read and show/hide each app's keycaps immediately.
    func setBinding(bundleID: String, hasShortcut: Bool) {
        objectWillChange.send()
        var set = Set(boundBundleIDs)
        if hasShortcut {
            set.insert(bundleID)
            registerAppHandler(bundleID)
        } else {
            set.remove(bundleID)
        }
        UserDefaults.standard.set(Array(set), forKey: boundKey)
    }

    private func registerAppHandler(_ bundleID: String) {
        let name = KeyboardShortcuts.Name.app(bundleID)
        guard registered.insert(name.rawValue).inserted else { return }
        KeyboardShortcuts.onKeyDown(for: name) {
            MainActor.assumeIsolated { AppLauncher.toggle(bundleID: bundleID) }
        }
    }
}
