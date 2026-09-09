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
    var showInMenuBar: Bool?
    var popToRootSeconds: Int?
    var compactMode: Bool?
    var showFavoritesInCompactMode: Bool?
    var searchScopes: [String]?
    var openOnCursorScreen: Bool?
    var customCommandsEnabled: Bool?
    var customCommandsShowInLauncher: Bool?
    var windowManagementEnabled: Bool?
    var windowManagementShowInLauncher: Bool?
    var windowGap: Int?
    var windowCycleOnRepeat: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case clipboardRetentionDays
        case clipboardDisabledApps
        case launchAtLogin
        case hyperKey
        case hyperKeyIncludesShift
        case hyperKeyQuickPress
        case hyperKeyReplacesGlyph
        case showInMenuBar
        case popToRootSeconds
        case compactMode
        case showFavoritesInCompactMode
        case searchScopes
        case openOnCursorScreen
        case customCommandsEnabled
        case customCommandsShowInLauncher
        case windowManagementEnabled
        case windowManagementShowInLauncher
        case windowGap
        case windowCycleOnRepeat
    }
}

// periphery:ignore - compiled by Tools/settings-backup-test.swift, which Periphery doesn't index.
enum SettingsBackupCoverage {
    static let deliberatelyExcluded: [String: String] = [:]

    static let externalFields: Set<SettingsData.CodingKeys> = [.launchAtLogin, .showInMenuBar]
}
