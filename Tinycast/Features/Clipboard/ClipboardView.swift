import AppKit
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
                .hideNativeScrollers()
            }
            .thinScrollbar()
            .onChange(of: scrollToken) {
                if let selectedID { proxy.scrollTo(selectedID.uuidString, anchor: .center) }
            }
        }
    }
}

/// Coarse date buckets for grouping clipboard and calculator-history entries into sections,
/// mirroring Raycast's Today / Yesterday / This Week / … grouping. Ordered newest-first by raw value.
enum DateBucket: Int {
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
    /// Hover lives on the row itself so a mouse sweep repaints only the rows entering/leaving — it
    /// never invalidates the parent list body. Mirrors the launcher's `AppRow`.
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

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
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .onHover { hovered = $0 }
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
            AsyncThumbnail(url: imageURL, maxPixel: 64) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            } placeholder: {
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

/// Renders a downsampled clipboard thumbnail, decoding misses off the main thread so the UI never
/// stalls when the clipboard first appears. Cache hits resolve on the first task tick; misses show
/// `placeholder` until the background decode completes. `content` styles the loaded image per site
/// (row thumbnail vs. large preview).
private struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = ImageThumbnail.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil  // show the placeholder while a new image decodes
            image = await ImageThumbnail.loadAsync(url, maxPixel: maxPixel)
        }
    }
}

struct ClipboardPreview: View {
    /// The preview pane is ~460pt wide (panel 750 − list 290); 900px keeps it crisp at 2× Retina
    /// without over-decoding — 1200px would allocate ~1.8× the pixels it can ever display.
    private static let previewMaxPixel: CGFloat = 900

    let item: ClipboardItem?
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, )
                ClipboardInfoSection(item: item, imageURL: store.imageURL(for: item))
            }
            .padding(8)
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
            AsyncThumbnail(url: store.imageURL(for: item), maxPixel: Self.previewMaxPixel) {
                image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } placeholder: {
                Image(systemName: "photo").font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Raycast-style "Information" block under the preview: label/value rows split by hairlines.
/// Everything that touches disk or walks the full text (dimensions, file size, character/word
/// counts) is gathered off the main actor per selection, so clicking through huge entries never
/// hitches the palette.
private struct ClipboardInfoSection: View {
    let item: ClipboardItem
    let imageURL: URL?

    @State private var details = Details()

    private struct Details: Equatable, Sendable {
        var characters: Int?
        var words: Int?
        var pixelSize: CGSize?
        var fileBytes: Int?
    }

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var icon: NSImage?
        var id: String { label }
    }

    /// "Today at 1:22:57 AM" — relative day name plus exact time. DateFormatter is expensive to
    /// build, so it's shared; @MainActor because the view only reads it from body.
    @MainActor private static let copiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Information")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: Theme.Spacing.lg)
                        if let icon = row.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.callout)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .padding(.top, Theme.Spacing.xl)
        .task(id: item.id) { await loadDetails() }
    }

    private var rows: [InfoRow] {
        var rows: [InfoRow] = []
        if let source {
            rows.append(InfoRow(label: "Source", value: source.name, icon: source.icon))
        }
        switch item.kind {
        case .text:
            rows.append(InfoRow(label: "Type", value: "Text"))
            if let characters = details.characters {
                rows.append(InfoRow(label: "Characters", value: characters.formatted()))
            }
            if let words = details.words {
                rows.append(InfoRow(label: "Words", value: words.formatted()))
            }
        case .image:
            rows.append(InfoRow(label: "Type", value: "Image"))
            if let size = details.pixelSize {
                rows.append(
                    InfoRow(label: "Dimensions", value: "\(Int(size.width))×\(Int(size.height))"))
            }
            if let bytes = details.fileBytes {
                rows.append(
                    InfoRow(
                        label: "Size", value: Int64(bytes).formatted(.byteCount(style: .file))))
            }
        }
        rows.append(
            InfoRow(label: "Copied", value: Self.copiedFormatter.string(from: item.createdAt)))
        return rows
    }

    /// Source app name + icon, resolved from the recorded bundle ID. Launch Services lookup is a
    /// quick main-thread call and the icon comes from the shared `IconCache`, so no extra caching.
    private var source: (name: String, icon: NSImage)? {
        guard let bundleID = item.sourceBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return (url.deletingPathExtension().lastPathComponent, IconCache.icon(forFile: url.path))
    }

    private func loadDetails() async {
        let text = item.text
        let url = imageURL
        details = await Task.detached(priority: .userInitiated) {
            var details = Details()
            if let text {
                details.characters = text.count
                details.words = Self.wordCount(text)
            }
            if let url {
                details.pixelSize = ImageThumbnail.pixelSize(of: url)
                details.fileBytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            }
            return details
        }.value
    }

    /// Single pass over scalars — `split(whereSeparator:)` would allocate a substring per word,
    /// which matters when a multi-MB copy lands here.
    private nonisolated static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let separator = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !separator && !inWord { count += 1 }
            inWord = !separator
        }
        return count
    }
}
