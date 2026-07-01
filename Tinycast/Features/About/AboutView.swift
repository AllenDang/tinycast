import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Tinycast")
                .font(.title2.bold())
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("A tiny, native macOS launcher.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Changelog") { AppCore.shared.showChangelog() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct ChangelogView: View {
    // Read + parse the bundled markdown once; the file is static, so a `let` avoids re-parsing it
    // on every body evaluation.
    private let blocks: [MarkdownBlock] = {
        guard let url = Bundle.module.url(forResource: "CHANGELOG", withExtension: "md"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [.paragraph(AttributedString("No changelog available."))] }
        return MarkdownBlock.parse(text)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    block.view(isFirst: index == 0)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .thinOverlayScrollbar()
        }
    }
}

/// A minimal, dependency-free block-level markdown renderer for the changelog. SwiftUI's
/// `Text(AttributedString)` only styles *inline* markdown (bold/italic/code/links) — it ignores
/// block syntax, so `#` headings and `-` bullets would otherwise render as literal characters.
/// This parser splits the document into blocks and renders each with the right SwiftUI styling,
/// while still using `AttributedString` for inline formatting within each line.
enum MarkdownBlock {
    case heading(level: Int, text: AttributedString)
    case bullet(AttributedString)
    case paragraph(AttributedString)

    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let level = headingLevel(trimmed) {
                blocks.append(
                    .heading(level: level, text: inline(String(trimmed.dropFirst(level + 1)))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(inline(String(trimmed.dropFirst(2)))))
            } else {
                blocks.append(.paragraph(inline(trimmed)))
            }
        }
        return blocks
    }

    /// Number of leading `#`s if the line is an ATX heading (`#` … `######` followed by a space).
    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let after = line.index(line.startIndex, offsetBy: hashes)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return hashes
    }

    /// Inline-only markdown (bold/italic/code/links) → styled `AttributedString`.
    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
    }

    @ViewBuilder func view(isFirst: Bool) -> some View {
        switch self {
        case .heading(let level, let text):
            Text(text)
                .font(Self.headingFont(level))
                // The first block sits flush against the container's top padding, so its heading
                // gets no extra top inset — keeping the padding uniform on all four sides.
                .padding(.top, isFirst ? 0 : (level <= 2 ? 8 : 2))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(text)
            }
            .padding(.leading, 4)
        case .paragraph(let text):
            Text(text)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.bold()
        case 2: return .title2.bold()
        case 3: return .title3.bold()
        default: return .headline
        }
    }
}

/// Hosts auxiliary SwiftUI windows (About, Changelog, Settings) for the accessory app. Each window
/// is torn down on close so its SwiftUI tree — and any timers it drives — deallocates instead of
/// lingering for the app's lifetime. Reopening rebuilds instantly (the views read live state).
@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(
        id: String, title: String, size: CGSize, seamlessTitleBar: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            var style: NSWindow.StyleMask = [.titled, .closable]
            if seamlessTitleBar { style.insert(.fullSizeContentView) }
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = title
            // Let the content (e.g. the Settings sidebar) run edge-to-edge under a transparent
            // titlebar so the window reads as one continuous surface — the modern inspector look.
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content())
            window.delegate = self
            window.center()
            windows[id] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // A plain `NSWindow` can only become key while the app is active. When opened from the menu
        // bar the app isn't active yet, and `NSApp.activate` is processed asynchronously — so the
        // synchronous `makeKeyAndOrderFront` above can land *before* the app is active, leaving the
        // window visible but not key. The first click then just makes the window key (NSTextField
        // doesn't accept first-mouse) instead of focusing the control under it, which is why the
        // hotkey recorder's key capture didn't arm on the first click. Re-asserting key on the next
        // runloop, after activation has taken effect, makes the window truly key up front.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: id)
    }
}
