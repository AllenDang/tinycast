import SwiftUI

/// Raycast's scroll-driven edge dissolve, applied to a scroll view that underlaps the palette's
/// transparent floating bars: at rest there is no fade at all (rows sit below/above the bars);
/// once content scrolls under a bar it ghosts through a soft alpha ramp whose midpoint slides
/// inward with scroll distance and whose alpha floors at 15% (top) / 25% (bottom) — rows stay
/// readable under the bars, sharp but translucent, and vanish only at the window edge.
/// (Mirrors Raycast v2's `scroll-area` mask math, see docs/raycast-design.md §4.)
struct EdgeDissolveMask: ViewModifier {
    /// Fade zones cover the bars' occupied heights (= the safe-area insets), so the ramp spans
    /// exactly the region where rows slide beneath a bar.
    var topFade: CGFloat = Theme.Size.headerHeight
    var bottomFade: CGFloat = Theme.Size.bottomBarHeight
    private static let topMinAlpha: CGFloat = 0.15
    private static let bottomMinAlpha: CGFloat = 0.25

    /// How much content is hidden beyond each edge, 0 when the list rests against it.
    @State private var topDistance: CGFloat = 0
    @State private var bottomDistance: CGFloat = 0

    private struct Distances: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Distances.self) { geo in
                Distances(
                    top: geo.contentOffset.y + geo.contentInsets.top,
                    bottom: geo.contentSize.height + geo.contentInsets.bottom
                        - geo.containerSize.height - geo.contentOffset.y
                )
            } action: { _, new in
                topDistance = max(0, new.top)
                bottomDistance = max(0, new.bottom)
            }
            .mask(
                // The mask must span the scroll view's *full* frame — the bars' safe-area insets
                // would otherwise shift the gradient inward, landing the fade bands on at-rest
                // rows and clipping the underlap regions to black.
                GeometryReader { geo in
                    LinearGradient(
                        stops: stops(height: geo.size.height),
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            )
    }

    private func stops(height: CGFloat) -> [Gradient.Stop] {
        guard height > 0 else { return [.init(color: .black, location: 0)] }
        var out: [Gradient.Stop] = []
        // progress 0 → no fade (opaque to the very edge); progress 1 → transparent edge ramping
        // through the floored alpha at the sliding midpoint to opaque at the fade height.
        let topProgress = min(topDistance / topFade, 1)
        out.append(.init(color: .black.opacity(1 - topProgress), location: 0))
        if topProgress > 0 {
            let alpha = 1 - (1 - Self.topMinAlpha) * topProgress
            out.append(
                .init(color: .black.opacity(alpha), location: topFade / 2 * topProgress / height))
            out.append(.init(color: .black, location: topFade / height))
        }
        let bottomProgress = min(bottomDistance / bottomFade, 1)
        if bottomProgress > 0 {
            let alpha = 1 - (1 - Self.bottomMinAlpha) * bottomProgress
            out.append(.init(color: .black, location: 1 - bottomFade / height))
            out.append(
                .init(
                    color: .black.opacity(alpha),
                    location: 1 - bottomFade / 2 * bottomProgress / height))
        }
        out.append(.init(color: .black.opacity(1 - bottomProgress), location: 1))
        return out
    }
}

extension View {
    /// Attach to a `ScrollView` that underlaps the palette's floating bars (before `thinScrollbar`,
    /// so the scrollbar overlay stays unmasked).
    func edgeDissolve() -> some View {
        modifier(EdgeDissolveMask())
    }
}
