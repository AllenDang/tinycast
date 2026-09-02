import SwiftUI
import MarkdownUI

struct AICommandScreen: PaletteScreen {
    struct Row: Identifiable { let id = 0 }

    let session: AICommandSession
    let coordinator: AICommandCoordinator

    var rows: [Row] {
        switch session.state {
        case .streaming, .result: return [Row()]
        default: return []
        }
    }

    var primaryActionTitle: String {
        if case .streaming = session.state { return "Generating…" }
        return "Copy Result"
    }

    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func secondary(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard case .result(let text) = session.state else { return }
        coordinator.finish(copying: text)
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
        case .streaming(let text), .result(let text):
            StreamingMarkdownView(text: text)
        case .failed(let message):
            EmptyResults(text: message)
        }
    }
}

/// A scrollable Markdown view that auto-scrolls to the bottom as content arrives (streaming).
private struct StreamingMarkdownView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Markdown(text)
                    .markdownTextStyle(\.text) {
                        ForegroundColor(.white)
                    }
                    // 1.2x line height: +0.2em relative to each block's own font size.
                    .markdownBlockStyle(\.paragraph) { configuration in
                        configuration.label
                            .relativeLineSpacing(.em(0.2))
                    }
                    .markdownTextStyle(\.code) {
                        FontFamilyVariant(.monospaced)
                    }
                    .markdownBlockStyle(\.codeBlock) { configuration in
                        configuration.label
                            .padding(Theme.Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                    .fill(Theme.Colors.cardFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                            )
                            .padding(.vertical, Theme.Spacing.xs)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.xl)
                    .textSelection(.enabled)
                    .id("markdown-bottom")
            }
            .onChange(of: text) {
                proxy.scrollTo("markdown-bottom", anchor: .bottom)
            }
        }
    }
}
