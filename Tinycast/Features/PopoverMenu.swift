import SwiftUI

/// Raycast-style popover menu chrome, reused by the bottom-left app menu and the row actions menu.
/// Presented inside a SwiftUI `.popover`, whose vibrancy gives the translucent rounded panel.
struct PopoverMenu<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.xs / 2)
            }
            content
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.Size.menuWidth)
    }
}

/// A single menu row: leading SF Symbol, label, optional trailing shortcut glyph, hover highlight.
struct PopoverMenuRow: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.menuIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.menuIcon)
                Text(title)
                    .font(Theme.Typography.menuRow)
                Spacer(minLength: Theme.Spacing.sm)
                if let shortcut {
                    Text(shortcut)
                        .font(Theme.Typography.menuShortcut)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(hovering ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
