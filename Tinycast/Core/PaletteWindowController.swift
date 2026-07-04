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
        // Drop the multi-MB clipboard preview bitmaps now the window is gone, so idle RAM returns near
        // baseline. Row thumbnails stay cached, so the next open is still instant.
        ImageThumbnail.purgePreviews()
        if restoreFocus { previousApp?.activate() }
    }

    /// Paste the item into the previously focused app while leaving the palette open and frontmost.
    /// The keystroke is delivered directly to that app's process, so Tinycast never loses focus.
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) {
        Paster.pasteInPlace(item, store: store, into: previousApp)
    }

    // MARK: - NSWindowDelegate

    /// Dismiss when the palette loses key status (click-away, ⌘-Tab, app switch).
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        hide(restoreFocus: false)
    }

    /// Re-bump focusToken once the panel has *actually* become key. Activating an accessory app
    /// from a global hotkey is asynchronous — `NSApp.activate` + `makeKeyAndOrderFront` in `show()`
    /// can return before AppKit finishes handing the window key status, so setting @FocusState right
    /// after those calls can lose the race and never take. This notification is the one point we
    /// know for certain the window is key, so refocusing here always sticks.
    func windowDidBecomeKey(_ notification: Notification) {
        core.palette.focusToken = UUID()
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
            .environmentObject(core.visibility)
            .environmentObject(core.calcHistory)
            .environmentObject(core.runningApps)
            .environmentObject(core.hotKeys)
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
