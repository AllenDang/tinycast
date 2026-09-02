import Foundation

struct SettingsBackup: Codable {
    var version = 4
    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var quicklinks: [Quicklink]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?

    // periphery:ignore - read by Tools/settings-backup-test.swift, which Periphery doesn't index.
    static let deliberatelyExcluded = SettingsBackupCoverage.deliberatelyExcluded

    struct HotkeyBackup: Codable {
        var togglePalette: HotKeyBinding?
        var toggleClipboard: HotKeyBinding?
        var toggleEmoji: HotKeyBinding?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var quicklinks: [String: HotKeyBinding]?
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var customCommands = 0
        var quicklinks = 0
    }
}

extension SettingsBackup {
    @MainActor
    struct Context {
        let settings: AppSettings
        let clipboardStore: ClipboardStore
        let hotKeys: HotKeyBindings
        let customCommands: CustomCommandStore
        let quicklinks: QuicklinkStore
        let favorites: FavoritesStore
        let visibility: VisibilityStore
        let replaceCustomCommands: ([CustomCommand]) -> Int
        let replaceQuicklinks: ([Quicklink]) -> Int
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(from context: Context) -> SettingsBackup {
        let s = context.settings
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
                ?? true,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            compactMode: s.compactMode,
            showFavoritesInCompactMode: s.showFavoritesInCompactMode,
            searchScopes: s.searchScopes,
            openOnCursorScreen: s.openOnCursorScreen,
            customCommandsEnabled: s.customCommandsEnabled,
            customCommandsShowInLauncher: s.customCommandsShowInLauncher,
            snippetsShowInLauncher: s.snippetsShowInLauncher,
            windowManagementEnabled: s.windowManagementEnabled,
            windowManagementShowInLauncher: s.windowManagementShowInLauncher,
            windowGap: s.windowGap,
            windowCycleOnRepeat: s.windowCycleOnRepeat,
            quicklinksEnabled: s.quicklinksEnabled,
            quicklinksShowInLauncher: s.quicklinksShowInLauncher,
            quicklinkOpensNewWindow: s.quicklinkOpensNewWindow,
            quicklinkSelectionFallback: s.quicklinkSelectionFallback.rawValue,
            quicklinkConfirmsBeforeDelete: s.quicklinkConfirmsBeforeDelete)

        let hk = context.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.toggleClipboard = hk.binding(for: .toggleClipboard)
        hotkeys.toggleEmoji = hk.binding(for: .toggleEmoji)
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.binding(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        hotkeys.customCommands = Dictionary(
            uniqueKeysWithValues: hk.boundCustomCommandIDs.compactMap { id in
                hk.binding(for: .customCommand(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.systemActions = Dictionary(
            uniqueKeysWithValues: SystemAction.ID.allCases.compactMap { id in
                hk.binding(for: .systemAction(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.windowCommands = Dictionary(
            uniqueKeysWithValues: WindowCommand.ID.allCases.compactMap { id in
                hk.binding(for: .windowCommand(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.quicklinks = Dictionary(
            uniqueKeysWithValues: hk.boundQuicklinkIDs.compactMap { id in
                hk.binding(for: .quicklink(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        backup.hotkeys = hotkeys

        backup.customCommands = context.customCommands.commands
        backup.quicklinks = context.quicklinks.quicklinks
        backup.favoriteApps = context.favorites.keys
        backup.hiddenLauncherItems = Array(context.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(context.visibility.hiddenKinds)
        return backup
    }

    @discardableResult
    func apply(to context: Context) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: context) }
        if let customCommands {
            summary.customCommands = context.replaceCustomCommands(customCommands)
        }
        // Before the hotkeys, so a restored binding has its quicklink to attach to.
        if let quicklinks {
            summary.quicklinks = context.replaceQuicklinks(quicklinks)
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: context) }
        if let favoriteApps {
            context.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(context.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(context.visibility.hiddenKinds)
            context.visibility.replace(hiddenItems: items, hiddenKinds: kinds)
            summary.hiddenItems = items.count
        }
        return summary
    }

    private func applySettings(_ s: SettingsData, to context: Context) -> Int {
        let settings = context.settings
        var count = 0
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            context.clipboardStore.maxAge = retention.maxAge
            context.clipboardStore.enforceLimits()
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
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let flag = s.showFavoritesInCompactMode {
            settings.showFavoritesInCompactMode = flag
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.openOnCursorScreen {
            settings.openOnCursorScreen = flag
            count += 1
        }
        // Writing through AppSettings is enough: feature observers re-project launcher presence.
        if let flag = s.customCommandsEnabled {
            settings.customCommandsEnabled = flag
            count += 1
        }
        if let flag = s.customCommandsShowInLauncher {
            settings.customCommandsShowInLauncher = flag
            count += 1
        }
        if let flag = s.snippetsShowInLauncher {
            settings.snippetsShowInLauncher = flag
            count += 1
        }
        if let flag = s.windowManagementEnabled {
            settings.windowManagementEnabled = flag
            count += 1
        }
        if let flag = s.windowManagementShowInLauncher {
            settings.windowManagementShowInLauncher = flag
            count += 1
        }
        if let gap = s.windowGap {
            settings.windowGap = gap
            count += 1
        }
        if let flag = s.windowCycleOnRepeat {
            settings.windowCycleOnRepeat = flag
            count += 1
        }
        if let flag = s.quicklinksEnabled {
            settings.quicklinksEnabled = flag
            count += 1
        }
        if let flag = s.quicklinksShowInLauncher {
            settings.quicklinksShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinkOpensNewWindow {
            settings.quicklinkOpensNewWindow = flag
            count += 1
        }
        if let raw = s.quicklinkSelectionFallback,
            let fallback = QuicklinkSelectionFallback(rawValue: raw) {
            settings.quicklinkSelectionFallback = fallback
            count += 1
        }
        if let flag = s.quicklinkConfirmsBeforeDelete {
            settings.quicklinkConfirmsBeforeDelete = flag
            count += 1
        }
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to context: Context) -> Int {
        let hk = context.hotKeys
        var count = 0
        func apply(_ binding: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: binding, excluding: action) == nil else { return }
            hk.setBinding(binding, for: action)
            count += 1
        }
        if let b = hotkeys.togglePalette { apply(b, .togglePalette) }
        if let b = hotkeys.toggleClipboard { apply(b, .toggleClipboard) }
        if let b = hotkeys.toggleEmoji { apply(b, .toggleEmoji) }
        for (id, b) in hotkeys.apps ?? [:] { apply(b, .app(bundleID: id)) }
        for (id, b) in hotkeys.panes ?? [:] { apply(b, .settingsPane(bundleID: id)) }
        for (rawID, b) in hotkeys.customCommands ?? [:] {
            guard let id = UUID(uuidString: rawID), context.customCommands.command(id: id) != nil else {
                continue
            }
            apply(b, .customCommand(id: id))
        }
        for (rawID, b) in hotkeys.systemActions ?? [:] {
            guard let id = SystemAction.ID(rawValue: rawID) else { continue }
            apply(b, .systemAction(id: id))
        }
        for (rawID, b) in hotkeys.windowCommands ?? [:] {
            guard let id = WindowCommand.ID(rawValue: rawID) else { continue }
            apply(b, .windowCommand(id: id))
        }
        for (rawID, b) in hotkeys.quicklinks ?? [:] {
            guard let id = UUID(uuidString: rawID), context.quicklinks.quicklink(id: id) != nil else {
                continue
            }
            apply(b, .quicklink(id: id))
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
