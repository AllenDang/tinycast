import AppKit
import SwiftUI

/// A thin, auto-hiding scrollbar drawn entirely in SwiftUI, for `ScrollView`s inside the reused
/// palette panel.
///
/// The native `NSScroller` overlay "flashes" as an appear affordance every time the panel re-shows —
/// AppKit drives that through private scroller machinery (`NSScrollerImpPair`), so it can't be
/// suppressed without undocumented overrides. Instead we hide the native scroller and bind our own
/// bar's visibility to real scroll **phases**: it literally cannot appear unless the user is actually
/// scrolling, so there's no flash on open, on any OS version, with no runtime tricks.
struct ThinScrollbar: ViewModifier {
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var scrollable: Bool { content > viewport + 1 }
    }

    @State private var metrics = Metrics()
    @State private var visible = false
    @State private var fade: Task<Void, Never>?
    @State private var scrollPos = ScrollPosition(idType: Never.self)
    /// Content offset captured when a thumb drag begins; non-nil only while dragging.
    @State private var dragAnchor: CGFloat?

    // Tuned to read like the macOS overlay knob: a thin, inset, semi-transparent capsule.
    private let width: CGFloat = 6
    private let inset: CGFloat = 3
    private let minThumb: CGFloat = 28

    private var dragging: Bool { dragAnchor != nil }

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)  // drop the native scroller (and its flash) entirely
            .scrollPosition($scrollPos)  // lets the thumb drive the offset when dragged
            // Geometry drives the thumb's size/position; it changes on layout too, so it never
            // touches visibility.
            .onScrollGeometryChange(for: Metrics.self) { geo in
                Metrics(
                    offset: geo.contentOffset.y,
                    content: geo.contentSize.height,
                    viewport: geo.containerSize.height
                )
            } action: { _, new in
                metrics = new
            }
            // Visibility follows the *interaction* only — so opening/laying out the list never shows it.
            // A thumb drag scrolls programmatically (no user phase), so its own handlers own visibility.
            .onScrollPhaseChange { _, phase in
                guard !dragging else { return }
                phase == .idle ? scheduleHide() : reveal()
            }
            .overlay(alignment: .topTrailing) { thumb }
    }

    @ViewBuilder private var thumb: some View {
        if metrics.scrollable {
            Capsule()
                .fill(Color.primary.opacity(dragging ? 0.45 : 0.28))
                .frame(width: width, height: thumbHeight)
                .padding(.trailing, inset)
                .offset(y: thumbOffset)
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: visible)
                .contentShape(.rect)  // hit area is just this thin capsule strip, not the row width
                // Approaching the knob reveals it (like the native overlay), so it can be grabbed even
                // after it has faded out.
                .onHover { hovering in hovering ? reveal() : scheduleHideUnlessDragging() }
                .gesture(dragGesture)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let maxScroll = max(0, metrics.content - metrics.viewport)
                let travel = track - thumbHeight
                guard maxScroll > 0, travel > 0 else { return }
                let anchor = dragAnchor ?? metrics.offset
                dragAnchor = anchor
                reveal()
                // Map thumb travel (points along the track) back to content offset.
                let target = anchor + value.translation.height / travel * maxScroll
                scrollPos.scrollTo(y: min(maxScroll, max(0, target)))
            }
            .onEnded { _ in
                dragAnchor = nil
                scheduleHide()
            }
    }

    /// Usable vertical travel, inset a little from the top and bottom edges.
    private var track: CGFloat { max(0, metrics.viewport - inset * 2) }

    private var thumbHeight: CGFloat {
        guard metrics.content > 0 else { return minThumb }
        return min(track, max(minThumb, track * metrics.viewport / metrics.content))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(0, metrics.content - metrics.viewport)
        guard maxScroll > 0 else { return inset }
        let fraction = min(1, max(0, metrics.offset / maxScroll))
        return inset + fraction * (track - thumbHeight)
    }

    private func reveal() {
        fade?.cancel()
        visible = true
    }

    /// Fade out a beat after scrolling stops, like the native overlay scroller.
    private func scheduleHide() {
        fade?.cancel()
        fade = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }

    /// Hover-out shouldn't hide the knob mid-drag (the pointer routinely leaves the thin strip while
    /// dragging); the drag's own `onEnded` schedules the hide instead.
    private func scheduleHideUnlessDragging() {
        guard !dragging else { return }
        scheduleHide()
    }
}

extension View {
    /// Attach to a `ScrollView` for a thin SwiftUI scrollbar that appears only while scrolling.
    func thinScrollbar() -> some View {
        modifier(ThinScrollbar())
    }

    /// Attach *inside* a `ScrollView` (on its content) to remove the native scrollers, so our
    /// `thinScrollbar` is the only one shown. Scrolling via trackpad/wheel/keyboard is unaffected.
    func hideNativeScrollers() -> some View {
        background(NativeScrollerHider().frame(width: 0, height: 0))
    }
}

/// Clears the backing `NSScrollView`'s scrollers. `.scrollIndicators(.hidden)` alone can't hide a
/// *legacy* (always-on) scroller when the system setting is "Always show scroll bars", so we remove
/// them on the AppKit view directly — only the widget goes; scrollability stays.
///
/// It also switches the scroller *style* to `.overlay`. A legacy scroller reserves a fixed strip of
/// layout width on the trailing edge even after its widget is hidden; overlay scrollers float over the
/// content and reserve zero width. Without this the content keeps an empty right-hand gutter.
///
/// macOS re-derives the preferred scroller style at runtime (unlock, appearance change, a mouse being
/// plugged/unplugged) and posts `preferredScrollerStyleDidChangeNotification`; AppKit reacts by
/// resetting every scroll view back to that system style — which re-adds the legacy scroller under our
/// custom bar. We observe that notification and re-assert the overlay/hidden config, so the fix is
/// event-driven rather than a one-shot that silently regresses.
private struct NativeScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiderView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HiderView)?.applyOverlayStyle()
    }

    private final class HiderView: NSView {
        private var retriesLeft = 10
        private var styleChangeObserver: NSObjectProtocol?

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
        override init(frame: NSRect) { super.init(frame: frame) }

        deinit {
            if let styleChangeObserver { NotificationCenter.default.removeObserver(styleChangeObserver) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopObservingStyleChanges()
                return
            }
            startObservingStyleChanges()
            retriesLeft = 10  // fresh hierarchy on (re)attach — allow the splice a few ticks again
            applyOverlayStyle()
        }

        private func startObservingStyleChanges() {
            guard styleChangeObserver == nil else { return }
            styleChangeObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                // AppKit resets this scroll view to the system style *on* this notification; re-assert
                // ours on the next tick, after its own handler has run.
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
        }

        private func stopObservingStyleChanges() {
            guard let styleChangeObserver else { return }
            NotificationCenter.default.removeObserver(styleChangeObserver)
            self.styleChangeObserver = nil
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                // Not yet spliced into the scroll view's hierarchy; retry next tick, bounded so a
                // view that never lands in a scroll view can't busy-loop the main thread.
                guard retriesLeft > 0 else { return }
                retriesLeft -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            // Idempotent: bail once the scroll view is already in the target state so re-runs (update,
            // repeated notifications) are cheap and don't churn layout.
            guard scrollView.scrollerStyle != .overlay
                || scrollView.hasVerticalScroller
                || scrollView.hasHorizontalScroller else { return }
            scrollView.scrollerStyle = .overlay  // float over content — reserves no layout width
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            // Reclaim the trailing gutter a legacy scroller was reserving, on this same layout pass.
            scrollView.tile()
        }
    }
}
