import AppKit
import Carbon.HIToolbox

enum Paster {
    /// Write the item onto the system pasteboard and paste it into `previousApp` via a synthetic
    /// ⌘V, activating that app so the keystroke lands there.
    @MainActor
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) {
        write(item, store: store)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            postCommandV()
        }
    }

    /// Put the item on the system pasteboard without pasting. The internal marker keeps our own
    /// poller from re-capturing it, so the history is left unchanged.
    @MainActor
    static func copy(_ item: ClipboardItem, store: ClipboardStore) {
        write(item, store: store)
    }

    /// Put a plain string on the system pasteboard *without* the internal marker: the clipboard
    /// poller captures it, so a copied calculator answer shows up in clipboard history like any
    /// other copy (Raycast behavior).
    @MainActor
    static func copyPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    /// Paste into `app` *without* activating it, by delivering the ⌘V straight to that process.
    /// This leaves Tinycast frontmost, so the palette can stay open with no focus flicker.
    @MainActor
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) {
        write(item, store: store)
        guard let pid = app?.processIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCommandV(toPid: pid)
        }
    }

    @MainActor
    private static func write(_ item: ClipboardItem, store: ClipboardStore) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .text:
            if let text = item.text {
                pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
                pb.setString(text, forType: .string)
            }
        case .image:
            if let url = store.imageURL(for: item), let data = try? Data(contentsOf: url) {
                pb.declareTypes([.png, ClipboardManager.internalType], owner: nil)
                pb.setData(data, forType: .png)
            }
        }
        pb.setData(Data(), forType: ClipboardManager.internalType)
    }

    /// Synthesize ⌘V. When `pid` is given, the event is delivered to that process only (keeping the
    /// current app frontmost); otherwise it goes through the system tap to whatever is frontmost.
    @MainActor
    private static func postCommandV(toPid pid: pid_t? = nil) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
