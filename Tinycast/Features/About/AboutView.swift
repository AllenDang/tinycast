import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    // Read the bundled .icns directly: NSApp.applicationIconImage returns the generic
    // placeholder until LaunchServices registers the app, which it hasn't when run from build/.
    private var appIcon: NSImage {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }

    private static let repoURL = URL(string: "https://github.com/abue-ammar/tinycast")!
    private static let developerURL = URL(string: "https://github.com/abue-ammar")!

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: Theme.Spacing.xs) {
                Text(Bundle.main.appDisplayName)
                    .font(.title2.bold())
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("A tiny, native macOS launcher.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: Theme.Spacing.sm) {
                AboutLinkButton(
                    title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                    url: Self.repoURL)
                AboutLinkButton(
                    title: "abue-ammar", systemImage: "person.crop.circle", url: Self.developerURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

/// A small pill-shaped external link, styled like the rest of the app's cards/chips.
private struct AboutLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL

    @State private var hovered = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(hovered ? Theme.Colors.rowHover : Theme.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Hosts auxiliary SwiftUI windows (About, Settings), torn down on close so their SwiftUI trees deallocate instead of lingering, and rebuilt instantly on reopen from live state.
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
            // Let the content run edge-to-edge under a transparent titlebar so the window reads as one continuous surface — the modern inspector look.
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: content())
            // Let the window keep its requested size instead of resizing to the SwiftUI fitting size (an unconstrained fill would otherwise blow the window up); the content fills the fixed frame.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.delegate = self
            window.center()
            windows[id] = window
        }
        // Promote to a regular app so the window gets a Dock icon and normal layering; demoted back to accessory when the last aux window closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // A plain `NSWindow` only becomes key while the app is active, but `NSApp.activate` from the menu bar is async, so the synchronous `makeKeyAndOrderFront` above can land first; re-asserting key on the next runloop makes the window truly key up front.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Re-focus an open aux window on reopen (Dock-icon click); returns false when none is open. `windows` only holds live windows (`windowWillClose` prunes them).
    @discardableResult
    func focusExisting() -> Bool {
        guard let window = windows.values.first(where: { $0.isVisible }) ?? windows.values.first
        else { return false }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Close a window programmatically; `windowWillClose` handles the dict/teardown so the SwiftUI tree deallocates.
    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: id)
        if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
