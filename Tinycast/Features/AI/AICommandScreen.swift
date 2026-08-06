import SwiftUI

/// The AI command screen: loading while the request is in flight, then the answer. Reached only by
/// committing an `AICommandCard` with Enter — never entered directly — and its only row is the
/// finished answer, so `rows` is empty until one lands (the footer's "Copy Result" pill and ↵ have
/// nothing to do before then).
struct AICommandScreen: PaletteScreen {
    struct Row: Identifiable { let id = 0 }

    let session: AICommandSession
    let core: AppCore

    var rows: [Row] {
        if case .result = session.state { return [Row()] }
        return []
    }

    var primaryActionTitle: String { "Copy Result" }

    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func secondary(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard case .result(let text) = session.state else { return }
        core.finishAICommand(copying: text)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content)
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                Text("Asking \(session.command?.name ?? "AI Command")…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .result(let text):
            ScrollView {
                Text(text)
                    .font(Theme.Typography.rowTitle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.xl)
            }
        case .failed(let message):
            EmptyResults(text: message)
        }
    }
}
