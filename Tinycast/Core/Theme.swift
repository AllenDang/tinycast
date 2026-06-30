import SwiftUI

/// Central design tokens for the palette UI. Spacing, sizing, radii, typography and colors live
/// here so the look stays consistent and visual tweaks happen in one place.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
    }

    enum Radius {
        static let panel: CGFloat = 24
        static let row: CGFloat = 8
        static let menu: CGFloat = 6
        static let menuPanel: CGFloat = 14
        static let thumbnail: CGFloat = 4
    }

    enum Size {
        static let panelWidth: CGFloat = 720
        static let panelHeight: CGFloat = 470
        static let headerHeight: CGFloat = 54
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 24
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
        static let sectionHeader = Font.subheadline.weight(.semibold)
        static let keyCap = Font.caption
        static let pill = Font.body.weight(.medium)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
    }

    enum Colors {
        /// Raycast-style selection: a soft, neutral translucent fill (not a saturated accent
        /// block). In the always-dark palette this reads as a gentle lighter row. The same token
        /// is shared by the launcher and clipboard so the two lists look identical.
        static let selection = Color.primary.opacity(0.12)
        /// Mouse hover — a fainter layer that follows the cursor, visually distinct from selection.
        static let rowHover = Color.primary.opacity(0.06)
        static let menuHover = Color.primary.opacity(0.10)
    }
}

extension View {
    /// A floating Tahoe Liquid Glass control surface (the action pill + menu button). The glass
    /// sits over the app list, so `.interactive()` gives the native lensing/press response and
    /// `.tint(.clear)` keeps the material untinted on macOS.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
            .tint(.clear)
    }
}
