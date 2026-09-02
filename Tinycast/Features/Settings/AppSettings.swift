import SwiftUI

enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: AppSettingsKey.searchScopes.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: AppSettingsKey.clipboardRetention.rawValue) }
    }

    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: AppSettingsKey.clipboardDisabledApps.rawValue) }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The physical key remapped to the Hyper chord; `HyperKeyTap` reacts via its observer.
    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: AppSettingsKey.hyperKey.rawValue) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: AppSettingsKey.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet { defaults.set(hyperKeyQuickPress.rawValue, forKey: AppSettingsKey.hyperKeyQuickPress.rawValue) }
    }

    /// Collapse the Hyper modifier set to "✦" wherever shortcut keycaps render.
    var hyperKeyReplacesGlyph: Bool {
        didSet { defaults.set(hyperKeyReplacesGlyph, forKey: AppSettingsKey.hyperKeyReplacesGlyph.rawValue) }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: AppSettingsKey.emojiSkinTone.rawValue) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: AppSettingsKey.popToRootTimeout.rawValue) }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: AppSettingsKey.compactMode.rawValue) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    var showFavoritesInCompactMode: Bool {
        didSet { defaults.set(showFavoritesInCompactMode, forKey: AppSettingsKey.showFavoritesInCompactMode.rawValue) }
    }

    /// Summon the palette on the display under the pointer instead of the one holding the menu bar.
    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: AppSettingsKey.openOnCursorScreen.rawValue) }
    }

    var customCommandsEnabled: Bool {
        didSet { defaults.set(customCommandsEnabled, forKey: AppSettingsKey.customCommandsEnabled.rawValue) }
    }

    /// With the feature on, controls only whether its launcher section appears.
    var customCommandsShowInLauncher: Bool {
        didSet {
            defaults.set(customCommandsShowInLauncher, forKey: AppSettingsKey.customCommandsShowInLauncher.rawValue)
        }
    }

    var snippetsEnabled: Bool {
        didSet { defaults.set(snippetsEnabled, forKey: AppSettingsKey.snippetsEnabled.rawValue) }
    }

    var snippetsShowInLauncher: Bool {
        didSet { defaults.set(snippetsShowInLauncher, forKey: AppSettingsKey.snippetsShowInLauncher.rawValue) }
    }

    /// Off means fully off: no launcher entries, and a still-registered shortcut moves nothing.
    var windowManagementEnabled: Bool {
        didSet { defaults.set(windowManagementEnabled, forKey: AppSettingsKey.windowManagementEnabled.rawValue) }
    }

    var windowManagementShowInLauncher: Bool {
        didSet {
            defaults.set(windowManagementShowInLauncher, forKey: AppSettingsKey.windowManagementShowInLauncher.rawValue)
        }
    }

    var windowGap: Int {
        didSet { defaults.set(windowGap, forKey: AppSettingsKey.windowGap.rawValue) }
    }

    /// Re-triggering a half steps it through ⅓ and ⅔ instead of re-applying the same frame.
    var windowCycleOnRepeat: Bool {
        didSet { defaults.set(windowCycleOnRepeat, forKey: AppSettingsKey.windowCycleOnRepeat.rawValue) }
    }

    var quicklinksEnabled: Bool {
        didSet { defaults.set(quicklinksEnabled, forKey: AppSettingsKey.quicklinksEnabled.rawValue) }
    }

    var quicklinksShowInLauncher: Bool {
        didSet { defaults.set(quicklinksShowInLauncher, forKey: AppSettingsKey.quicklinksShowInLauncher.rawValue) }
    }

    var quicklinkOpensNewWindow: Bool {
        didSet { defaults.set(quicklinkOpensNewWindow, forKey: AppSettingsKey.quicklinkOpensNewWindow.rawValue) }
    }

    /// What `{selection}` does when there is no readable selection to pass.
    var quicklinkSelectionFallback: QuicklinkSelectionFallback {
        didSet {
            defaults.set(quicklinkSelectionFallback.rawValue, forKey: AppSettingsKey.quicklinkSelectionFallback.rawValue)
        }
    }

    var quicklinkConfirmsBeforeDelete: Bool {
        didSet {
            defaults.set(quicklinkConfirmsBeforeDelete, forKey: AppSettingsKey.quicklinkConfirmsBeforeDelete.rawValue)
        }
    }

    init() {
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: AppSettingsKey.clipboardRetention.rawValue))
            ?? .threeMonths
        clipboardDisabledApps =
            defaults.stringArray(forKey: AppSettingsKey.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        hyperKey =
            defaults.string(forKey: AppSettingsKey.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init) ?? .none
        // The two Bools default to true, so absence must be distinguished from stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: AppSettingsKey.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: AppSettingsKey.hyperKeyQuickPress.rawValue).flatMap(HyperKeyQuickPress.init)
            ?? .none
        hyperKeyReplacesGlyph =
            defaults.object(forKey: AppSettingsKey.hyperKeyReplacesGlyph.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.hyperKeyReplacesGlyph.rawValue)
        emojiSkinTone =
            defaults.string(forKey: AppSettingsKey.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: AppSettingsKey.popToRootTimeout.rawValue))
            ?? .immediately
        compactMode = defaults.bool(forKey: AppSettingsKey.compactMode.rawValue)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: AppSettingsKey.showFavoritesInCompactMode.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.showFavoritesInCompactMode.rawValue)
        searchScopes = defaults.stringArray(forKey: AppSettingsKey.searchScopes.rawValue) ?? SearchScopes.defaults
        openOnCursorScreen =
            defaults.object(forKey: AppSettingsKey.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.openOnCursorScreen.rawValue)
        customCommandsEnabled = defaults.bool(forKey: AppSettingsKey.customCommandsEnabled.rawValue)
        customCommandsShowInLauncher =
            defaults.object(forKey: AppSettingsKey.customCommandsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.customCommandsShowInLauncher.rawValue)
        snippetsEnabled = defaults.bool(forKey: AppSettingsKey.snippetsEnabled.rawValue)
        snippetsShowInLauncher =
            defaults.object(forKey: AppSettingsKey.snippetsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.snippetsShowInLauncher.rawValue)
        windowManagementEnabled = defaults.bool(forKey: AppSettingsKey.windowManagementEnabled.rawValue)
        windowManagementShowInLauncher =
            defaults.object(forKey: AppSettingsKey.windowManagementShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.windowManagementShowInLauncher.rawValue)
        // Unset reads as 0, which is the intended default anyway — no gap.
        windowGap = defaults.integer(forKey: AppSettingsKey.windowGap.rawValue)
        windowCycleOnRepeat = defaults.bool(forKey: AppSettingsKey.windowCycleOnRepeat.rawValue)
        quicklinksEnabled = defaults.bool(forKey: AppSettingsKey.quicklinksEnabled.rawValue)
        quicklinksShowInLauncher =
            defaults.object(forKey: AppSettingsKey.quicklinksShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.quicklinksShowInLauncher.rawValue)
        quicklinkOpensNewWindow = defaults.bool(forKey: AppSettingsKey.quicklinkOpensNewWindow.rawValue)
        quicklinkSelectionFallback =
            defaults.string(forKey: AppSettingsKey.quicklinkSelectionFallback.rawValue)
            .flatMap(QuicklinkSelectionFallback.init) ?? .ask
        quicklinkConfirmsBeforeDelete =
            defaults.object(forKey: AppSettingsKey.quicklinkConfirmsBeforeDelete.rawValue) == nil
            || defaults.bool(forKey: AppSettingsKey.quicklinkConfirmsBeforeDelete.rawValue)
    }
}
