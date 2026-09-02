import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let palette: PaletteState
    private let quicklinkArguments: QuicklinkArgumentSession
    private let rootContent: @MainActor () -> AnyView
    var collapsed: @MainActor () -> Bool = { false }
    var showSettings: @MainActor () -> Void = {}
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    private var popToRootTimer: Timer?
    private var anchor: (x: CGFloat, topEdgeY: CGFloat)?

    init(
        settings: AppSettings,
        palette: PaletteState,
        quicklinkArguments: QuicklinkArgumentSession,
        rootContent: @escaping @MainActor () -> AnyView
    ) {
        self.settings = settings
        self.palette = palette
        self.quicklinkArguments = quicklinkArguments
        self.rootContent = rootContent
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        Signposts.interval("PaletteWindowController.show") {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
                previousApp = frontmost
            }
            palette.pasteTarget = PasteTarget(app: previousApp)
            let panel = ensurePanel()
            palette.hoverHighlightArmed = false
            anchor = nil
            positionPanel(panel, collapsed: collapsed())
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        anchor = nil
        ImageThumbnail.purgePreviews()
        schedulePopToRoot()
        if restoreFocus { previousApp?.activate() }
    }

    private func schedulePopToRoot() {
        popToRootTimer?.invalidate()
        let timeout = settings.popToRootTimeout
        guard timeout != .immediately else {
            palette.prepare(mode: .launcher)
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popToRootTimer = nil
                self?.palette.prepare(mode: .launcher)
            }
        }
    }

    func consumePreservedState() -> Bool {
        guard let timer = popToRootTimer else { return false }
        timer.invalidate()
        popToRootTimer = nil
        return true
    }

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

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.palette.focusToken = UUID()
        }
    }

    // MARK: - Private

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let panel = PalettePanel(rootView: rootContent())
        panel.delegate = self
        panel.paletteViewModel = palette
        panel.onBareBackspace = { [weak self] in
            guard let self, palette.mode != .launcher, palette.query.isEmpty else { return false }
            if palette.mode == .quicklinkArguments,
                let previous = quicklinkArguments.retreat() {
                palette.query = previous
                palette.selection = 0
                return true
            }
            palette.prepare(mode: .launcher)
            return true
        }
        panel.onCommandShortcut = { [weak self] event in
            guard let self, !event.isARepeat,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            else { return false }
            // Escape has no character, so it matches by key code.
            if Int(event.keyCode) == kVK_Escape {
                self.palette.prepare(mode: .launcher)
                return true
            }
            guard let character = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch character {
            case ",":
                self.showSettings()
                return true
            case "w":
                self.hide(restoreFocus: true)
                return true
            default:
                return false
            }
        }
        self.panel = panel
        return panel
    }

    func applyCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        positionPanel(panel, collapsed: collapsed)
    }

    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        guard let anchor = resolveAnchor() else { return }
        let height = collapsed ? Theme.Size.compactHeight : Theme.Size.panelHeight
        let frame = NSRect(
            x: anchor.x, y: anchor.topEdgeY - height, width: Theme.Size.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    private func targetScreen() -> NSScreen? {
        settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    private func resolveAnchor() -> (x: CGFloat, topEdgeY: CGFloat)? {
        if let anchor { return anchor }
        guard let screen = targetScreen() else { return nil }
        let visible = screen.visibleFrame
        let resolved = (
            x: visible.midX - Theme.Size.panelWidth / 2,
            topEdgeY: visible.maxY - visible.height * Theme.Size.paletteTopMarginFraction
        )
        anchor = resolved
        return resolved
    }
}
