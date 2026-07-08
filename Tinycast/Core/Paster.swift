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

    /// Put the item on the pasteboard without pasting; the internal marker keeps our poller from re-capturing it.
    @MainActor
    static func copy(_ item: ClipboardItem, store: ClipboardStore) {
        write(item, store: store)
    }

    /// Put a plain string on the pasteboard *without* the internal marker, so a copied calculator answer flows into clipboard history like any other copy.
    @MainActor
    static func copyPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    /// Paste into `app` *without* activating it (⌘V delivered straight to its process), leaving Tinycast frontmost so the palette stays open.
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

    /// Synthesize ⌘V — delivered to `pid` alone when given, otherwise through the system tap to whatever is frontmost.
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
