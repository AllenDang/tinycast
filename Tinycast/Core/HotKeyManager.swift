import Foundation

/// Owns all global shortcut bindings: persistence, Carbon registration (via `HotKeyCenter`),
/// conflict lookup for the settings recorder, and dispatch to the actual actions.
@MainActor
final class HotKeyManager: ObservableObject {
    var onTogglePalette: (() -> Void)?
    var onToggleClipboard: (() -> Void)?

    /// The recorder currently capturing keystrokes, or `nil`. This single published value is
    /// what makes the recorders glitch-free: "which field is recording" is plain app state, so
    /// clicking another field is just a state flip — there is no first-responder handoff.
    /// While any recorder is active every Carbon registration is paused, so the combo being
    /// typed can't trigger the palette (Carbon consumes hotkeys before local monitors see them).
    @Published var recordingAction: HotKeyAction? {
        didSet { center.isPaused = recordingAction != nil }
    }

    private let center = HotKeyCenter()
    private let boundKey = "boundAppBundleIDs"

    func start() {
        register(.togglePalette)
        register(.toggleClipboard)
        for bundleID in boundBundleIDs { register(.app(bundleID: bundleID)) }
    }

    /// Bundle IDs that currently have a per-app hotkey — the index that lets `start()` know
    /// which `appHotkey.*` records to load and lets the launcher rows show keycaps.
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        // The stored value is a JSON *string* (the replaced package's format). Anything else —
        // e.g. the boolean sentinel old package versions could write — reads as unbound.
        guard
            let json = UserDefaults.standard.string(forKey: action.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(KeyShortcut.self, from: data)
    }

    /// Persists (or clears, when `nil`) the binding and swaps the live Carbon registration.
    /// Publishing lets the launcher list and every recorder re-render immediately.
    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        objectWillChange.send()
        if let shortcut,
            let data = try? JSONEncoder().encode(shortcut),
            let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
            register(action)
        } else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        }
        if case .app(let bundleID) = action {
            var set = Set(boundBundleIDs)
            if shortcut == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundKey)
        }
    }

    /// The display name of whatever `shortcut` is already bound to (other than `action`
    /// itself), or `nil` if it's free. Drives the recorder's "Used by …" message.
    func conflictOwner(of shortcut: KeyShortcut, excluding action: HotKeyAction) -> String? {
        var candidates: [HotKeyAction] = [.togglePalette, .toggleClipboard]
        candidates += boundBundleIDs.map { .app(bundleID: $0) }
        for candidate in candidates
        where candidate != action && self.shortcut(for: candidate) == shortcut {
            return displayName(of: candidate)
        }
        return nil
    }

    private func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .toggleClipboard:
            return "Clipboard History"
        case .app(let bundleID):
            let apps = AppCore.shared.appIndex.apps
            return apps.first { $0.bundleID == bundleID }?.name ?? bundleID
        }
    }

    private func register(_ action: HotKeyAction) {
        guard let shortcut = shortcut(for: action) else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePalette: onTogglePalette?()
        case .toggleClipboard: onToggleClipboard?()
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        }
    }
}
