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

    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 0), count: EmojiGrid.columns)

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
                        LazyVGrid(columns: Self.gridColumns, spacing: 0) {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) {
                                offset, entry in
                                let flat = section.start + offset
                                EmojiCell(
                                    glyph: entry.display(tone: tone), selected: flat == selection
                                )
                                .id(section.id + "-" + entry.id)
                                .onTapGesture { onSelect(flat) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(flat)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(flat) }
                            }
                        }
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

private struct EmojiCell: View {
    let glyph: String
    let selected: Bool
    /// Hover lives on the cell itself so a mouse sweep repaints only the cells entering/leaving, mirroring `AppRow`.
    @State private var hovered = false

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
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
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
            PopoverMenuRow(title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                core.copyEmoji(entry)
                dismiss()
            }
            PopoverMenuRow(title: "Paste & Keep Window Open", systemImage: "pin", shortcut: "⌥↵") {
                core.pasteEmojiKeepingWindowOpen(entry)
                dismiss()
            }
        }
    }
}
