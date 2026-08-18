import SwiftUI
import MarkdownUI

/// The AI command screen: loading while the request is in flight, then the answer. Reached only by
/// committing an `AICommandCard` with Enter — never entered directly.
///
/// While streaming, partial content is rendered as Markdown and auto-scrolled to the bottom. Once
/// the stream finishes, the row activates and the footer pill reads "Copy Result" — Enter copies
/// the full text and exits.
struct AICommandScreen: PaletteScreen {
    struct Row: Identifiable { let id = 0 }

    let session: AICommandSession
    let core: AppCore

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
