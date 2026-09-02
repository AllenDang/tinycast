import AppKit
import SwiftUI

extension View {
    func overlayScroller() -> some View {
        background(OverlayScrollerConfigurator().frame(width: 0, height: 0))
    }
}

private struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.applyOverlayStyle()
    }

    private final class ProbeView: NSView {
        private var attemptsRemaining = 12
        private var styleObserver: NotificationToken?

        override init(frame frameRect: NSRect) { super.init(frame: frameRect) }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                styleObserver = nil
                return
            }
            observeStyleChanges()
            // A new hierarchy gets a fresh splice retry budget.
            attemptsRemaining = 12
            applyOverlayStyle()
        }

        private func observeStyleChanges() {
            guard styleObserver == nil else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
            styleObserver = NotificationToken(token, center: .default)
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                guard attemptsRemaining > 0 else { return }
                attemptsRemaining -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            guard scrollView.scrollerStyle != .overlay || !scrollView.autohidesScrollers else {
                // Avoid layout churn after reaching the target state.
                return
            }
            // Overlay scrollers reserve no content width.
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            // Reclaim the legacy gutter in the same layout pass.
            scrollView.tile()
        }
    }
}
