import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    /// Called for a bare backspace before it reaches the field editor (return true to consume); the field editor swallows plain backspace itself, so SwiftUI `onKeyPress` up the hierarchy never sees it.
    var onBareBackspace: (() -> Bool)?
    /// Drives Raycast-style hover-to-select: arm on real pointer movement, disarm on any key. `sendEvent` is the one place both event streams pass through (mouse-moved needs `acceptsMouseMovedEvents`), so the arm state stays screen-space true — a keyboard-driven scroll that slides rows under a still pointer never fires `.mouseMoved`, so hover stays disarmed.
    weak var paletteViewModel: PaletteViewModel?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteViewModel?.hoverSelectionArmed = true
        case .keyDown: paletteViewModel?.hoverSelectionArmed = false
        default: break
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 475),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
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
        // The controller owns the frame: without this the hosting view resizes the panel to fit the SwiftUI content, dropping the top edge on the first compact→expanded mount.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
