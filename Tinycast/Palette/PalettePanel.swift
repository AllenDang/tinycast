import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    var onBareBackspace: (() -> Bool)?
    var onCommandShortcut: ((NSEvent) -> Bool)?
    weak var paletteViewModel: PaletteState? {
        didSet {
            paletteViewModel?.onSearchFieldFrozenChanged = { [weak self] frozen in self?.setSearchCaretHidden(frozen) }
        }
    }

    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab
    ]

    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = hidden ? .clear : .white
        if hidden {
            let end = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: end, length: 0))
        }
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteViewModel?.hoverHighlightArmed = true
        case .keyDown: paletteViewModel?.hoverHighlightArmed = false
        default: break
        }
        if event.type == .keyDown,
            paletteViewModel?.searchFieldFrozen == true,
            event.modifierFlags.isDisjoint(with: [.command, .control]),
            !Self.menuNavKeys.contains(Int(event.keyCode)) {
            return
        }
        let wasComposing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            !wasComposing,
            onBareBackspace?() == true {
            return
        }
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }
        super.sendEvent(event)
        if event.type == .keyDown {
            paletteViewModel?.isComposing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        }
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
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
