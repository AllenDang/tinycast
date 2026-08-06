import Foundation

/// The AI command in flight: which one, what text it's running on, and the request's own lifecycle.
/// Mirrors `UninstallSession`'s shape — state enum plus the `Task` that fills it — rather than a
/// second ad hoc pattern for "one async operation the palette is waiting on."
@MainActor
@Observable
final class AICommandSession {
    enum State: Equatable {
        case loading
        case result(String)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var command: AICommand?
    private(set) var input: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Starts the request. `isEnabled` is re-read immediately before the request fires and again the
    /// instant the `await` returns — consent can be withdrawn while the response is in flight, and a
    /// late answer must never be shown or become copyable.
    func begin(
        command: AICommand, input: String, baseURL: URL, model: String, apiKey: String,
        isEnabled: @escaping @MainActor () -> Bool
    ) {
        cancel()
        self.command = command
        self.input = input
        state = .loading

        let context = SnippetTemplateEngine.ExpansionContext(
            clipboardHistory: [], selection: "", now: Date(), calendar: .current,
            locale: .current, timeZone: .current, input: input)
        let prompt = SnippetTemplateEngine.expand(text: command.promptTemplate, context: context).text

        task = Task { [weak self] in
            guard isEnabled() else {
                self?.state = .failed("AI commands are turned off.")
                return
            }
            do {
                let result = try await AIChatClient.complete(
                    baseURL: baseURL, model: model, apiKey: apiKey, prompt: prompt)
                guard !Task.isCancelled, isEnabled() else { return }
                self?.state = .result(result)
            } catch {
                guard !Task.isCancelled, isEnabled() else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Drops the in-flight request (if any) and the answer it was about — the Esc path, and every
    /// way of leaving the screen (Tab, the back chevron, a fresh summon).
    func cancel() {
        task?.cancel()
        task = nil
        state = .loading
        command = nil
        input = nil
    }
}
