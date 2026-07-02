import AppKit
import SwiftUI

/// A thin, auto-hiding overlay scrollbar drawn entirely in SwiftUI, tuned to feel like Raycast's: a
/// hairline thumb that appears while scrolling and fades out, plus a hover-reveal along the trailing
/// edge that fades in a subtle rail and fattens the thumb so it can be grabbed and dragged.
///
/// It's a pure floating overlay — no layout changes — and never reintroduces the native `NSScroller`
/// (whose overlay flashes on every panel re-show). Three independent interaction signals drive it;
/// `visible` and `expanded` are *derived* from them so hover, scroll and drag never clobber each other.
///
/// The SwiftUI layer only *draws*; every pointer interaction (hover, thumb drag, wheel) lives in one
/// AppKit view, `ScrollbarInteraction`. That split is deliberate, not incidental:
/// - Dragging must scroll the backing `NSScrollView` directly. `ScrollPosition.scrollTo(y:)` is
///   silently ignored on macOS once the user has scrolled manually (the position flips to
///   "positioned by user"), which froze the thumb.
/// - The thumb must not carry a SwiftUI gesture. One makes `NSHostingView.hitTest` claim that region,
///   and the hosting view is an *ancestor* of the `NSScrollView` — so wheel events over the thumb
///   bubbled up past the scroll view and died instead of scrolling.
struct ThinScrollbar: ViewModifier {
    private struct Metrics: Equatable {
        /// Raw `contentOffset.y` — equals the clip view's origin, so with `safeAreaInset` bars it is
        /// `-insetTop` at rest and tops out at `content − viewport − insetTop`. Normalize with
        /// `insetTop` before mapping to a track fraction, or the thumb never reaches the rail's end.
        var offset: CGFloat = 0
        var insetTop: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var scrollable: Bool { content > viewport + 1 }
    }

    // Interaction signals — kept separate so each source of "show the bar" is independent.
    @State private var isScrolling = false
    @State private var isHoveringTrack = false
    /// Mirrors the AppKit-side thumb drag (`ScrollbarInteraction` owns the actual drag state).
    @State private var isDragging = false

    @State private var metrics = Metrics()
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

    private var visible: Bool { isScrolling || isHoveringTrack || isDragging }
    private var expanded: Bool { isHoveringTrack || isDragging }

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)  // drop the native scroller (and its flash) entirely
            // Geometry drives the thumb's size/position; it changes on layout too, so it never
            // touches visibility.
            .onScrollGeometryChange(for: Metrics.self) { geo in
                Metrics(
                    offset: geo.contentOffset.y,
                    insetTop: geo.contentInsets.top,
                    content: geo.contentSize.height,
                    viewport: geo.containerSize.height
                )
            } action: { _, new in
                metrics = new
            }
            // Scrolling reveals the thumb (not the rail) and re-hides a beat after it stops.
            // A thumb drag scrolls the clip view directly (no user phase), so its handlers own
            // visibility.
            .onScrollPhaseChange { _, phase in
                guard !isDragging else { return }
                phase == .idle ? scheduleScrollStop() : beganScrolling()
            }
            .overlay(alignment: .topTrailing) { bar }
            // All pointer handling for the whole trailing strip, via one tracking view laid over
            // everything. It hit-tests as transparent except over the visible thumb, so content
            // clicks fall through; over the thumb it owns the drag and forwards wheel events to the
            // scroll view. Because it sits *above* the thumb, moving onto the thumb still reads as
            // "in zone" — so the rail never flickers the way a content-level SwiftUI hover did.
            .overlay {
                ScrollbarInteraction(
                    edgeWidth: hoverZone,
                    inset: inset,
                    thumbY: thumbOffset,
                    thumbHeight: thumbHeight,
                    thumbGrabbable: metrics.scrollable && visible,
                    railActive: metrics.scrollable && expanded,
                    onZoneChange: updateZone,
                    onDragChange: dragChanged
                )
            }
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

                // Thumb: proportional knob, thin at rest and fatter when expanded.
                Capsule()
                    .fill(Color.primary.opacity(isDragging ? 0.5 : (expanded ? 0.42 : 0.30)))
                    .frame(width: expanded ? expandedWidth : thinWidth, height: thumbHeight)
                    .frame(width: expandedWidth)
                    .offset(y: thumbOffset)
                    .opacity(visible ? 1 : 0)
            }
            .frame(width: expandedWidth)
            .padding(.trailing, inset)
            // Purely visual; ScrollbarInteraction above owns clicks, drags and wheel routing.
            .allowsHitTesting(false)
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
        let fraction = min(1, max(0, (metrics.offset + metrics.insetTop) / maxScroll))
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

    // MARK: - Drag signal

    private func dragChanged(_ dragging: Bool) {
        withAnimation(morphCurve) { isDragging = dragging }
        if dragging {
            scrollStop?.cancel()
        } else {
            // Linger like a normal scroll, then fade unless still hovering/scrolling.
            isScrolling = true
            scheduleScrollStop()
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

/// The single AppKit view that owns every pointer interaction for the scrollbar. Laid over the whole
/// scroll view (as a sibling of the backing `NSScrollView` inside the hosting view), it plays three
/// roles that must live in one place to avoid the SwiftUI/AppKit event-routing gaps described on
/// `ThinScrollbar`:
///
/// - **Hover**: an `NSTrackingArea` reports whether the pointer is within `edgeWidth` of the trailing
///   edge. Because this view sits above the thumb, the cursor resting *on* the thumb still reads as
///   "in zone" — flicker-free, unlike a content-level SwiftUI hover.
/// - **Thumb drag & track click**: `hitTest` returns `self` inside the thumb's grab strip while the
///   bar is visible, and over the whole trailing strip while the rail is expanded — so a click aimed
///   at the scrollbar can never fall through and activate the row beneath. A track click jumps the
///   thumb to the pointer (native "jump to spot") and continues as a drag. Scrolling is done on the
///   backing `NSScrollView`'s clip view directly — the one channel that always works, unlike
///   `ScrollPosition.scrollTo(y:)` after a manual scroll — and the legal offset range comes from
///   `NSClipView.constrainBoundsRect`, which accounts for the content insets that `safeAreaInset`
///   bars (palette header/footer) put on the scroll view. Raw `[0, content − viewport]` clamping is
///   wrong there: the at-rest origin is `-topInset`, and the bottom inset's travel would be lost.
/// - **Wheel**: owning those hit-tests means wheel events over the bar land here; they are forwarded
///   to the scroll view (an AppKit sibling the responder chain would otherwise skip).
private struct ScrollbarInteraction: NSViewRepresentable {
    let edgeWidth: CGFloat
    let inset: CGFloat
    let thumbY: CGFloat
    let thumbHeight: CGFloat
    let thumbGrabbable: Bool
    let railActive: Bool
    let onZoneChange: @MainActor (Bool) -> Void
    let onDragChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        InteractionView(onZoneChange: onZoneChange, onDragChange: onDragChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? InteractionView else { return }
        view.edgeWidth = edgeWidth
        view.inset = inset
        view.thumbY = thumbY
        view.thumbHeight = thumbHeight
        view.thumbGrabbable = thumbGrabbable
        view.railActive = railActive
        view.onZoneChange = onZoneChange
        view.onDragChange = onDragChange
    }

    private final class InteractionView: NSView {
        var edgeWidth: CGFloat = 0
        var inset: CGFloat = 0
        var thumbY: CGFloat = 0
        var thumbHeight: CGFloat = 0
        var thumbGrabbable = false
        var railActive = false
        var onZoneChange: @MainActor (Bool) -> Void
        var onDragChange: @MainActor (Bool) -> Void

        private var lastInZone = false
        /// Pointer y + content offset captured at `mouseDown`; non-nil only while dragging the thumb.
        private var dragStart: (pointerY: CGFloat, offset: CGFloat)?
        private weak var scrollView: NSScrollView?

        init(
            onZoneChange: @escaping @MainActor (Bool) -> Void,
            onDragChange: @escaping @MainActor (Bool) -> Void
        ) {
            self.onZoneChange = onZoneChange
            self.onDragChange = onDragChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // Match SwiftUI's top-down coordinates so `thumbY` can be used directly.
        override var isFlipped: Bool { true }

        // MARK: Hit testing

        /// Opaque over the visible thumb's grab strip, and over the whole trailing strip while the
        /// rail is expanded (so a click aimed at the scrollbar never activates the row beneath);
        /// transparent everywhere else so content clicks and wheel events fall straight through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            let p = convert(point, from: superview)
            if grabRect.contains(p) { return self }
            if railActive && p.x >= bounds.width - edgeWidth { return self }
            return nil
        }

        /// Full trailing-strip width (not just the drawn capsule) at the thumb's vertical span, so
        /// the hairline thumb is comfortably grabbable — like the fattened native overlay knob.
        private var grabRect: CGRect {
            guard thumbGrabbable else { return .null }
            return CGRect(
                x: bounds.width - edgeWidth, y: thumbY, width: edgeWidth, height: thumbHeight)
        }

        // MARK: Wheel routing

        /// We only receive wheel events when the cursor is over the bar (see `hitTest`); hand them
        /// to the scroll view, which the responder chain would otherwise bypass (it's a sibling).
        override func scrollWheel(with event: NSEvent) {
            if let target = targetScrollView() {
                target.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
        }

        // MARK: Thumb drag & track click

        override func mouseDown(with event: NSEvent) {
            guard let target = targetScrollView() else { return }
            let p = convert(event.locationInWindow, from: nil)
            // Track click (outside the thumb's span): jump so the thumb centers on the pointer,
            // *then* anchor — the click seamlessly continues as a drag of the jumped-to thumb.
            if !(thumbY...(thumbY + thumbHeight)).contains(p.y) {
                jumpThumb(toPointerY: p.y, in: target)
            }
            dragStart = (p.y, target.contentView.bounds.origin.y)
            onDragChange(true)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart, let target = targetScrollView() else { return }
            let (minOffset, maxOffset) = offsetRange(of: target.contentView)
            let travel = trackTravel
            guard maxOffset > minOffset, travel > 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            // Map thumb travel (points along the track) back to content offset, anchored at the
            // mouse-down state so clamped over-drags don't accumulate drift.
            let offset =
                dragStart.offset + (p.y - dragStart.pointerY) / travel * (maxOffset - minOffset)
            scroll(target, toOffset: min(maxOffset, max(minOffset, offset)))
        }

        override func mouseUp(with event: NSEvent) {
            guard dragStart != nil else { return }
            dragStart = nil
            onDragChange(false)
        }

        /// Thumb travel in track points: the rail's height minus the thumb.
        private var trackTravel: CGFloat { (bounds.height - inset * 2) - thumbHeight }

        /// Scroll so the thumb's center lands on the given pointer y (clamped to the track).
        private func jumpThumb(toPointerY y: CGFloat, in target: NSScrollView) {
            let (minOffset, maxOffset) = offsetRange(of: target.contentView)
            let travel = trackTravel
            guard maxOffset > minOffset, travel > 0 else { return }
            let thumbTop = min(inset + travel, max(inset, y - thumbHeight / 2))
            let fraction = (thumbTop - inset) / travel
            scroll(target, toOffset: minOffset + fraction * (maxOffset - minOffset))
        }

        /// The clip view's legal `bounds.origin.y` range, via AppKit's own constraint logic. This is
        /// what makes the drag inset-correct: with `safeAreaInset` bars the at-rest origin is
        /// `-topInset` and the max extends past `content − viewport` by the bottom inset — a raw
        /// `[0, content − viewport]` clamp snaps content under the header and can't reach the end.
        private func offsetRange(of clip: NSClipView) -> (min: CGFloat, max: CGFloat) {
            var probe = clip.bounds
            probe.origin.y = -1_000_000_000
            let minY = clip.constrainBoundsRect(probe).origin.y
            probe.origin.y = 1_000_000_000
            let maxY = clip.constrainBoundsRect(probe).origin.y
            return (minY, maxY)
        }

        private func scroll(_ target: NSScrollView, toOffset y: CGFloat) {
            let clip = target.contentView
            var origin = clip.bounds.origin
            origin.y = y
            clip.scroll(to: origin)
            target.reflectScrolledClipView(clip)
        }

        /// The `NSScrollView` backing the SwiftUI `ScrollView` this overlay covers. As an overlay we
        /// are its sibling, not its descendant, so `enclosingScrollView` can't find it — walk up and
        /// take the nearest scroll view in a surrounding subtree, cached weakly across events.
        private func targetScrollView() -> NSScrollView? {
            if let scrollView, scrollView.window === window { return scrollView }
            var branch: NSView = self
            var node = superview
            while let ancestor = node {
                if let found = Self.firstScrollView(under: ancestor, excluding: branch) {
                    scrollView = found
                    return found
                }
                branch = ancestor
                node = ancestor.superview
            }
            return nil
        }

        private static func firstScrollView(under view: NSView, excluding: NSView?) -> NSScrollView?
        {
            for sub in view.subviews where sub !== excluding {
                if let scroll = sub as? NSScrollView { return scroll }
                if let scroll = firstScrollView(under: sub, excluding: nil) { return scroll }
            }
            return nil
        }

        // MARK: Hover tracking

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // `.inVisibleRect` keeps the area pinned to the (resizing) bounds; the rect arg is
            // ignored. `.activeAlways` so hover reveals the rail in non-key windows too (Settings/
            // About behind another window), like the native overlay scroller.
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [
                        .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect,
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
