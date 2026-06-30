import SwiftUI

/// Central design tokens for the palette UI. Spacing, sizing, radii, typography and colors live
/// here so the look stays consistent and visual tweaks happen in one place.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let xl: CGFloat = 14
        static let xxl: CGFloat = 20
    }

    enum Radius {
        static let panel: CGFloat = 22
        static let row: CGFloat = 8
        static let menu: CGFloat = 6
        static let menuPanel: CGFloat = 13
        static let thumbnail: CGFloat = 4
    }

    enum Size {
        static let panelWidth: CGFloat = 720
        static let panelHeight: CGFloat = 470
        static let headerHeight: CGFloat = 54
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 22
        static let menuButton: CGFloat = 36
        static let clipboardListWidth: CGFloat = 290
        static let menuWidth: CGFloat = 240
        static let menuIcon: CGFloat = 16
    }

    /// System text styles (not hardcoded point sizes) so the UI honors Dynamic Type and matches
    /// the metrics of first-party macOS apps.
    enum Typography {
        static let searchField = Font.title2
        static let headerIcon = Font.title2
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.caption.weight(.semibold)
        static let pill = Font.body.weight(.medium)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
    }

    enum Colors {
        /// Spotlight/Finder-style selection: a filled row in the system accent color. The same
        /// token is used by the launcher and clipboard so the two lists read identically.
        static let selection = Color.accentColor
        /// Mouse hover — a fainter, visually distinct layer that follows the cursor (Raycast-style),
        /// kept neutral so it never competes with the accent selection.
        static let rowHover = Color.primary.opacity(0.06)
        static let menuHover = Color.primary.opacity(0.08)
    }
}

extension View {
    /// A stock Tahoe Liquid Glass control surface. `.interactive()` gives the native lensing +
    /// hover/press response of the Control Center toggles — no hand-drawn material or border.
    /// `.tint(.clear)` is required on macOS for glass controls to render with the correct,
    /// untinted material.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
            .tint(.clear)
    }
}
