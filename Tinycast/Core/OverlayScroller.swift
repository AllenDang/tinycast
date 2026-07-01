import AppKit
import SwiftUI

/// Forces the backing `NSScrollView` of a SwiftUI `ScrollView` to use the thin,
/// auto-hiding *overlay* scroller, regardless of the user's system
/// "Show scroll bars" setting. Pure configuration — no custom NSScroller, no
/// drawing. Leaves SwiftUI's ScrollView / ScrollViewReader / LazyVStack untouched;
/// if the enclosing scroll view can't be found it does nothing (default scroller).
private struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguratorView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfiguratorView)?.applyOverlayStyle()
    }

    private final class ConfiguratorView: NSView {
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
        override init(frame: NSRect) { super.init(frame: frame) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyOverlayStyle()
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                // Not yet spliced into the scroll view's hierarchy; retry next tick.
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            guard scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay  // thin + appears-on-scroll + auto-hide
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
            // A legacy scroller reserves a fixed strip of layout width; switching to overlay frees it,
            // but the content only reclaims that width on the next full layout — which, in a reused
            // panel, doesn't happen until a reopen. Re-tile now so the clip view (and the hosted
            // content it sizes) expands to full width immediately, on this same pass.
            scrollView.tile()
        }
    }
}

extension View {
    /// Attach *inside* a SwiftUI `ScrollView` (e.g. on its content) to force the
    /// native thin overlay scrollbar.
    func thinOverlayScrollbar() -> some View {
        background(OverlayScrollerConfigurator().frame(width: 0, height: 0))
    }
}
