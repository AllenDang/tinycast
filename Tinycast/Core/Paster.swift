import AppKit
import Carbon.HIToolbox

enum Paster {
    @MainActor
    static func paste(_ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?) {
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

        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            postCommandV()
        }
    }

    @MainActor
    private static func postCommandV() {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
