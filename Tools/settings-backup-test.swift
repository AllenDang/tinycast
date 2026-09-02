import Foundation

@main
@MainActor
struct SettingsBackupCompletenessTests {
    private static var failures = 0

    private static let appSettingsFields: [AppSettingsKey: SettingsData.CodingKeys] = [
        .clipboardRetention: .clipboardRetentionDays,
        .clipboardDisabledApps: .clipboardDisabledApps,
        .hyperKey: .hyperKey,
        .hyperKeyIncludesShift: .hyperKeyIncludesShift,
        .hyperKeyQuickPress: .hyperKeyQuickPress,
        .hyperKeyReplacesGlyph: .hyperKeyReplacesGlyph,
        .emojiSkinTone: .emojiSkinTone,
        .popToRootTimeout: .popToRootSeconds,
        .compactMode: .compactMode,
        .showFavoritesInCompactMode: .showFavoritesInCompactMode,
        .searchScopes: .searchScopes,
        .openOnCursorScreen: .openOnCursorScreen,
        .customCommandsEnabled: .customCommandsEnabled,
        .customCommandsShowInLauncher: .customCommandsShowInLauncher,
        .snippetsShowInLauncher: .snippetsShowInLauncher,
        .windowManagementEnabled: .windowManagementEnabled,
        .windowManagementShowInLauncher: .windowManagementShowInLauncher,
        .windowGap: .windowGap,
        .windowCycleOnRepeat: .windowCycleOnRepeat,
        .quicklinksEnabled: .quicklinksEnabled,
        .quicklinksShowInLauncher: .quicklinksShowInLauncher,
        .quicklinkOpensNewWindow: .quicklinkOpensNewWindow,
        .quicklinkSelectionFallback: .quicklinkSelectionFallback,
        .quicklinkConfirmsBeforeDelete: .quicklinkConfirmsBeforeDelete,
    ]

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() throws {
        let exclusions = SettingsBackupCoverage.deliberatelyExcluded
        let expectedReason =
            "Doubles as keyword-expansion consent; an import must not enable keystroke listening."
        expect(exclusions.count == 1, "only snippetsEnabled is deliberately excluded")
        expect(
            exclusions[AppSettingsKey.snippetsEnabled.rawValue] == expectedReason,
            "snippetsEnabled carries the required security reason")
        expect(exclusions.values.allSatisfy { !$0.isEmpty }, "every exclusion has a reason")

        let allKeys = Set(AppSettingsKey.allCases.map(\.rawValue))
        let mappedKeys = Set(appSettingsFields.keys.map(\.rawValue))
        let coveredKeys = mappedKeys.union(exclusions.keys)
        expect(
            coveredKeys == allKeys,
            "AppSettings key coverage mismatch; missing \(allKeys.subtracting(coveredKeys).sorted()), "
                + "unknown \(coveredKeys.subtracting(allKeys).sorted())")

        let expectedExternal: Set<SettingsData.CodingKeys> = [.launchAtLogin, .showInMenuBar]
        expect(
            SettingsBackupCoverage.externalFields == expectedExternal,
            "external backup fields must be exactly launchAtLogin and showInMenuBar")

        let allFields = Set(SettingsData.CodingKeys.allCases)
        let mappedFields = Set(appSettingsFields.values)
        let coveredFields = mappedFields.union(SettingsBackupCoverage.externalFields)
        expect(
            coveredFields == allFields,
            "SettingsData field coverage mismatch; missing "
                + "\(allFields.subtracting(coveredFields).map(\.rawValue).sorted()), unknown "
                + "\(coveredFields.subtracting(allFields).map(\.rawValue).sorted())")
        expect(
            mappedFields.count == appSettingsFields.count,
            "two AppSettings keys must not silently map to one backup field")

        let fixture = SettingsData(
            clipboardRetentionDays: 90, clipboardDisabledApps: ["example"], launchAtLogin: true,
            hyperKey: "capsLock", hyperKeyIncludesShift: true, hyperKeyQuickPress: "none",
            hyperKeyReplacesGlyph: true, emojiSkinTone: "none", showInMenuBar: true,
            popToRootSeconds: 5, compactMode: true, showFavoritesInCompactMode: true,
            searchScopes: ["/Applications"], openOnCursorScreen: true,
            customCommandsEnabled: true, customCommandsShowInLauncher: true,
            snippetsShowInLauncher: true, windowManagementEnabled: true,
            windowManagementShowInLauncher: true, windowGap: 8, windowCycleOnRepeat: true,
            quicklinksEnabled: true, quicklinksShowInLauncher: true,
            quicklinkOpensNewWindow: true, quicklinkSelectionFallback: "ask",
            quicklinkConfirmsBeforeDelete: true)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture))
        let dictionary = object as? [String: Any] ?? [:]
        let encodedFields = Set(dictionary.keys)
        expect(
            encodedFields == Set(SettingsData.CodingKeys.allCases.map(\.rawValue)),
            "encoded SettingsData schema must match its CodingKeys")
        expect(!encodedFields.contains("snippetsEnabled"), "the consent key must not be encoded")

        if failures == 0 {
            print("PASS: SettingsBackup covers every setting and excludes consent explicitly")
        } else {
            exit(1)
        }
    }
}
