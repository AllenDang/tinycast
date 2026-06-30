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
        static let panel: CGFloat = 20
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

    enum Typography {
        static let searchField = Font.system(size: 18, weight: .regular)
        static let headerIcon = Font.system(size: 17)
        static let rowTitle = Font.system(size: 14)
        static let rowTrailing = Font.system(size: 12)
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        static let pill = Font.system(size: 13, weight: .medium)
        static let menuRow = Font.system(size: 13)
        static let menuShortcut = Font.system(size: 12)
        static let menuIcon = Font.system(size: 13)
    }

    enum Colors {
        static let hairline = Color.white.opacity(0.10)
        static let panelTint = Color.black.opacity(0.10)
        /// Keyboard selection — the stronger highlight; what Enter activates.
        static let rowSelection = Color.primary.opacity(0.10)
        /// Mouse hover — a fainter, visually distinct layer that follows the cursor (Raycast-style).
        static let rowHover = Color.primary.opacity(0.05)
        static let clipSelection = Color.accentColor.opacity(0.22)
        static let menuHover = Color.primary.opacity(0.12)
    }

    enum Opacity {
        static let divider = 0.08
        static let previewDivider = 0.35
    }
}

extension View {
    /// A stock Tahoe Liquid Glass control surface. `.interactive()` gives the native lensing +
    /// hover/press response of the Control Center toggles — no hand-drawn material or border.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}
