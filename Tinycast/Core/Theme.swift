import SwiftUI

/// Central design tokens for the palette UI, so visual tweaks happen in one place.
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
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 480
        static let headerHeight: CGFloat = 44
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 24
        static let menuButton: CGFloat = 36
        static let clipboardListWidth: CGFloat = 290
        static let menuWidth: CGFloat = 240
        static let menuIcon: CGFloat = 16
        /// Settings window: sidebar column width and the small icon used in setting rows.
        static let settingsSidebar: CGFloat = 184
        static let settingsRowIcon: CGFloat = 20
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let searchField = Font.system(size: 20, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
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
        /// Selection fill: a soft neutral translucent layer shared by launcher and clipboard so both lists look identical.
        static let selection = Color.primary.opacity(0.12)
        /// Mouse hover — a fainter layer that follows the cursor, visually distinct from selection.
        static let rowHover = Color.primary.opacity(0.06)
        static let menuHover = Color.primary.opacity(0.10)
        /// Settings grouped "card": a faint raised surface whose hairline border doubles as the inset row divider.
        static let cardFill = Color.primary.opacity(0.04)
        static let cardStroke = Color.primary.opacity(0.08)
    }
}

extension View {
    /// A floating Liquid Glass control surface (action pill + menu button), interactive for native lensing and untinted via `.tint(.clear)`.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
            .tint(.clear)
    }
}
