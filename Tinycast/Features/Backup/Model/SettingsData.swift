import Foundation

/// The settings payload nested under `SettingsBackup.settings`.
struct SettingsData: Codable {
    var clipboardRetentionDays: Int?
    var clipboardDisabledApps: [String]?
    var launchAtLogin: Bool?
    var hyperKey: String?
    var hyperKeyIncludesShift: Bool?
    var hyperKeyQuickPress: String?
    var hyperKeyReplacesGlyph: Bool?
    var emojiSkinTone: String?
    var showInMenuBar: Bool?
    var popToRootSeconds: Int?
    var compactMode: Bool?
    var showFavoritesInCompactMode: Bool?
    var searchScopes: [String]?
    var openOnCursorScreen: Bool?
    var customCommandsEnabled: Bool?
    var customCommandsShowInLauncher: Bool?
    var snippetsShowInLauncher: Bool?
    var windowManagementEnabled: Bool?
    var windowManagementShowInLauncher: Bool?
    var windowGap: Int?
    var windowCycleOnRepeat: Bool?
    var quicklinksEnabled: Bool?
    var quicklinksShowInLauncher: Bool?
    var quicklinkOpensNewWindow: Bool?
    var quicklinkSelectionFallback: String?
    var quicklinkConfirmsBeforeDelete: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case clipboardRetentionDays
        case clipboardDisabledApps
        case launchAtLogin
        case hyperKey
        case hyperKeyIncludesShift
        case hyperKeyQuickPress
        case hyperKeyReplacesGlyph
        case emojiSkinTone
        case showInMenuBar
        case popToRootSeconds
        case compactMode
        case showFavoritesInCompactMode
        case searchScopes
        case openOnCursorScreen
        case customCommandsEnabled
        case customCommandsShowInLauncher
        case snippetsShowInLauncher
        case windowManagementEnabled
        case windowManagementShowInLauncher
        case windowGap
        case windowCycleOnRepeat
        case quicklinksEnabled
        case quicklinksShowInLauncher
        case quicklinkOpensNewWindow
        case quicklinkSelectionFallback
        case quicklinkConfirmsBeforeDelete
    }
}

// periphery:ignore - compiled by Tools/settings-backup-test.swift, which Periphery doesn't index.
enum SettingsBackupCoverage {
    static let deliberatelyExcluded = [
        AppSettingsKey.snippetsEnabled.rawValue:
            "Doubles as keyword-expansion consent; an import must not enable keystroke listening."
    ]

    static let externalFields: Set<SettingsData.CodingKeys> = [.launchAtLogin, .showInMenuBar]
}
