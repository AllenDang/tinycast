import SwiftUI

/// One-deep memo over `CalcEngine.evaluate`, mirroring `AppIndex.matchCache`: the palette body
/// re-renders on hover/selection changes with the same query, and this keeps those renders from
/// re-running the evaluator.
@MainActor
enum CalcMemo {
    private static var cache: (query: String, result: CalcResult?)?

    static func evaluate(_ query: String) -> CalcResult? {
        if let cache, cache.query == query { return cache.result }
        let result = CalcEngine.evaluate(query)
        cache = (query, result)
        return result
    }
}

/// The inline answer card pinned above the app results (expression → result, or a friendly message on impossible conversion); selectable like a row, Enter copies.
struct CalculatorCard: View {
    let result: CalcResult
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Group {
            switch result.payload {
            case .value(let display, _):
                HStack(spacing: 0) {
                    Text(result.expression)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(display)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
            case .error(let message):
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                    Text(message)
                        .lineLimit(1)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fill)
        )
        .onHover { hovered = $0 }
    }
}

/// Actions popover for the calculator card — only answers can be copied, so an error card
/// gets no menu (the caller passes `calc` only for value payloads).
struct CalcActionsMenu: View {
    let result: CalcResult
    let dismiss: () -> Void
    @EnvironmentObject private var core: AppCore

    var body: some View {
        PopoverMenu(header: result.expression) {
            PopoverMenuRow(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                core.copyCalculatorResult(result)
                dismiss()
            }
        }
    }
}
