import AppKit
import Carbon.HIToolbox

final class DialogPanel: NSPanel {
    /// What the panel saw, not what it means: how far a step moves is the caller's business.
    enum Key {
        case cancel
        case confirm
        case increment
        case decrement
    }

    var onKey: ((Key) -> Bool)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Suppresses AppKit's own window animation; `fadeIn`/`fadeOut` replace it.
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey else {
            super.sendEvent(event)
            return
        }
        let key: Key?
        switch Int(event.keyCode) {
        case kVK_Escape:
            key = .cancel
        case kVK_Return, kVK_ANSI_KeypadEnter:
            key = .confirm
        case kVK_LeftArrow, kVK_DownArrow:
            key = .decrement
        case kVK_RightArrow, kVK_UpArrow:
            key = .increment
        default:
            key = nil
        }
        if let key, onKey(key) { return }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
