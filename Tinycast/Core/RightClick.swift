import SwiftUI

/// Right-click handler. SwiftUI's `.contextMenu` opens at the cursor; we want the actions popover
/// anchored to a fixed point, so we capture the right-click ourselves and present separately.
/// Used as an `.overlay` whose `hitTest` only claims right-mouse events — left-clicks (launch) pass
/// straight through to the SwiftUI row beneath.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func rightMouseDown(with event: NSEvent) { action() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }
}
