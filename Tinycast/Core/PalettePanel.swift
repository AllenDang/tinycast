import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    /// Called for a bare backspace before the event reaches the field editor; return true to
    /// consume it. Needed for "backspace in an empty search backs out to the root launcher":
    /// the focused field editor handles plain backspace itself (a no-op when the field is empty),
    /// so SwiftUI `onKeyPress` handlers up the hierarchy never see it — unlike ⌘⌫ or the arrows.
    var onBareBackspace: (() -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            onBareBackspace?() == true
        {
            return
        }
        super.sendEvent(event)
    }
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 470),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
