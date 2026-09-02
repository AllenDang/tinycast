import AppKit

@MainActor
@Observable
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let runningApps: RunningAppsMonitor
    private let palette: PaletteCoordinator
    private let customCommands: CustomCommandCoordinator
    private let systemActions: SystemActionCoordinator
    private let windowManagement: WindowManagementCoordinator
    private let quicklinks: QuicklinkCoordinator
    private let snippets: SnippetExpansionCoordinator
    private let backup: BackupCoordinator
    private let uninstall: UninstallCoordinator
    private let presentation: PresentationActions

    init(
        ranking: LauncherRankingStore,
        runningApps: RunningAppsMonitor,
        palette: PaletteCoordinator,
        customCommands: CustomCommandCoordinator,
        systemActions: SystemActionCoordinator,
        windowManagement: WindowManagementCoordinator,
        quicklinks: QuicklinkCoordinator,
        snippets: SnippetExpansionCoordinator,
        backup: BackupCoordinator,
        uninstall: UninstallCoordinator,
        presentation: PresentationActions
    ) {
        self.ranking = ranking
        self.runningApps = runningApps
        self.palette = palette
        self.customCommands = customCommands
        self.systemActions = systemActions
        self.windowManagement = windowManagement
        self.quicklinks = quicklinks
        self.snippets = snippets
        self.backup = backup
        self.uninstall = uninstall
        self.presentation = presentation
    }

    var rankingIsEmpty: Bool { ranking.isEmpty }

    func resetLearnedRanking() async {
        guard
            await presentation.confirm(
                "Reset learned launcher ranking?",
                "Tinycast will relearn your preferred results as you use the launcher.",
                "arrow.counterclockwise", "Reset Ranking", .danger, .destructive)
        else { return }
        ranking.resetAll()
    }

    func launch(_ app: AppEntry, searchQuery: String? = nil) {
        if let searchQuery {
            ranking.record(itemKey: app.preferenceKey, query: searchQuery)
        }
        switch app.kind {
        case .command:
            runCommand(app)
        case .customCommand:
            guard let id = CustomCommand.id(fromEntryID: app.id) else { return }
            customCommands.runCustomCommand(id: id)
        case .systemAction:
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActions.runSystemAction(id: action.id)
        case .windowCommand:
            guard let command = WindowCommandCatalog.command(forEntryID: app.id) else { return }
            windowManagement.run(id: command.id)
        case .quicklink:
            guard let id = Quicklink.id(fromEntryID: app.id) else { return }
            quicklinks.openQuicklink(id: id)
        case .application, .systemSettings, .snippet:
            let previous = palette.previousApp
            palette.hidePalette(restoreFocus: false)
            switch app.kind {
            case .application:
                AppLauncher.launch(app.url)
            case .systemSettings:
                guard let bundleID = app.bundleID else { return }
                AppLauncher.openSettingsPane(bundleID: bundleID)
            case .snippet:
                let snippetID = String(app.id.dropFirst("snippet:".count))
                snippets.expandSnippet(id: snippetID, targetApp: previous)
            case .command, .customCommand, .systemAction, .windowCommand, .quicklink:
                break
            }
        }
    }

    func hasRanking(for app: AppEntry) -> Bool {
        ranking.hasRanking(for: app.preferenceKey)
    }

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func isRunning(_ app: AppEntry) -> Bool {
        runningApps.isRunning(app)
    }

    func quit(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        let quittingPreviousApp = palette.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        palette.hidePalette(restoreFocus: !quittingPreviousApp)
    }

    func showInFinder(_ app: AppEntry) {
        palette.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func beginUninstall(_ app: AppEntry) {
        uninstall.beginUninstall(app)
    }

    private func runCommand(_ entry: AppEntry) {
        switch CommandCatalog.command(for: entry) {
        case .calculatorHistory:
            palette.showPalette(mode: .calculatorHistory)
        case .clipboardHistory:
            palette.showPalette(mode: .clipboard)
        case .searchEmoji:
            palette.showPalette(mode: .emoji)
        case .searchQuicklinks:
            palette.showPalette(mode: .quicklinks)
        case .createQuicklink:
            palette.hidePalette(restoreFocus: false)
            quicklinks.editQuicklink(nil)
        case .importQuicklinks:
            palette.hidePalette(restoreFocus: false)
            Task { await quicklinks.importQuicklinks() }
        case .exportQuicklinks:
            palette.hidePalette(restoreFocus: false)
            Task { await quicklinks.exportQuicklinks() }
        case .exportSettings:
            palette.hidePalette(restoreFocus: false)
            Task { await backup.exportSettings() }
        case .importSettings:
            palette.hidePalette(restoreFocus: false)
            Task { await backup.importSettings() }
        case .importFromRaycast:
            palette.hidePalette(restoreFocus: false)
            palette.showBackupSettings()
        case .settings:
            palette.hidePalette(restoreFocus: false)
            palette.showSettings()
        case .about:
            palette.hidePalette(restoreFocus: false)
            palette.showAbout()
        case .quit:
            NSApp.terminate(nil)
        case nil:
            break
        }
    }
}
