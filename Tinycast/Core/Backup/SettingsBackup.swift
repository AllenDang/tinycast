import Foundation

/// A passwordless, human-readable snapshot of Tinycast's configuration. Every field is optional so an import applies only the keys actually present (non-destructive merge): a partial file — or one from Raycast — leaves everything it omits untouched.
struct SettingsBackup: Codable {
    var version = 1
    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?

    /// Enum-backed settings are stored by raw value so the JSON stays legible and forward-compatible (an unknown value is ignored on import rather than failing the whole decode).
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
    }

    struct HotkeyBackup: Codable {
        var togglePalette: KeyShortcut?
        var toggleClipboard: KeyShortcut?
        var toggleEmoji: KeyShortcut?
        var apps: [String: KeyShortcut]?
        var panes: [String: KeyShortcut]?
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore = .shared) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            hyperKeyReplacesGlyph: s.hyperKeyReplacesGlyph,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            showInMenuBar: UserDefaults.standard.object(forKey: SettingsKey.showInMenuBar) as? Bool
                ?? true)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.shortcut(for: .togglePalette)
        hotkeys.toggleClipboard = hk.shortcut(for: .toggleClipboard)
        hotkeys.toggleEmoji = hk.shortcut(for: .toggleEmoji)
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.shortcut(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.shortcut(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        backup.hotkeys = hotkeys

        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.hiddenKinds)
        return backup
    }

    @discardableResult
    func apply(to core: AppCore = .shared) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.hiddenKinds)
            core.visibility.replace(hiddenItems: items, hiddenKinds: kinds)
            summary.hiddenItems = items.count
        }
        return summary
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            core.clipboardStore.maxAge = retention.maxAge
            core.clipboardStore.enforceLimits()
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.hyperKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.hyperKey = key
            count += 1
        }
        if let flag = s.hyperKeyIncludesShift {
            settings.hyperKeyIncludesShift = flag
            count += 1
        }
        if let raw = s.hyperKeyQuickPress, let quick = HyperKeyQuickPress(rawValue: raw) {
            settings.hyperKeyQuickPress = quick
            count += 1
        }
        if let flag = s.hyperKeyReplacesGlyph {
            settings.hyperKeyReplacesGlyph = flag
            count += 1
        }
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let show = s.showInMenuBar {
            UserDefaults.standard.set(show, forKey: SettingsKey.showInMenuBar)
            count += 1
        }
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        if let s = hotkeys.togglePalette {
            hk.setShortcut(s, for: .togglePalette)
            count += 1
        }
        if let s = hotkeys.toggleClipboard {
            hk.setShortcut(s, for: .toggleClipboard)
            count += 1
        }
        if let s = hotkeys.toggleEmoji {
            hk.setShortcut(s, for: .toggleEmoji)
            count += 1
        }
        for (id, s) in hotkeys.apps ?? [:] {
            hk.setShortcut(s, for: .app(bundleID: id))
            count += 1
        }
        for (id, s) in hotkeys.panes ?? [:] {
            hk.setShortcut(s, for: .settingsPane(bundleID: id))
            count += 1
        }
        return count
    }
}

// MARK: - Serialization

extension SettingsBackup {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
