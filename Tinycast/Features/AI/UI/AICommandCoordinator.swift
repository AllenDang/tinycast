import Foundation

@MainActor
@Observable
final class AICommandCoordinator {
    private let providerStore: AIProviderStore
    private let commandStore: AICommandStore
    private let session: AICommandSession
    private let paletteState: PaletteState
    private let palette: PaletteCoordinator
    private let presentation: PresentationActions

    init(
        providerStore: AIProviderStore,
        commandStore: AICommandStore,
        session: AICommandSession,
        paletteState: PaletteState,
        palette: PaletteCoordinator,
        presentation: PresentationActions
    ) {
        self.providerStore = providerStore
        self.commandStore = commandStore
        self.session = session
        self.paletteState = paletteState
        self.palette = palette
        self.presentation = presentation
    }

    func confirmEnablingProvider() async -> Bool {
        await presentation.confirm(
            "Turn on AI commands?",
            "Text typed after a command’s keyword is sent to the endpoint you configure below, "
                + "using the API key you provide there. Nothing is sent until you set an endpoint "
                + "and use a command.",
            AICommand.sfSymbol, "Enable", .neutral, .standard)
    }

    func delete(_ command: AICommand) async {
        guard
            await presentation.confirm(
                "Delete “\(command.name)”?",
                "Its keyword will stop matching in the launcher.",
                AICommand.sfSymbol, "Delete", .danger, .destructive)
        else { return }
        commandStore.remove(id: command.id)
    }

    func begin(_ match: AICommandMatch) {
        guard providerStore.isConfigured,
            let providerID = match.command.providerID,
            let provider = providerStore.provider(id: providerID),
            let baseURL = provider.baseURL,
            providerStore.isProviderConfigured(providerID)
        else { return }
        let model = provider.model.trimmingCharacters(in: .whitespaces)
        session.begin(
            command: match.command, input: match.input, baseURL: baseURL, model: model,
            apiKey: providerStore.apiKey(for: providerID),
            isEnabled: { [weak providerStore] in providerStore?.isEnabled ?? false })
        paletteState.mode = .aiCommand
    }

    func cancel() {
        session.cancel()
    }

    func finish(copying text: String) {
        session.cancel()
        paletteState.mode = .launcher
        palette.hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }
}
