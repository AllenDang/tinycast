import SwiftUI

struct ClipboardList: View {
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem) -> Void
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { item in
                        ClipboardRow(item: item, selected: item.id == selectedID, imageURL: store.imageURL(for: item))
                            .contentShape(Rectangle())
                            // Single click selects *instantly* — the double-click-to-paste gesture
                            // is `.simultaneousGesture`, so the single tap never waits on the
                            // double-click timeout to disambiguate. Right-click uses the lightweight
                            // catcher — not SwiftUI's `.contextMenu`, which stalls clicks for
                            // seconds inside a LazyVStack on macOS.
                            .onTapGesture { onSelect(item) }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                onSelect(item); onActivate()
                            })
                            .onRightClick { onActions(item) }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// Actions popover for a clipboard entry — shown anchored bottom-right on right-click, mirroring the
/// launcher's `AppActionsMenu`. Same stock Liquid Glass `PopoverMenu` surface.
struct ClipboardActionsMenu: View {
    let item: ClipboardItem
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var store: ClipboardStore

    private var headerText: String {
        switch item.kind {
        case .text:
            // Collapse all whitespace/newlines to single spaces so a multi-line copy stays a clean
            // one-line title.
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return String(oneLine.prefix(40))
        case .image: return "Image"
        }
    }

    var body: some View {
        PopoverMenu(header: headerText) {
            PopoverMenuRow(title: "Paste", systemImage: "doc.on.clipboard", shortcut: "↵") {
                core.paste(item); dismiss()
            }
            PopoverMenuRow(title: "Copy to Clipboard", systemImage: "doc.on.doc") {
                core.copyToClipboard(item); dismiss()
            }
            PopoverMenuRow(title: "Paste & Keep Window Open", systemImage: "pin") {
                core.pasteKeepingWindowOpen(item); dismiss()
            }
            if item.kind == .image {
                PopoverMenuRow(title: "Show in Finder", systemImage: "folder") {
                    core.revealClipboardImage(item); dismiss()
                }
            }
            PopoverMenuRow(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                store.remove(item); dismiss()
            }
            PopoverMenuRow(title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true) {
                store.clearAll(); dismiss()
            }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail
            Text(previewText)
                .font(Theme.Typography.menuRow)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 1)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : Color.clear)
        )
    }

    private var previewText: String {
        switch item.kind {
        // Single-line row, so cap before trimming — never walk a multi-MB clipboard string per row.
        case .text: return String((item.text ?? "").prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return "Image"
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .symbolRenderingMode(.hierarchical)
                .frame(width: 26, height: 20)
                .foregroundStyle(.secondary)
        case .image:
            if let url = imageURL, let image = ImageThumbnail.load(url, maxPixel: 64) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
            } else {
                Image(systemName: "photo")
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 26, height: 20)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ClipboardPreview: View {
    let item: ClipboardItem?
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer(for: item)
            }
            .padding(16)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image:
            if let url = store.imageURL(for: item), let image = ImageThumbnail.load(url, maxPixel: 1200) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func footer(for item: ClipboardItem) -> some View {
        HStack {
            Text(metadata(for: item))
            Spacer()
            Text("\(item.createdAt, style: .relative) ago")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private func metadata(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let count = (item.text ?? "").count
            return "Text · \(count) character\(count == 1 ? "" : "s")"
        case .image:
            if let url = store.imageURL(for: item), let size = ImageThumbnail.pixelSize(of: url) {
                return "Image · \(Int(size.width))×\(Int(size.height))"
            }
            return "Image"
        }
    }
}
