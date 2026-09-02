import SwiftUI

struct ScrollIntent: Equatable {
    enum Kind {
        case top
        case follow
    }

    var kind: Kind
    /// Distinguishes back-to-back intents of the same kind so `onChange` still fires.
    var nonce = UUID()
}

extension View {
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }
}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }

    func reveal(_ id: String) {
        scrollTo(id, anchor: nil)
    }
}
