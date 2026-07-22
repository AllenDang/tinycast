import AppKit
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    private var popToRootTimer: Timer?
    /// Y of the panel's top edge, held fixed across compact↔expanded resizes so the search bar stays put and the list grows downward. Recomputed from the full panel height each show.
    private var anchorTopY: CGFloat = 0

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
        // Size + place the panel to the current collapsed state before ordering front, so a compact summon never flashes at full size.
        positionPanel(panel, collapsed: core.paletteIsCollapsed)
        // The `.nonactivatingPanel` takes key focus without activating the app, so summoning the palette never raises the app's Settings/onboarding windows behind it.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // A never-activated login-item process can drop the first key request before the window is registered with the window server; re-assert next turn once it is (same pattern as AuxWindowController).
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
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

    /// Re-bump focusToken a turn after the panel becomes key: on the first-ever show this fires mid-mount, before the SwiftUI tree has registered its onChange, so a synchronous bump is silently lost.
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.core.palette.focusToken = UUID()
        }
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

    /// Resize the panel to the given collapsed state, keeping the top edge anchored. Applied even while hidden (e.g. compact toggled in Settings) so the window is already correctly sized before the next show — otherwise the list would mount at the stale size and open scrolled up.
    func applyCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        positionPanel(panel, collapsed: collapsed)
    }

    /// Size the panel to compact/expanded height (width fixed) and place it so its top edge sits at `anchorTopY` — recomputed from the full panel height so compact and expanded share one top. Resize is instant (no animation, matching Raycast).
    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = Theme.Size.panelWidth
        let fullOrigin = visible.midY - Theme.Size.panelHeight / 2 + visible.height * 0.08
        anchorTopY = fullOrigin + Theme.Size.panelHeight
        let height = collapsed ? Theme.Size.compactHeight : Theme.Size.panelHeight
        let frame = NSRect(
            x: visible.midX - width / 2, y: anchorTopY - height, width: width, height: height)
        panel.setFrame(frame, display: true)
    }
}
