import AppKit
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = ensurePanel()
        center(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    // MARK: - NSWindowDelegate

    /// Dismiss when the palette loses key status (click-away, ⌘-Tab, app switch).
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        hide(restoreFocus: false)
    }

    // MARK: - Private

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView()
            .environmentObject(core)
            .environmentObject(core.palette)
            .environmentObject(core.appIndex)
            .environmentObject(core.clipboardStore)
            .environmentObject(core.favorites)
            .environmentObject(core.runningApps)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.08
        )
        panel.setFrameOrigin(origin)
    }
}
