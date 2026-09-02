import Foundation

/// UserDefaults keys shared between call sites outside `AppSettings`.
enum SettingsKey {
    static let showInMenuBar = "showInMenuBar"
}

/// Every UserDefaults key owned by `AppSettings`.
enum AppSettingsKey: String, CaseIterable {
    case clipboardRetention = "clipboardRetentionDays"
    case clipboardDisabledApps
    case hyperKey = "hyperKeyPhysicalKey"
    case hyperKeyIncludesShift
    case hyperKeyQuickPress
    case hyperKeyReplacesGlyph
    case emojiSkinTone
    case popToRootTimeout
    case compactMode
    case showFavoritesInCompactMode
    case searchScopes = "launcherSearchScopes"
    case openOnCursorScreen
    case customCommandsEnabled
    case customCommandsShowInLauncher
    case snippetsEnabled
    case snippetsShowInLauncher
    case windowManagementEnabled
    case windowManagementShowInLauncher
    case windowGap = "windowManagementGap"
    case windowCycleOnRepeat = "windowManagementCycleOnRepeat"
    case quicklinksEnabled
    case quicklinksShowInLauncher
    case quicklinkOpensNewWindow
    case quicklinkSelectionFallback
    case quicklinkConfirmsBeforeDelete
}
