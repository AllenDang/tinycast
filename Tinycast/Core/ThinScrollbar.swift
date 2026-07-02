import AppKit
import SwiftUI

/// A thin, auto-hiding overlay scrollbar drawn entirely in SwiftUI, tuned to feel like Raycast's: a
/// hairline thumb that appears while scrolling and fades out, plus a hover-reveal along the trailing
/// edge that fades in a subtle rail and fattens the thumb so it can be grabbed and dragged.
///
/// It's a pure floating overlay — no layout changes — and never reintroduces the native `NSScroller`
/// (whose overlay flashes on every panel re-show). Three independent interaction signals drive it;
/// `visible` and `expanded` are *derived* from them so hover, scroll and drag never clobber each other.
struct ThinScrollbar: ViewModifier {
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var scrollable: Bool { content > viewport + 1 }
    }

    // Interaction signals — kept separate so each source of "show the bar" is independent.
    @State private var isScrolling = false
    @State private var isHoveringTrack = false
    /// Content offset captured when a thumb drag begins; non-nil only while dragging (`isDragging`).
    @State private var dragAnchor: CGFloat?

    @State private var metrics = Metrics()
    @State private var scrollPos = ScrollPosition(idType: Never.self)
    /// Instantaneous "pointer is in the trailing hover zone" mirror, for edge-transition detection.
    @State private var inZone = false
    @State private var scrollStop: Task<Void, Never>?
    @State private var hoverExit: Task<Void, Never>?

    // Knob/rail geometry: thin at rest, fatter on hover/drag — like the macOS overlay knob.
    private let thinWidth: CGFloat = 6
    private let expandedWidth: CGFloat = 10
    private let inset: CGFloat = 3
    private let minThumb: CGFloat = 28
    private let hoverZone: CGFloat = 16  // trailing strip that reveals the rail; wider than the thumb

    // Animation curves shared across the interaction transitions.
    private let fadeCurve: Animation = .easeOut(duration: 0.18)
    private let morphCurve: Animation = .spring(response: 0.28, dampingFraction: 0.85)

    private var isDragging: Bool { dragAnchor != nil }
    private var visible: Bool { isScrolling || isHoveringTrack || isDragging }
    private var expanded: Bool { isHoveringTrack || isDragging }

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
            // Scrolling reveals the thumb (not the rail) and re-hides a beat after it stops.
            // A thumb drag scrolls programmatically (no user phase), so its handlers own visibility.
            .onScrollPhaseChange { _, phase in
                guard !isDragging else { return }
                phase == .idle ? scheduleScrollStop() : beganScrolling()
            }
            .overlay(alignment: .topTrailing) { bar }
            // Hover for the whole trailing strip, via a click-transparent tracking view laid over
            // everything. Because it sits *above* the thumb (yet passes clicks/drags through), moving
            // onto the thumb still reads as "in zone" — so the rail no longer flickers the way a
            // content-level SwiftUI hover did when the thumb overlay stole the hover.
            .overlay { PointerEdgeTracker(edgeWidth: hoverZone, onZoneChange: updateZone) }
    }

    @ViewBuilder private var bar: some View {
        if metrics.scrollable {
            ZStack(alignment: .top) {
                // Rail: a faint full-height track, present only while hovering/dragging.
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: expandedWidth, height: track)
                    .offset(y: inset)
                    .opacity(expanded ? 1 : 0)

                // Thumb: proportional knob, thin at rest and fatter when expanded. The outer frame keeps
                // the grab area the full strip width even while the visible capsule is hairline-thin.
                Capsule()
                    .fill(Color.primary.opacity(isDragging ? 0.5 : (expanded ? 0.42 : 0.30)))
                    .frame(width: expanded ? expandedWidth : thinWidth, height: thumbHeight)
                    .frame(width: expandedWidth)
                    .offset(y: thumbOffset)
                    .opacity(visible ? 1 : 0)
                    .contentShape(.rect)  // hit area is just this thin strip, not the row width
                    .gesture(dragGesture)
            }
            .frame(width: expandedWidth)
            .padding(.trailing, inset)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let maxScroll = max(0, metrics.content - metrics.viewport)
                let travel = track - thumbHeight
                guard maxScroll > 0, travel > 0 else { return }
                let anchor = dragAnchor ?? metrics.offset
                // Expand once, on the first change; the offset updates below stay un-animated so the
                // knob tracks the pointer instantly.
                if dragAnchor == nil { withAnimation(morphCurve) { dragAnchor = anchor } }
                // Map thumb travel (points along the track) back to content offset.
                let target = anchor + value.translation.height / travel * maxScroll
                scrollPos.scrollTo(y: min(maxScroll, max(0, target)))
            }
            .onEnded { _ in
                withAnimation(morphCurve) { dragAnchor = nil }
                // Linger like a normal scroll, then fade unless still hovering/scrolling.
                isScrolling = true
                scheduleScrollStop()
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

    // MARK: - Scroll signal

    private func beganScrolling() {
        scrollStop?.cancel()
        withAnimation(fadeCurve) { isScrolling = true }
    }

    /// Fade the thumb out a beat after scrolling stops, like the native overlay scroller.
    private func scheduleScrollStop() {
        scrollStop?.cancel()
        scrollStop = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(fadeCurve) { isScrolling = false }
        }
    }

    // MARK: - Hover signal

    /// Called on every pointer move; acts only on the in-zone ⇄ out-of-zone *transition*.
    private func updateZone(_ nowInZone: Bool) {
        guard nowInZone != inZone else { return }
        inZone = nowInZone
        if nowInZone {
            hoverExit?.cancel()
            withAnimation(morphCurve) { isHoveringTrack = true }
        } else {
            scheduleHoverExit()
        }
    }

    /// Leaving the zone collapses the rail after a short delay, so brief exits don't flicker it.
    private func scheduleHoverExit() {
        hoverExit?.cancel()
        hoverExit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(morphCurve) { isHoveringTrack = false }
        }
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
            if let styleChangeObserver {
                NotificationCenter.default.removeObserver(styleChangeObserver)
            }
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
            guard
                scrollView.scrollerStyle != .overlay
                    || scrollView.hasVerticalScroller
                    || scrollView.hasHorizontalScroller
            else { return }
            scrollView.scrollerStyle = .overlay  // float over content — reserves no layout width
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            // Reclaim the trailing gutter a legacy scroller was reserving, on this same layout pass.
            scrollView.tile()
        }
    }
}

/// A click-transparent AppKit tracking view that reports whether the pointer is within `edgeWidth`
/// points of the trailing edge. It overrides `hitTest` to return `nil`, so it never intercepts clicks
/// or the thumb drag (events fall through to the views beneath), yet its `NSTrackingArea` still delivers
/// pointer moves. That combination is what makes the hover flicker-free: laid over the whole scroll
/// view — above the thumb — it keeps reading "in zone" even while the cursor is on the thumb, which a
/// content-level SwiftUI hover cannot do (the thumb overlay steals the hover and the rail oscillates).
private struct PointerEdgeTracker: NSViewRepresentable {
    let edgeWidth: CGFloat
    let onZoneChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        TrackerView(edgeWidth: edgeWidth, onZoneChange: onZoneChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? TrackerView else { return }
        view.edgeWidth = edgeWidth
        view.onZoneChange = onZoneChange
    }

    private final class TrackerView: NSView {
        var edgeWidth: CGFloat
        var onZoneChange: @MainActor (Bool) -> Void
        private var lastInZone = false

        init(edgeWidth: CGFloat, onZoneChange: @escaping @MainActor (Bool) -> Void) {
            self.edgeWidth = edgeWidth
            self.onZoneChange = onZoneChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // Transparent to the click/drag hit-test — pointer-down events fall through to the thumb and rows.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // `.inVisibleRect` keeps the area pinned to the (resizing) bounds; the rect arg is ignored.
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [
                        .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
                    ],
                    owner: self
                ))
        }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { update(inZone: false) }

        private func report(_ event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            update(inZone: x >= bounds.width - edgeWidth)
        }

        /// Fire the callback only on a zone transition, so a stream of `mouseMoved`s stays cheap.
        private func update(inZone: Bool) {
            guard inZone != lastInZone else { return }
            lastInZone = inZone
            onZoneChange(inZone)
        }
    }
}
