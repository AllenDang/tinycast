import Foundation

@MainActor
@Observable
final class CustomCommandCoordinator {
    private let store: CustomCommandStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteCoordinator
    private let hotKeys: HotKeyBindings
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let presentation: PresentationActions

    init(
        store: CustomCommandStore,
        settings: AppSettings,
        appIndex: AppIndex,
        palette: PaletteCoordinator,
        hotKeys: HotKeyBindings,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        presentation: PresentationActions
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.presentation = presentation
    }

    func applyCustomCommandsPresence() {
        let visible = settings.customCommandsEnabled && settings.customCommandsShowInLauncher
        appIndex.setCustomCommands(visible ? store.commands : [])
    }

    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try store.add(draft)
    }

    func updateCustomCommand(_ draft: CustomCommand) throws {
        try store.update(draft)
    }

    func deleteCustomCommand(id: UUID) async {
        guard let command = store.command(id: id) else { return }
        guard
            await presentation.confirm(
                "Delete “\(command.name)”?",
                "Its global shortcut and launcher references will also be removed.",
                CustomCommand.sfSymbol, "Delete", .danger, .destructive)
        else { return }
        removeCustomCommandReferences(ids: [id], entryIDs: [command.entryID])
        store.remove(id: id)
    }

    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.commands.map { ($0.id, $0) })
        let count = store.replace(with: commands)
        let liveIDs = Set(store.commands.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeCustomCommandReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    func runCustomCommand(id: UUID) {
        guard settings.customCommandsEnabled else { return }
        guard let command = store.command(id: id) else { return }
        if palette.isVisible { palette.hidePalette(restoreFocus: false) }
        Task {
            if command.requiresConfirmation {
                guard
                    await presentation.confirm(
                        command.name,
                        "Are you sure you want to run this command?\n\n\(command.command)",
                        CustomCommand.sfSymbol, "Run", .neutral, .standard)
                else { return }
            }
            let outcome = await ShellCommandRunner.run(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment)
            guard outcome != .success else {
                if command.showsConfirmation {
                    presentation.showMessage("Ran \(command.name)", .success)
                }
                return
            }
            await presentCustomCommandFailure(command: command, outcome: outcome)
        }
    }

    private func removeCustomCommandReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customCommand(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    private func presentCustomCommandFailure(
        command: CustomCommand, outcome: ShellCommandOutcome
    ) async {
        let message: String
        var suggestsShellEnvironment = false
        switch outcome {
        case .success:
            return
        case .launchFailure(let detail):
            message = "The shell could not be started.\n\n\(detail)"
        case .nonZeroExit(let status, let stderr):
            suggestsShellEnvironment = status == 127 && !command.loadsShellEnvironment
            message =
                "The command exited with status \(status)."
                + (stderr.map { "\n\n" + $0 } ?? "")
                + (suggestsShellEnvironment
                    ? "\n\nIf this is a shell alias or function, turn on Load Shell Environment for "
                        + "this command." : "")
        }
        guard
            await presentation.reportFailure(
                "“\(command.name)” Failed", message, CustomCommand.sfSymbol,
                suggestsShellEnvironment ? "Open Settings…" : nil)
        else { return }
        palette.showSettings(tab: .commands)
    }
}
