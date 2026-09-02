import Foundation

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
    @ObservationIgnored private var streamTask: Task<Void, Never>?

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
