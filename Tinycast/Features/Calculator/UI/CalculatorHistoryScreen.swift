import SwiftUI

/// Past calculations, led by the live answer for the current search query.
struct CalculatorHistoryScreen: PaletteScreen {
    let history: CalculatorHistoryStore
    let currencyRates: CurrencyRateStore
    let coordinator: CalculatorCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case entry(CalcHistoryEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .entry(let entry): return entry.id.uuidString
            }
        }
    }

    private var calc: CalcResult? { CalcMemo.evaluate(vm.query, currency: currencyRates.source) }
    private var entries: [CalcHistoryEntry] { history.search(vm.query) }

    var rows: [Row] {
        let entries = entries.map(Row.entry)
        guard let calc else { return entries }
        return [.calc(calc)] + entries
    }

    var primaryActionTitle: String { "Copy Answer" }

    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func entry(at selection: Int) -> CalcHistoryEntry? {
        guard case .entry(let entry) = row(at: selection) else { return nil }
        return entry
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        if case .calc = row(at: selection) { return true }
        return false
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable
                ? CalcActionsMenu.content(result: result, coordinator: coordinator) : nil
        case .entry(let entry):
            return CalcHistoryActionsMenu.content(
                entry: entry, coordinator: coordinator, calcHistory: history)
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .calc(let result): coordinator.copyResult(result)
        case .entry(let entry): coordinator.copyHistoryEntry(entry)
        case nil: break
        }
    }

    /// ⌘↵ applies only to stored entries.
    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        coordinator.copyHistoryExpression(entry)
        return true
    }

    func perform(_ command: PaletteCommand, at selection: Int) -> Bool {
        guard command == .delete else { return false }
        if let entry = entry(at: selection) { history.remove(entry) }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "No calculations yet" : "No matching calculations")
        } else {
            CalculatorHistoryList(
                results: entries,
                selectedID: entry(at: selection)?.id,
                scroll: scroll,
                calc: calc,
                calcSelected: isCardSelected(selection),
                onActivateCalc: {
                    vm.selection = 0
                    activate(at: 0)
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    openActions()
                },
                onSelect: { entry in
                    if let index = rows.firstIndex(of: .entry(entry)) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { entry in
                    if let index = rows.firstIndex(of: .entry(entry)) { vm.selection = index }
                    openActions()
                }
            )
        }
    }
}

@MainActor
enum CalcHistoryActionsMenu {
    static func content(
        entry: CalcHistoryEntry,
        coordinator: CalculatorCoordinator,
        calcHistory: CalculatorHistoryStore
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: entry.expression,
            items: [
                PopoverMenuItem(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                    coordinator.copyHistoryEntry(entry)
                },
                PopoverMenuItem(
                    title: "Copy Expression", systemImage: "doc.on.doc.fill", shortcut: "⌘↵"
                ) {
                    coordinator.copyHistoryExpression(entry)
                },
                PopoverMenuItem(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                    calcHistory.remove(entry)
                },
                PopoverMenuItem(
                    title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
                ) {
                    calcHistory.clearAll()
                }
            ]
        )
    }
}
