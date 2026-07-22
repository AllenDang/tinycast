import SwiftUI

/// One popover-menu row's data: the render path and the keyboard handlers both address rows through these, so a selection index can drive highlight and activation. Actions are pure — closing the menu is the caller's job (one central `onActivate`).
struct PopoverMenuItem {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    /// Destructive rows (delete) tint their icon + label red, matching the native menu convention.
    var isDestructive: Bool = false
    let action: () -> Void
}

/// A popover menu's header + rows, built once per feature and consumed by both the render path and `RootPaletteView`'s keyboard handlers.
struct PopoverMenuContent {
    var header: String? = nil
    let items: [PopoverMenuItem]
}

/// In-window overlay menu (not a system popover), anchored to a bottom corner so it stays clipped inside the palette, with a stock Liquid Glass surface. Data-driven so `selection` can highlight a row for keyboard navigation; `onActivate(index)` is the single path fired by both a click and Return.
struct PopoverMenu: View {
    var header: String? = nil
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.xs / 2)
            }
            // Index-as-id is stable because a menu's rows never reorder while it is open, and the index is what selection/activation address.
            ForEach(items.indices, id: \.self) { index in
                PopoverMenuRow(
                    item: items[index],
                    selected: index == selection,
                    onHover: { selection = index },
                    onActivate: { onActivate(index) }
                )
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: Theme.Size.menuWidth)
        // Tahoe glass carries its own elevation/shadow; a hand-tuned drop shadow on top reads heavy and non-native, so we let the glass own it.
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }
}

/// A single menu row: leading SF Symbol, label, optional trailing shortcut glyph. Highlight is selection-driven (hover reports up so keyboard and mouse converge on one highlight), so there is never more than one active row.
private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    /// Fired when the cursor enters the row so the owner can move selection here — keyboard and mouse then share one highlight.
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: item.systemImage)
                    .font(Theme.Typography.menuIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                    .frame(width: Theme.Size.menuIcon)
                Text(item.title)
                    .font(Theme.Typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                Spacer(minLength: Theme.Spacing.sm)
                if let shortcut = item.shortcut {
                    HStack(spacing: Theme.Spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            // Pin the content height to the keycap height so rows with and without a shortcut share one row height.
            .frame(minHeight: Theme.Size.keyCap)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { if $0 { onHover() } }
    }
}
