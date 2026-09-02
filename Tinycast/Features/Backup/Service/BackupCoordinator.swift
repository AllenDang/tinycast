import AppKit

@MainActor
@Observable
final class BackupCoordinator {
    struct RaycastOutcome {
        var summary: SettingsBackup.ApplySummary
        var clipboardImported: Int
        var snippetsImported: Int
        var snippetsError: String?
        var missingImages: Int
    }

    private let context: SettingsBackup.Context
    private let snippetsStore: SnippetsStore
    private let confirmAction: @MainActor (
        String, String, String, String, DialogTone, DialogAction.Role
    ) async -> Bool
    private let noticeAction: @MainActor (String, String, String, DialogTone) async -> Void

    init(
        context: SettingsBackup.Context,
        snippetsStore: SnippetsStore,
        confirm: @escaping @MainActor (
            String, String, String, String, DialogTone, DialogAction.Role
        ) async -> Bool,
        notice: @escaping @MainActor (String, String, String, DialogTone) async -> Void
    ) {
        self.context = context
        self.snippetsStore = snippetsStore
        confirmAction = confirm
        noticeAction = notice
    }

    func exportSettings() async {
        guard let url = BackupActions.chooseSaveLocation(named: "Tinycast-Settings") else { return }
        do {
            try SettingsBackup.gather(from: context).encoded().write(to: url, options: .atomic)
        } catch {
            await present(
                title: "Export Failed", message: error.localizedDescription,
                symbol: "square.and.arrow.up")
        }
    }

    func importSettings() async {
        guard let url = BackupActions.chooseJSONFile() else { return }
        do {
            let backup = try SettingsBackup(json: try Data(contentsOf: url))
            let commandCount = backup.customCommands?.count ?? 0
            let shortcutCount = backup.hotkeys?.customCommands?.count ?? 0
            guard await confirmExecutableImport(commands: commandCount, shortcuts: shortcutCount)
            else { return }
            await present(
                title: "Settings Imported",
                message: BackupActions.summaryText(backup.apply(to: context)),
                symbol: Self.importSymbol, tone: .success)
        } catch {
            await present(
                title: "Import Failed", message: error.localizedDescription,
                symbol: Self.importSymbol)
        }
    }

    func importRaycast(
        file: URL, passphrase: String, options: RaycastImportOptions = .all
    ) async throws -> RaycastOutcome {
        let result = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try RaycastImport.read(file: file, passphrase: passphrase).selecting(options)
            }
        }.value
        var snippetsImported = 0
        var snippetsError: String?
        if !result.snippets.isEmpty {
            do {
                if context.settings.snippetsEnabled { await snippetsStore.start() }
                snippetsImported =
                    try await snippetsStore.importSnippets(result.snippets).count
            } catch {
                snippetsError = error.localizedDescription
            }
        }
        let summary = result.backup.apply(to: context)
        let imported =
            result.clipboard.isEmpty
            ? 0 : context.clipboardStore.importEntries(result.clipboard)
        return RaycastOutcome(
            summary: summary,
            clipboardImported: imported,
            snippetsImported: snippetsImported,
            snippetsError: snippetsError,
            missingImages: result.missingImages)
    }

    private func confirmExecutableImport(commands: Int, shortcuts: Int) async -> Bool {
        guard commands > 0 || shortcuts > 0 else { return true }
        let commandText = commands == 1 ? "1 custom command" : "\(commands) custom commands"
        let shortcutText =
            shortcuts == 1 ? "1 global shortcut" : "\(shortcuts) global shortcuts"
        return await confirmAction(
            "Import executable commands?",
            "This backup contains \(commandText) and \(shortcutText). Custom commands can run "
                + "arbitrary shell code. Only import files you trust.",
            Self.importSymbol, "Import", .danger, .standard)
    }

    private static let importSymbol = "square.and.arrow.down"

    private func present(
        title: String, message: String, symbol: String, tone: DialogTone = .danger
    ) async {
        await noticeAction(title, message, symbol, tone)
    }
}
