import AppKit
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    private var popToRootTimer: Timer?

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        // Ignore ourselves as the "previous" app (e.g. summoned while Settings/About/Onboarding is frontmost) so paste/focus-restore always targets the user's real app, never Tinycast's own field.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }
        let panel = ensurePanel()
        center(panel)
        // The `.nonactivatingPanel` takes key focus without activating the app, so summoning the palette never raises the app's Settings/onboarding windows behind it.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        // Drop the multi-MB clipboard preview bitmaps now the window is gone, so idle RAM returns near baseline (row thumbnails stay cached).
        ImageThumbnail.purgePreviews()
        schedulePopToRoot()
        if restoreFocus { previousApp?.activate() }
    }

    /// Pop to Root Search: reset immediately (also releases heavy sub-screens — a fully scrolled emoji grid is ~2k realized views), or keep state and reset after the configured delay unless a reopen consumes it first.
    private func schedulePopToRoot() {
        popToRootTimer?.invalidate()
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            core.palette.prepare(mode: .launcher)
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.popToRootTimer = nil
                self?.core.palette.prepare(mode: .launcher)
            }
        }
    }

    /// True when a hidden palette still holds pre-close state (pending pop-to-root); consuming cancels the reset either way — the caller decides whether to restore or re-prepare.
    func consumePreservedState() -> Bool {
        guard let timer = popToRootTimer else { return false }
        timer.invalidate()
        popToRootTimer = nil
        return true
    }

    /// Paste into the previously focused app while leaving the palette frontmost (keystroke delivered straight to that app's process).
    @discardableResult
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        Paster.pasteInPlace(item, store: store, into: previousApp)
    }

    /// String flavor of the above, for emoji/symbol pastes.
    func pasteStringKeepingWindowOpen(_ text: String) {
        Paster.pasteStringInPlace(text, into: previousApp)
    }

    // MARK: - NSWindowDelegate

    /// Dismiss when the palette loses key status (click-away, ⌘-Tab, app switch).
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        hide(restoreFocus: false)
    }

    /// Re-bump focusToken once the panel has *actually* become key, since activating an accessory app from a hotkey is async and refocusing right after `show()` can lose the race.
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
            .environmentObject(core.emojiIndex)
            .environmentObject(core.frequentEmoji)
            .environmentObject(core.runningApps)
            .environmentObject(core.hotKeys)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        // Backspace in an already-empty search backs out of a sub-screen to a fresh root launcher; `prepare` clears state and re-focuses the field.
        panel.onBareBackspace = { [weak self] in
            guard let vm = self?.core.palette, vm.mode != .launcher, vm.query.isEmpty else {
                return false
            }
            vm.prepare(mode: .launcher)
            return true
        }
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
