import SwiftUI

/// Central design tokens for the palette UI, so visual tweaks happen in one place.
/// Values mirror Raycast v2's dark theme (see docs/raycast-design.md): the app forces
/// `.darkAqua`, so the ramps are literal white/black alphas rather than adaptive colors.
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
        static let panel: CGFloat = 26
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        static let menuPanel: CGFloat = 12
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 5
        static let control: CGFloat = 6
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        static let headerHeight: CGFloat = 64
        static let bottomBarHeight: CGFloat = 52
        static let rowHeight: CGFloat = 40
        static let rowIcon: CGFloat = 22
        static let keyCap: CGFloat = 20
        static let menuButton: CGFloat = 36
        static let clipboardListWidth: CGFloat = 290
        static let menuWidth: CGFloat = 240
        static let menuIcon: CGFloat = 16
        /// Settings window: sidebar column width and the small icon used in setting rows.
        static let settingsSidebar: CGFloat = 184
        static let settingsRowIcon: CGFloat = 20
    }

    enum Typography {
        static let searchField = Font.system(size: 18, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.system(size: 13)
        static let rowTrailing = Font.system(size: 13)
        static let sectionHeader = Font.system(size: 13, weight: .medium)
        static let keyCap = Font.system(size: 12)
        static let bar = Font.system(size: 13)
        static let menuRow = Font.system(size: 13)
        static let menuShortcut = Font.system(size: 12)
        static let menuIcon = Font.system(size: 13)
    }

    enum Colors {
        /// Black opacity of the panel's surface tint over the behind-window material — the
        /// whole "Raycast look" is this 40% black scrim over the desktop blur.
        static let panelDimming: CGFloat = 0.4
        /// Selection fill (Raycast: selection color @ 10% — white in the dark theme).
        static let selection = Color.white.opacity(0.10)
        /// Mouse hover — the fainter 5% layer, visually distinct from selection.
        static let rowHover = Color.white.opacity(0.05)
        static let menuHover = Color.white.opacity(0.10)
        /// 1px hairlines between the bars and the list (Raycast `--color-border-separator`).
        static let separator = Color.white.opacity(0.10)
        /// Action-bar wash (Raycast `--color-surface-action-bar`).
        static let barSurface = Color.white.opacity(0.05)
        /// Small control surfaces: kbd chips, glyph tiles (Raycast `--color-surface-control`).
        static let controlSurface = Color.white.opacity(0.10)
        /// Control borders: outlined kbd chips (Raycast `--color-border-token` = fg-20).
        static let border = Color.white.opacity(0.20)
        /// Text tiers below `.primary` (Raycast fg-60 / fg-40).
        static let textSecondary = Color.white.opacity(0.60)
        static let textTertiary = Color.white.opacity(0.40)
        /// Settings grouped "card": a faint raised surface whose hairline border doubles as the inset row divider.
        static let cardFill = Color.white.opacity(0.05)
        static let cardStroke = Color.white.opacity(0.10)
    }
}

/// A single keycap chip, shared by list rows and the bottom action bar. Raycast's two kbd
/// variants: `.outline` (1px white-20 border, no fill — hotkey hints on rows) and `.filled`
/// (white-10 fill, no border — footer shortcut chips).
struct KeyCapChip: View {
    enum Style {
        case outline
        case filled
    }

    let text: String
    var style: Style = .filled

    var body: some View {
        Text(text)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: Theme.Size.keyCap, minHeight: Theme.Size.keyCap)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                    .fill(style == .filled ? Theme.Colors.controlSurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                    .strokeBorder(
                        style == .outline ? Theme.Colors.border : Color.clear,
                        lineWidth: 1)
            )
    }
}

extension View {
    /// A floating Liquid Glass control surface (action group + menu button), interactive for native lensing and untinted via `.tint(.clear)`.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
            .tint(.clear)
    }
}
