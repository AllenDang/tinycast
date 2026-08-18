import Foundation

/// The HTTP calls the AI commands feature makes: an OpenAI-compatible `POST {baseURL}/chat/completions`
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

    /// A streaming SSE request and the task that drives it, so the caller can cancel the network
    /// I/O immediately rather than waiting for the next chunk to arrive.
    struct StreamHandle {
        let stream: AsyncThrowingStream<String, any Error>
        let task: Task<Void, Never>
    }

    /// Streaming completion via SSE (`"stream": true`). Yields content deltas as they arrive;
    /// the caller is responsible for accumulating and checking consent after each chunk.
    /// Cancel the returned `handle.task` to tear down the network connection immediately —
    /// the `stream` will throw `CancellationError` and the consumer's `for try await` will exit.
    static func streamComplete(
        baseURL: URL, model: String, apiKey: String, prompt: String
    ) -> StreamHandle {
        let taskBox = StreamTaskBox()
        let stream = AsyncThrowingStream<String, any Error> { continuation in
            taskBox.task = Task {
                do {
                    var request = URLRequest(
                        url: baseURL.appendingPathComponent("chat/completions"),
                        timeoutInterval: 120)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(
                        StreamRequest(
                            model: model,
                            messages: [
                                StreamRequest.Message(role: "user", content: prompt)
                            ],
                            stream: true))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw Failure.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let message =
                            (try? JSONDecoder().decode(ErrorPayload.self, from: errorData))?.error?
                            .message
                        throw Failure.http(status: http.statusCode, message: message)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = line.dropFirst(6)
                        if json == "[DONE]" { break }
                        guard let jsonData = json.data(using: .utf8),
                            let chunk = try? JSONDecoder().decode(
                                StreamChunk.self, from: jsonData),
                            let content = chunk.choices.first?.delta.content,
                            !content.isEmpty
                        else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in taskBox.task?.cancel() }
        }
        return StreamHandle(stream: stream, task: taskBox.task!)
    }

    /// Box that holds the network task so the `AsyncThrowingStream`'s `@Sendable` closure can
    /// capture it by reference and `onTermination` can still cancel it.
    private final class StreamTaskBox: @unchecked Sendable {
        var task: Task<Void, Never>?
    }

    // MARK: - Request/response models

    private struct StreamRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let stream: Bool
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            let delta: Delta
        }
        struct Delta: Decodable {
            let content: String?
        }
        let choices: [Choice]
    }

    private struct ErrorPayload: Decodable {
        struct ErrorBody: Decodable { let message: String? }
        let error: ErrorBody?
    }
}
