import SwiftUI

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

struct AICommandHintCard: View {
    let command: AICommand
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: AICommand.sfSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(command.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.lg)
            Text("Type text to run")
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
