import AppKit

extension NSScreen {
    static var underCursor: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    /// The menu-bar display: the one at the global origin, which `NSScreen.main` is not.
    static var primary: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }
}
