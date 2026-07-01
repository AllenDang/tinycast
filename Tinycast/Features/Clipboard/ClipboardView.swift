import SwiftUI

struct ClipboardList: View {
    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    /// Changes only when the list should scroll to follow the selection (keyboard nav / reset), so
    /// mouse selection never yanks the scroll position.
    let scrollToken: UUID
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem) -> Void
    @EnvironmentObject private var store: ClipboardStore

    private enum Row: Identifiable {
        case header(String)
        case item(ClipboardItem)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .item(let item): return item.id.uuidString
            }
        }
    }

    /// Items are newest-first, so grouping is just a walk that emits a date header whenever the
    /// bucket changes — mirrors the launcher's Favorites/Applications sectioning.
    private var rows: [Row] {
        var rows: [Row] = []
        var currentBucket: DateBucket?
        for item in results {
            let bucket = DateBucket(for: item.createdAt)
            if bucket != currentBucket {
                rows.append(.header(bucket.title))
                currentBucket = bucket
            }
            rows.append(.item(item))
        }
        return rows
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title)
                        case .item(let item):
                            ClipboardRow(
                                item: item, selected: item.id == selectedID,
                                imageURL: store.imageURL(for: item)
                            )
                            .contentShape(Rectangle())
                            // Single click selects *instantly* — the double-click-to-paste gesture
                            // is `.simultaneousGesture`, so the single tap never waits on the
                            // double-click timeout to disambiguate. Right-click uses the lightweight
                            // catcher — not SwiftUI's `.contextMenu`, which stalls clicks for
                            // seconds inside a LazyVStack on macOS.
                            .onTapGesture { onSelect(item) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(item)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(item) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .thinOverlayScrollbar()
            }
            .onChange(of: scrollToken) {
                if let selectedID { proxy.scrollTo(selectedID.uuidString, anchor: .center) }
            }
        }
    }
}

/// Coarse date buckets for grouping clipboard entries into sections, mirroring Raycast's
/// Today / Yesterday / This Week / … history grouping. Ordered newest-first by raw value.
private enum DateBucket: Int {
    case today, yesterday, thisWeek, thisMonth, earlier

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
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
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            return String(oneLine.prefix(40))
        case .image: return "Image"
        }
    }

    var body: some View {
        PopoverMenu(header: headerText) {
            PopoverMenuRow(title: "Paste", systemImage: "doc.on.clipboard", shortcut: "↵") {
                core.paste(item)
                dismiss()
            }
            PopoverMenuRow(title: "Copy to Clipboard", systemImage: "doc.on.doc") {
                core.copyToClipboard(item)
                dismiss()
            }
            PopoverMenuRow(title: "Paste & Keep Window Open", systemImage: "pin") {
                core.pasteKeepingWindowOpen(item)
                dismiss()
            }
            if item.kind == .image {
                PopoverMenuRow(title: "Show in Finder", systemImage: "folder") {
                    core.revealClipboardImage(item)
                    dismiss()
                }
            }
            PopoverMenuRow(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                store.remove(item)
                dismiss()
            }
            PopoverMenuRow(
                title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
            ) {
                store.clearAll()
                dismiss()
            }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            thumbnail
            Text(previewText)
                .font(Theme.Typography.menuRow)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : Color.clear)
        )
    }

    private var previewText: String {
        switch item.kind {
        // Single-line row, so cap before trimming — never walk a multi-MB clipboard string per row.
        case .text:
            return String((item.text ?? "").prefix(200)).trimmingCharacters(
                in: .whitespacesAndNewlines)
        case .image: return "Image"
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .text:
            glyphTile("doc.text")
        case .image:
            if let url = imageURL, let image = ImageThumbnail.load(url, maxPixel: 64) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            } else {
                glyphTile("photo")
            }
        }
    }

    /// An SF Symbol centered on a rounded tile, sized to match the launcher's app icon so text and
    /// image clipboard rows share one consistent thumbnail shape.
    private func glyphTile(_ systemName: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            )
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
            if let url = store.imageURL(for: item),
                let image = ImageThumbnail.load(url, maxPixel: 1200)
            {
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
