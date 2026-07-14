import SwiftUI

/// UserDefaults keys shared between `@AppStorage` call sites so the App and the Settings UI bind to the same key.
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
        static let hyperKey = "hyperKeyPhysicalKey"
        static let hyperKeyIncludesShift = "hyperKeyIncludesShift"
        static let hyperKeyQuickPress = "hyperKeyQuickPress"
        static let hyperKeyReplacesGlyph = "hyperKeyReplacesGlyph"
        static let emojiSkinTone = "emojiSkinTone"
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

    /// The physical key remapped to the Hyper chord; `HyperKeyTap` reacts via its publisher.
    @Published var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    @Published var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift) }
    }

    @Published var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet { defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress) }
    }

    /// Collapse the Hyper modifier set to "✦" wherever shortcut keycaps render.
    @Published var hyperKeyReplacesGlyph: Bool {
        didSet { defaults.set(hyperKeyReplacesGlyph, forKey: Key.hyperKeyReplacesGlyph) }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    @Published var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone) }
    }

    init() {
        // integer(forKey:) returns 0 when unset, which no case matches — falls through to 3 Months.
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention))
            ?? .threeMonths
        // Password managers are excluded out of the box; the defaults apply only until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        hyperKey =
            defaults.string(forKey: Key.hyperKey).flatMap(HyperKeyPhysicalKey.init) ?? .none
        // The two Bools default to true, so absence must be distinguished from stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress).flatMap(HyperKeyQuickPress.init)
            ?? .none
        hyperKeyReplacesGlyph =
            defaults.object(forKey: Key.hyperKeyReplacesGlyph) == nil
            || defaults.bool(forKey: Key.hyperKeyReplacesGlyph)
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone).flatMap(EmojiSkinTone.init) ?? .none
    }
}
