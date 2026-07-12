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

    /// The visible sections for a query: ranked results while searching, otherwise Frequently Used + every category.
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

struct EmojiGridView: View {
    let sections: [EmojiGridSection]
    /// Flat selection index across all sections in order — the same single-source-of-truth contract as the list modes.
    let selection: Int
    let tone: EmojiSkinTone
    /// Changes only when the grid should scroll to follow the selection (keyboard nav / reset), so mouse selection never yanks the scroll position.
    let scrollToken: UUID
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    /// Scroll target for the current selection; IDs are section-namespaced because a frequent emoji repeats inside its category section.
    private var selectedCellID: String? {
        guard let section = sections.last(where: { selection >= $0.start }),
            selection - section.start < section.entries.count
        else { return nil }
        return section.id + "-" + section.entries[selection - section.start].id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        SectionHeader(title: section.title)
                        EmojiSectionGrid(
                            section: section, selection: selection, tone: tone,
                            onSelect: onSelect, onActivate: onActivate, onActions: onActions
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scrollToken) {
                if let selectedCellID { proxy.scrollTo(selectedCellID, anchor: .center) }
            }
        }
    }
}

/// One section's grid. All interaction (tap, double-tap, right-click, hover) lives here — once per section, not per cell — because a fast scroll realizes every cell and per-cell gesture/tracking machinery at ~2k cells costs ~100 MB that lazy containers never release.
private struct EmojiSectionGrid: View {
    let section: EmojiGridSection
    let selection: Int
    let tone: EmojiSkinTone
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @State private var hoveredIndex: Int?
    @State private var width: CGFloat = 0

    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 0), count: EmojiGrid.columns)

    var body: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 0) {
            ForEach(Array(section.entries.enumerated()), id: \.element.id) { offset, entry in
                EmojiCell(
                    glyph: entry.display(tone: tone),
                    selected: section.start + offset == selection,
                    hovered: offset == hoveredIndex
                )
                .id(section.id + "-" + entry.id)
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        // Single tap selects immediately; the double-tap paste rides along as a simultaneous gesture (the list rows' pattern).
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let local = localIndex(at: value.location) { onSelect(section.start + local) }
            }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                guard let local = localIndex(at: value.location) else { return }
                onSelect(section.start + local)
                onActivate()
            }
        )
        .onRightClick { point in
            if let local = localIndex(at: point) { onActions(section.start + local) }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): hoveredIndex = localIndex(at: point)
            case .ended: hoveredIndex = nil
            }
        }
    }

    /// Point → cell, exact because columns split the width evenly with zero spacing and rows are `Theme.Size.emojiCell` tall; empty trailing cells of a partial last row resolve to nil.
    private func localIndex(at point: CGPoint) -> Int? {
        guard width > 0, point.y >= 0, point.x >= 0, point.x < width else { return nil }
        let column = min(
            Int(point.x / (width / CGFloat(EmojiGrid.columns))), EmojiGrid.columns - 1)
        let local = Int(point.y / Theme.Size.emojiCell) * EmojiGrid.columns + column
        return local < section.entries.count ? local : nil
    }
}

/// Pure content — no gestures, overlays or hover tracking; interaction is handled by `EmojiSectionGrid` so realized cells stay cheap.
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

/// Actions popover for an emoji/symbol cell, anchored bottom-right on right-click, mirroring `ClipboardActionsMenu`.
struct EmojiActionsMenu: View {
    let entry: EmojiEntry
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore

    var body: some View {
        PopoverMenu(header: entry.displayName) {
            PopoverMenuRow(title: "Paste", systemImage: "doc.on.clipboard", shortcut: "↵") {
                core.pasteEmoji(entry)
                dismiss()
            }
            PopoverMenuRow(title: "Copy to Clipboard", systemImage: "doc.on.doc") {
                core.copyEmoji(entry)
                dismiss()
            }
            PopoverMenuRow(title: "Paste & Keep Window Open", systemImage: "pin") {
                core.pasteEmojiKeepingWindowOpen(entry)
                dismiss()
            }
        }
    }
}
