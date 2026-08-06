import Foundation

/// The one HTTP call the AI commands feature makes: an OpenAI-compatible `POST {baseURL}/chat/completions`
/// against the user's own endpoint, with their own API key. No provider is named or assumed — `baseURL`
/// and `model` are entirely user-configured in Settings.
///
/// Mirrors `CurrencyRateStore.fetch`'s session shape: a private, cacheless `URLSession` rather than
/// `URLSession.shared`, so a feature the user has turned off can never leave a second copy of a
/// request or response sitting in the shared `URLCache`.
enum AIChatClient {
    enum Failure: LocalizedError {
        case invalidResponse
        case http(status: Int, message: String?)
        case empty

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The endpoint returned a response Tinycast couldn't read."
            case .http(let status, let message):
                return message ?? "The endpoint returned HTTP \(status)."
            case .empty:
                return "The endpoint returned an empty response."
            }
        }
    }

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// `baseURL` is joined with `chat/completions` the way every OpenAI-compatible server expects;
    /// `URL.appendingPathComponent` handles a base that already ends in a slash without doubling it.
    static func complete(
        baseURL: URL, model: String, apiKey: String, prompt: String
    ) async throws -> String {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("chat/completions"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, messages: [ChatRequest.Message(role: "user", content: prompt)]))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error?.message
            throw Failure.http(status: http.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: data),
            let content = decoded.choices.first?.message.content,
            !content.isEmpty
        else { throw Failure.empty }
        return content
    }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
    }

    private struct ChatCompletion: Decodable {
        struct Choice: Decodable {
            let message: ChatMessage
        }
        let choices: [Choice]
    }

    private struct ChatMessage: Decodable { let content: String }

    private struct ErrorPayload: Decodable {
        struct ErrorBody: Decodable { let message: String? }
        let error: ErrorBody?
    }
}
