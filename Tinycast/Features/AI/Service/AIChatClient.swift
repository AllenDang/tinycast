import Foundation

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

    struct StreamHandle {
        let stream: AsyncThrowingStream<String, any Error>
        let task: Task<Void, Never>
    }

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
