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
        .popToRootTimeout: .popToRootSeconds,
        .compactMode: .compactMode,
        .showFavoritesInCompactMode: .showFavoritesInCompactMode,
        .searchScopes: .searchScopes,
        .openOnCursorScreen: .openOnCursorScreen,
        .customCommandsEnabled: .customCommandsEnabled,
        .customCommandsShowInLauncher: .customCommandsShowInLauncher,
        .windowManagementEnabled: .windowManagementEnabled,
        .windowManagementShowInLauncher: .windowManagementShowInLauncher,
        .windowGap: .windowGap,
        .windowCycleOnRepeat: .windowCycleOnRepeat,
    ]

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() throws {
        let exclusions = SettingsBackupCoverage.deliberatelyExcluded
        expect(exclusions.isEmpty, "all current AppSettings fields are mirrored")
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
            hyperKeyReplacesGlyph: true, showInMenuBar: true,
            popToRootSeconds: 5, compactMode: true, showFavoritesInCompactMode: true,
            searchScopes: ["/Applications"], openOnCursorScreen: true,
            customCommandsEnabled: true, customCommandsShowInLauncher: true,
            windowManagementEnabled: true,
            windowManagementShowInLauncher: true, windowGap: 8, windowCycleOnRepeat: true)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture))
        let dictionary = object as? [String: Any] ?? [:]
        let encodedFields = Set(dictionary.keys)
        expect(
            encodedFields == Set(SettingsData.CodingKeys.allCases.map(\.rawValue)),
            "encoded SettingsData schema must match its CodingKeys")

        let legacy = try JSONDecoder().decode(SettingsData.self, from: Data("""
            {"compactMode":true,"windowGap":8,"emojiSkinTone":42,
             "snippetsEnabled":true,"snippetsShowInLauncher":[],"quicklinksEnabled":{},
             "quicklinkSelectionFallback":false,"quicklinkConfirmsBeforeDelete":"old"}
            """.utf8))
        expect(legacy.compactMode == true && legacy.windowGap == 8,
               "malformed retired values cannot poison surviving settings")
        let legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy))
            as? [String: Any] ?? [:]
        expect(Set(legacyJSON.keys) == ["compactMode", "windowGap"],
               "retired fields are never emitted after legacy import")

        if failures == 0 {
            print("PASS: SettingsBackup covers every setting without retired fields")
        } else {
            exit(1)
        }
    }
}
