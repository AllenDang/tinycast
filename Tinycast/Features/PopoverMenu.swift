import SwiftUI

/// Raycast-style menu, reused by the bottom-left app menu and the row actions menu. Rendered as an
/// in-window overlay anchored to a bottom corner (not a system popover), so it stays clipped inside
/// the palette. The surface is stock Tahoe Liquid Glass so it reads like a native macOS menu.
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
        // Tahoe glass carries its own elevation/shadow; a hand-tuned drop shadow on top of the
        // newer, more opaque material reads heavy and non-native, so we let the glass own it.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous))
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
                    .symbolRenderingMode(.hierarchical)
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
