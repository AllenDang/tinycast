import SwiftUI

/// Forces every NSScrollView in the hosting window to use thin, auto-hiding overlay scrollers
/// (Raycast-style), regardless of the system "Show scroll bars" preference.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configureWindow(of: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configureWindow(of: nsView) }
    }

    private func configureWindow(of view: NSView) {
        guard let content = view.window?.contentView else { return }
        apply(to: content)
    }

    private func apply(to view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
        }
        view.subviews.forEach(apply)
    }
}
