import Foundation

@MainActor
@Observable
final class CalculatorCoordinator {
    private let history: CalculatorHistoryStore
    private let palette: PaletteCoordinator

    init(history: CalculatorHistoryStore, palette: PaletteCoordinator) {
        self.history = history
        self.palette = palette
    }

    func copyResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        history.record(expression: result.expression, result: display)
        palette.hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        palette.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.result.replacingOccurrences(of: ",", with: ""))
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        palette.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.expression)
    }
}
