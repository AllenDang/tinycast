import SwiftUI

/// Alpha dissolve at a scroll view's top/bottom edges: rows melt to transparent as they slide
/// under the floating search header and action bar, which are transparent overlays — the dissolve
/// *is* the edge, no divider. Rows stay ghosted through the bar's text zone, Raycast-style, and
/// vanish only past it.
struct EdgeDissolveMask: ViewModifier {
    /// Band heights match the bars' occupied heights (= the safe-area insets), so at rest the
    /// first/last rows sit exactly at full alpha and only content sliding under a bar dissolves.
    /// The top band borrows the list's own top padding so the ramp ends exactly at the first
    /// at-rest row instead of a few points above it.
    var topFade: CGFloat = Theme.Size.headerHeight + Theme.Spacing.md + Theme.Spacing.xs
    /// Shorter and gentler than the top, like the old bottom blur was.
    var bottomFade: CGFloat = Theme.Size.bottomBarHeight - Theme.Spacing.md

    /// Ramp stops as (fraction of the band from that edge, alpha). Rows stay ghosted through the
    /// search-text zone (like Raycast) and reach full transparency only above the text line.
    private static let top: [(CGFloat, CGFloat)] = [
        (0.00, 0.00), (0.15, 0.02), (0.30, 0.10), (0.45, 0.25),
        (0.60, 0.45), (0.75, 0.68), (0.90, 0.90), (1.00, 1.00),
    ]
    private static let bottom: [(CGFloat, CGFloat)] = [
        (0.00, 0.00), (0.16, 0.05), (0.28, 0.14), (0.40, 0.30),
        (0.55, 0.55), (0.70, 0.78), (0.85, 0.93), (1.00, 1.00),
    ]

    func body(content: Content) -> some View {
        content.mask(
            // The mask must span the scroll view's *full* frame — the bars' safe-area insets would
            // otherwise shift the gradient inward, landing the fade bands on at-rest rows and
            // clipping the underlap regions to black.
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
        let height = max(height, topFade + bottomFade)
        var out: [Gradient.Stop] = Self.top.map { (fraction, alpha) in
            .init(color: .black.opacity(alpha), location: fraction * topFade / height)
        }
        out.append(.init(color: .black, location: 1 - bottomFade / height))
        out += Self.bottom.reversed().map { (fraction, alpha) in
            .init(color: .black.opacity(alpha), location: 1 - fraction * bottomFade / height)
        }
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
