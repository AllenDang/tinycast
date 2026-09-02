import AppKit

@MainActor
@Observable
final class SnippetExpansionCoordinator {
    private let store: SnippetsStore
    private let listener: SnippetKeywordListener
    private let injector: SnippetTextInjector
    private let clipboardStore: ClipboardStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let presentation: PresentationActions
    private let promptArguments: @MainActor (
        UUID, String, [SnippetTemplateEngine.MissingArgument]
    ) async -> [String: String]?
    private let cancelPrompt: @MainActor (UUID) -> Void
    @ObservationIgnored private var argumentTask: Task<Void, Never>?
    @ObservationIgnored private var argumentPromptID: UUID?

    init(
        store: SnippetsStore,
        listener: SnippetKeywordListener,
        injector: SnippetTextInjector,
        clipboardStore: ClipboardStore,
        appIndex: AppIndex,
        settings: AppSettings,
        presentation: PresentationActions,
        promptArguments: @escaping @MainActor (
            UUID, String, [SnippetTemplateEngine.MissingArgument]
        ) async -> [String: String]?,
        cancelPrompt: @escaping @MainActor (UUID) -> Void
    ) {
        self.store = store
        self.listener = listener
        self.injector = injector
        self.clipboardStore = clipboardStore
        self.appIndex = appIndex
        self.settings = settings
        self.presentation = presentation
        self.promptArguments = promptArguments
        self.cancelPrompt = cancelPrompt
    }

    func revealInFinder() {
        NSWorkspace.shared.open(store.snippetsDirectory)
    }

    func delete(_ record: StoredSnippet) async {
        guard
            await presentation.confirm(
                "Delete “\(record.snippet.name)”?",
                "This removes \(record.fileURL.lastPathComponent) from your snippets folder.",
                "text.quote", "Delete", .danger, .destructive)
        else { return }
        try? await store.delete(id: record.id)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.snippetsEnabled else { return }
        if !enabled {
            cancelArgumentTask()
            settings.snippetsEnabled = false
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await presentation.confirm(
                    "Enable snippets?",
                    "Keyword expansion requires the Accessibility permission. Keystrokes stay on this Mac.",
                    "curlybraces", "Continue", .neutral, .standard)
            else { return }
            settings.snippetsEnabled = true
            Permissions.ensureAccessibility()
        }
    }

    func applySnippetsLauncherPresence() {
        let visible = settings.snippetsEnabled && settings.snippetsShowInLauncher
        appIndex.updateSnippets(visible ? store.snippets : [])
    }

    func applySnippetsEnabled() {
        if settings.snippetsEnabled {
            Task { await store.start() }
            applySnippetsLauncherPresence()
            startSnippetKeywordListener()
            return
        }
        cancelArgumentTask()
        listener.stop()
        injector.cancelAutomaticExpansion()
        store.stop()
        appIndex.updateSnippets([])
    }

    private static let clipboardHistoryDepth = 20

    func startSnippetKeywordListener() {
        listener.start { [weak self] id, keyword, keywordLength, targetApp in
            guard let self else { return }
            guard
                !SnippetKeywordPolicy.ignoresTarget(
                    bundleID: targetApp?.bundleIdentifier,
                    ownBundleID: Bundle.main.bundleIdentifier)
            else { return }
            guard let generation = self.injector.beginAutomaticExpansion(targetApp: targetApp)
            else { return }
            self.expandSnippet(
                id: id,
                targetApp: targetApp,
                expectedKeyword: keyword,
                keywordLength: keywordLength,
                automaticGeneration: generation)
        }
    }

    func clipboardHistoryForExpansion() -> [String] {
        var history = clipboardStore.items
            .filter { $0.kind == .text }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.clipboardHistoryDepth)
            .compactMap(\.text)
        if let current = NSPasteboard.general.string(forType: .string), current != history.first {
            history.insert(current, at: 0)
        }
        return history
    }

    func expandSnippet(
        id: StoredSnippet.ID,
        targetApp: NSRunningApplication?,
        expectedKeyword: String? = nil,
        keywordLength: Int = 0,
        automaticGeneration: UInt? = nil
    ) {
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp)
            return
        }
        if automaticGeneration == nil {
            guard injector.prepareInteractiveExpansion(targetApp: targetApp) else { return }
        }
        let confirmation = record.snippet.showsConfirmation ? "Inserted \(record.snippet.name)" : nil
        let context = injector.captureExpansionContext(
            targetApp: targetApp,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context)
        if !result.missingArguments.isEmpty {
            guard argumentTask == nil else {
                injector.cancelArgumentPrompt(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp)
                return
            }
            let promptID = UUID()
            argumentPromptID = promptID
            argumentTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.argumentPromptID == promptID {
                        self.argumentPromptID = nil
                        self.argumentTask = nil
                    }
                }
                guard !Task.isCancelled else {
                    self.injector.cancelArgumentPrompt(
                        automaticGeneration: automaticGeneration,
                        targetApp: targetApp)
                    return
                }
                await self.promptSnippetArguments(
                    id: promptID,
                    record: record,
                    records: records,
                    context: context,
                    missingArgs: result.missingArguments,
                    targetApp: targetApp,
                    expectedKeyword: expectedKeyword,
                    keywordLength: keywordLength,
                    automaticGeneration: automaticGeneration,
                    confirmation: confirmation)
            }
            return
        }
        completeSnippetExpansion(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation)
    }

    private func promptSnippetArguments(
        id: UUID,
        record: StoredSnippet,
        records: [StoredSnippet],
        context: SnippetTemplateEngine.ExpansionContext,
        missingArgs: [SnippetTemplateEngine.MissingArgument],
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) async {
        let arguments = await promptArguments(id, record.snippet.name, missingArgs)
        guard !Task.isCancelled, let arguments else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp)
            return
        }

        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context,
            userArguments: arguments)
        completeSnippetExpansion(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation)
    }

    private func cancelArgumentTask() {
        guard let argumentTask, let argumentPromptID else { return }
        argumentTask.cancel()
        cancelPrompt(argumentPromptID)
    }

    private func completeSnippetExpansion(
        _ result: SnippetTemplateEngine.ExpansionResult,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        injector.deliver(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            onDelivered: { [weak self] in
                guard let self, let confirmation else { return }
                self.presentation.showMessage(confirmation, .success)
            })
    }
}
