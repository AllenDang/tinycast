import SwiftUI

struct CalculatorHistoryList: View {
    let results: [CalcHistoryEntry]
    let selectedID: CalcHistoryEntry.ID?
    let scroll: ScrollIntent
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

    /// Scroll target for the current selection.
    private var selectedRowID: String? {
        calcSelected ? Self.calcRowID : selectedID?.uuidString
    }

    private var firstRowSelected: Bool {
        calc != nil ? calcSelected : selectedID != nil && selectedID == results.first?.id
    }

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
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
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
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    if firstRowSelected {
                        proxy.scrollToOrigin()
                    } else if let selectedRowID {
                        proxy.reveal(selectedRowID)
                    }
                }
            }
        }
    }
}

private struct CalcHistoryRow: View {
    let entry: CalcHistoryEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
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
        .armedHover($hovered)
    }
}
