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
    private var markdown: AttributedString {
        guard let url = Bundle.module.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let attributed = try? AttributedString(
                  markdown: text,
                  options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else { return AttributedString("No changelog available.") }
        return attributed
    }

    var body: some View {
        ScrollView {
            Text(markdown)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}

/// Hosts auxiliary SwiftUI windows (About, Changelog) for the accessory app. Caches one window per
/// id so reopening keeps state, and raises it to the front like `AppCore.showSettings()` does.
@MainActor
final class AuxWindowController {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: CGSize, @ViewBuilder content: () -> Content) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content())
            window.center()
            windows[id] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
