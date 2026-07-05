import Foundation

/// RAII handle for a block-based `NotificationCenter` observation: dropping the token removes the
/// observer. Block-based observations aren't cleaned up automatically (unlike selector-based ones),
/// but a `@MainActor` class can't touch its non-`Sendable` token from its nonisolated `deinit` under
/// Swift 6 — so ownership lives here instead, where the deinit and the token share one isolation
/// domain. `removeObserver` is documented thread-safe, so this is sound wherever the last release
/// happens.
final class NotificationToken {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol, center: NotificationCenter) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
