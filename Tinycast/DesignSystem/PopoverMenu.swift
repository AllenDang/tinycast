import SwiftUI

enum PopoverMenuIcon: Equatable {
    case symbol(String)
    case file(path: String)

    static func paste(_ target: PasteTarget?, fallback: String) -> PopoverMenuIcon {
        guard let path = target?.iconPath else { return .symbol(fallback) }
        return .file(path: path)
    }
}

struct PopoverMenuItem {
    let title: String
    let icon: PopoverMenuIcon
    var shortcut: String?
    /// Destructive rows (delete) tint their icon + label red, matching the native menu convention.
    var isDestructive: Bool = false
    let action: () -> Void

    init(
        title: String, icon: PopoverMenuIcon, shortcut: String? = nil, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.isDestructive = isDestructive
        self.action = action
    }

    init(
        title: String, systemImage: String, shortcut: String? = nil, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), shortcut: shortcut,
            isDestructive: isDestructive, action: action)
    }
}

struct PopoverMenuContent {
    var header: String?
    let items: [PopoverMenuItem]
}

struct PopoverMenu: View {
    var header: String?
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
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }
}

private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: Theme.Spacing.sm) {
                switch item.icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(Theme.Typography.menuIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                        .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                }
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

private struct MenuFileIcon: View {
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cached(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
        .task(id: path) {
            guard image == nil else { return }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}
