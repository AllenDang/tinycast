import Foundation

/// The AI command in flight: which one, what text it's running on, and the request's own lifecycle.
/// Mirrors `UninstallSession`'s shape — state enum plus the `Task` that fills it — rather than a
/// second ad hoc pattern for "one async operation the palette is waiting on."
///
/// Uses SSE streaming: content chunks arrive through `AIChatClient.streamComplete` and are
/// accumulated into the `.streaming` state, then finalized to `.result` when the stream ends.
@MainActor
@Observable
final class AICommandSession {
    enum State: Equatable {
        case loading
        case streaming(String)
        case result(String)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var command: AICommand?
    private(set) var input: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// The network-side task that drives `URLSession.bytes`; cancelled directly by `cancel()` so Esc
    /// tears down the connection immediately instead of waiting for the next SSE chunk.
    @ObservationIgnored private var streamTask: Task<Void, Never>?

    /// Starts the streaming request. `isEnabled` is re-read before the first chunk and after every
    /// chunk — consent can be withdrawn while the response is in flight, and a late answer must
    /// never be shown or become copyable.
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
            var accumulated = ""
            do {
                let handle = AIChatClient.streamComplete(
                    baseURL: baseURL, model: model, apiKey: apiKey, prompt: prompt)
                await MainActor.run { [weak self] in self?.streamTask = handle.task }
                for try await chunk in handle.stream {
                    guard !Task.isCancelled, isEnabled() else { return }
                    accumulated += chunk
                    self?.state = .streaming(accumulated)
                }
                guard !Task.isCancelled, isEnabled() else { return }
                self?.state = accumulated.isEmpty
                    ? .failed("The endpoint returned an empty response.") : .result(accumulated)
            } catch {
                guard !Task.isCancelled, isEnabled() else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Drops the in-flight request (if any) and the answer it was about — the Esc path, and every
    /// way of leaving the screen (Tab, the back chevron, a fresh summon).
    ///
    /// Cancels the session's own task (which stops the consumer loop) *and* the network-side stream
    /// task (which tears down the `URLSession` connection immediately). Without the second cancel,
    /// the `for try await` loop stays blocked on the next SSE chunk and Esc takes effect only after
    /// that chunk arrives.
    func cancel() {
        task?.cancel()
        streamTask?.cancel()
        task = nil
        streamTask = nil
        state = .loading
        command = nil
        input = nil
    }
}
