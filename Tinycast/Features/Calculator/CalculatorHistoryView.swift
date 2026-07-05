import SwiftUI

/// Full-width list of past calculations, mirroring `ClipboardList`'s structure (date-bucket
/// sections, instant single-tap select, double-tap activate, right-click actions). Each row
/// carries both sides of the calculation, so there's no preview pane.
struct CalculatorHistoryList: View {
    let results: [CalcHistoryEntry]
    let selectedID: CalcHistoryEntry.ID?
    /// Changes only when the list should scroll to follow the selection (keyboard nav / reset), so
    /// mouse selection never yanks the scroll position.
    let scrollToken: UUID
    /// Live answer for a calculation typed into the history search — same card and flat-index-0
    /// contract as the launcher (`LauncherList.calc`).
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    let onSelect: (CalcHistoryEntry) -> Void
    let onActivate: () -> Void
    let onActions: (CalcHistoryEntry) -> Void

    private nonisolated static let calcRowID = "calc-card"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case entry(CalcHistoryEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return CalculatorHistoryList.calcRowID
            case .entry(let entry): return entry.id.uuidString
            }
        }
    }

    /// Entries are newest-first, so grouping is a walk that emits a date header whenever the
    /// bucket changes — same shape as the clipboard list. A live calculation pins above them.
    private var rows: [Row] {
        var rows: [Row] = []
        if let calc { rows = [.header("Calculator"), .calc(calc)] }
        var currentBucket: DateBucket?
        for entry in results {
            let bucket = DateBucket(for: entry.createdAt)
            if bucket != currentBucket {
                rows.append(.header(bucket.title))
                currentBucket = bucket
            }
            rows.append(.entry(entry))
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
                        case .calc(let result):
                            CalculatorCard(result: result, selected: calcSelected)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onActivateCalc)
                                .onRightClick(perform: onCalcActions)
                                .padding(.bottom, Theme.Spacing.xs)
                        case .entry(let entry):
                            CalcHistoryRow(entry: entry, selected: entry.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(entry) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(entry)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(entry) }
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
                if calcSelected {
                    proxy.scrollTo(Self.calcRowID, anchor: .center)
                } else if let selectedID {
                    proxy.scrollTo(selectedID.uuidString, anchor: .center)
                }
            }
        }
    }
}

private struct CalcHistoryRow: View {
    let entry: CalcHistoryEntry
    let selected: Bool
    /// Hover lives on the row itself so a mouse sweep repaints only the rows entering/leaving.
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                )
            Text(entry.expression)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.xl)
            Text(entry.result)
                .font(Theme.Typography.rowTitle.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .onHover { hovered = $0 }
    }
}

/// Actions popover for a calculator-history entry, anchored bottom-right like the other modes.
struct CalcHistoryActionsMenu: View {
    let entry: CalcHistoryEntry
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var calcHistory: CalculatorHistoryStore

    var body: some View {
        PopoverMenu(header: entry.expression) {
            PopoverMenuRow(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                core.copyHistoryEntry(entry)
                dismiss()
            }
            PopoverMenuRow(title: "Copy Expression", systemImage: "doc.on.doc.fill") {
                core.copyHistoryExpression(entry)
                dismiss()
            }
            PopoverMenuRow(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                calcHistory.remove(entry)
                dismiss()
            }
            PopoverMenuRow(
                title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
            ) {
                calcHistory.clearAll()
                dismiss()
            }
        }
    }
}
