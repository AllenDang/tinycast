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
    case popToRootTimeout
    case compactMode
    case showFavoritesInCompactMode
    case searchScopes = "launcherSearchScopes"
    case openOnCursorScreen
    case customCommandsEnabled
    case customCommandsShowInLauncher
    case windowManagementEnabled
    case windowManagementShowInLauncher
    case windowGap = "windowManagementGap"
    case windowCycleOnRepeat = "windowManagementCycleOnRepeat"
}

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
