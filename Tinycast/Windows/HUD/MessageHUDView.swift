import SwiftUI

struct MessageHUDView: View {
    let message: String
    let tone: DialogTone

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(message)
                .font(Theme.Typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Image(systemName: tone.hudSymbol)
                .font(Theme.Typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.tint)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .frame(maxWidth: Theme.Size.hudMaxWidth, alignment: .leading)
        .fixedSize()
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(Capsule())
    }
}

extension DialogTone {
    fileprivate var hudSymbol: String {
        switch self {
        case .neutral: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .danger: return "exclamationmark.circle.fill"
        }
    }
}
