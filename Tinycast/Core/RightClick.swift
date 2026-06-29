import SwiftUI

/// Right-click handler. SwiftUI's `.contextMenu` opens at the cursor; we want the actions popover
/// anchored to a fixed point, so we capture the right-click ourselves and present separately.
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
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        background(RightClickCatcher(action: action))
    }
}
