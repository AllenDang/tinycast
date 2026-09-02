import SwiftUI

/// One titled run of grid cells; `start` is the flat selection index of its first cell.
struct EmojiGridSection: Identifiable {
    let title: String
    let entries: [EmojiEntry]
    let start: Int

    var id: String { title }
}

enum EmojiGrid {
    static let columns = 8

    @MainActor
    static func sections(
        query: String, index: EmojiIndex, frequent: FrequentEmojiStore
    ) -> [EmojiGridSection] {
        var sections: [EmojiGridSection] = []
        var start = 0
        func append(_ title: String, _ entries: [EmojiEntry]) {
            guard !entries.isEmpty else { return }
            sections.append(EmojiGridSection(title: title, entries: entries, start: start))
            start += entries.count
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            append("Frequently Used", frequent.top().compactMap(index.entry(for:)))
            for section in index.categorySections {
                append(section.category.title, section.entries)
            }
        } else {
            append("Results", index.search(query))
        }
        return sections
    }
}

private struct EmojiGridRow: Identifiable {
    let id: String
    let start: Int
    let entries: [EmojiEntry]
}

/// Flat render order for one query: section headers and grid rows interleaved.
private enum EmojiGridItem: Identifiable {
    case header(id: String, title: String)
    case row(EmojiGridRow)

    var id: String {
        switch self {
        case .header(let id, _): return id
        case .row(let row): return row.id
        }
    }
}

struct EmojiGridView: View {
    let sections: [EmojiGridSection]
    let selection: Int
    let tone: EmojiSkinTone
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    private var items: [EmojiGridItem] {
        var items: [EmojiGridItem] = []
        for section in sections {
            items.append(.header(id: section.id + "-header", title: section.title))
            var offset = 0
            var row = 0
            while offset < section.entries.count {
                let end = min(offset + EmojiGrid.columns, section.entries.count)
                items.append(
                    .row(
                        EmojiGridRow(
                            id: section.id + "-row-\(row)",
                            start: section.start + offset,
                            entries: Array(section.entries[offset..<end]))))
                offset = end
                row += 1
            }
        }
        return items
    }

    private var selectedRowID: String? {
        guard let section = sections.last(where: { selection >= $0.start }),
            selection - section.start < section.entries.count
        else { return nil }
        return section.id + "-row-\((selection - section.start) / EmojiGrid.columns)"
    }

    private var firstRowID: String? { sections.first.map { $0.id + "-row-0" } }

    var body: some View {
        let items = items
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(_, let title):
                            SectionHeader(title: title, isFirst: item.id == items.first?.id)
                        case .row(let row):
                            EmojiGridRowView(
                                row: row, selection: selection, tone: tone,
                                onSelect: onSelect, onActivate: onActivate, onActions: onActions
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    guard let selectedRowID else { return }
                    if selectedRowID == firstRowID {
                        proxy.scrollToOrigin()
                    } else {
                        proxy.reveal(selectedRowID)
                    }
                }
            }
        }
    }
}

private struct EmojiGridRowView: View {
    let row: EmojiGridRow
    let selection: Int
    let tone: EmojiSkinTone
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @Environment(PaletteState.self) private var palette
    @State private var hoveredColumn: Int?
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<EmojiGrid.columns, id: \.self) { column in
                if column < row.entries.count {
                    EmojiCell(
                        glyph: row.entries[column].display(tone: tone),
                        selected: row.start + column == selection,
                        hovered: column == hoveredColumn
                    )
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: Theme.Size.emojiCell)
                }
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let column = column(at: value.location) { onSelect(row.start + column) }
            }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                guard let column = column(at: value.location) else { return }
                onSelect(row.start + column)
                onActivate()
            }
        )
        .onRightClick { point in
            if let column = column(at: point) { onActions(row.start + column) }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoveredColumn = palette.hoverHighlightArmed ? column(at: point) : nil
            case .ended:
                hoveredColumn = nil
            }
        }
    }

    private func column(at point: CGPoint) -> Int? {
        guard width > 0, point.x >= 0, point.x < width else { return nil }
        let column = min(
            Int(point.x / (width / CGFloat(EmojiGrid.columns))), EmojiGrid.columns - 1)
        return column < row.entries.count ? column : nil
    }
}

private struct EmojiCell: View {
    let glyph: String
    let selected: Bool
    let hovered: Bool

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Text(glyph)
            .font(.system(size: 30))
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.emojiCell)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(fill)
            )
    }
}
