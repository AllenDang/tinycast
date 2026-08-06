import SwiftUI

/// The inline hint shown when the raw query matches a configured AI command's keyword — "trans some
/// text", say — at flat selection index 0, exactly where `CalculatorCard` sits. The key difference:
/// the calculator's card is the actual answer, computed synchronously and locally; this card only
/// previews the *intent*. The request reaches the network and is asynchronous, so it must never fire
/// while the user is still typing — only Enter (or a click) commits it, which opens
/// `AICommandScreen` instead of finishing anything inline.
struct AICommandCard: View {
    let match: AICommandMatch
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "return")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(match.command.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Text("“\(match.input)”")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.lg)
            Text("AI Command")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
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
