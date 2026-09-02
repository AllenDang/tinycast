import SwiftUI

@MainActor
enum ClipboardActionsMenu {
    static func content(
        item: ClipboardItem, coordinator: ClipboardCoordinator, store: ClipboardStore,
        target: PasteTarget?
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: target?.pasteTitle ?? "Paste",
                icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
            ) {
                coordinator.paste(item)
            },
            PopoverMenuItem(title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                coordinator.copyToClipboard(item)
            },
            PopoverMenuItem(
                title: "Paste & Keep Window Open", icon: .paste(target, fallback: "macwindow")
            ) {
                coordinator.pasteKeepingWindowOpen(item)
            }
        ]
        if item.isPinned {
            items.append(
                PopoverMenuItem(title: "Unpin Entry", systemImage: "pin.slash", shortcut: "⌘P") {
                    coordinator.togglePinned(item)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Pin Entry", systemImage: "pin", shortcut: "⌘P") {
                    coordinator.togglePinned(item)
                })
        }
        if item.kind == .image {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder") {
                    coordinator.revealImage(item)
                })
        }
        items.append(
            PopoverMenuItem(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                store.remove(item)
            })
        items.append(
            PopoverMenuItem(
                title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
            ) {
                store.clearAll()
            })
        return PopoverMenuContent(header: headerText(item), items: items)
    }

    private static func headerText(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            return String(oneLine.prefix(40))
        case .image: return "Image"
        }
    }
}
