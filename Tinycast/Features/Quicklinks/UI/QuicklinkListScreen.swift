import SwiftUI

/// Search Quicklinks: the library filtered by the search field, pinned entries first.
struct QuicklinkListScreen: PaletteScreen {
    let store: QuicklinkStore
    let coordinator: QuicklinkCoordinator
    let palette: PaletteCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Quicklink] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.quicklinks }
        return store.quicklinks.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var primaryActionTitle: String { "Open Quicklink" }

    private func quicklink(at selection: Int) -> Quicklink? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let quicklink = quicklink(at: selection) else { return nil }
        return QuicklinkActionsMenu.content(
            quicklink: quicklink, coordinator: coordinator, palette: palette)
    }

    func activate(at selection: Int) {
        guard let quicklink = quicklink(at: selection) else { return }
        coordinator.openQuicklink(id: quicklink.id)
    }

    /// ⌘↵ bypasses a saved "open with" app; without one there is nothing to bypass.
    func secondary(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection), quicklink.openWithBundleID != nil else {
            return false
        }
        coordinator.openQuicklink(id: quicklink.id, forcingDefaultApp: true)
        return true
    }

    func perform(_ command: PaletteCommand, at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection) else { return false }
        switch command {
        case .delete:
            Task { await coordinator.deleteQuicklink(id: quicklink.id) }
            return true
        case .pin:
            coordinator.toggleQuicklinkPinned(id: quicklink.id)
            return true
        case .alternateActivate, .quit:
            return false
        }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: store.quicklinks.isEmpty ? "No quicklinks yet" : "No matching quicklinks")
        } else {
            QuicklinkList(
                results: rows,
                selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                scroll: scroll,
                onSelect: { link in
                    if let index = rows.firstIndex(of: link) { vm.selection = index }
                },
                onActivate: { activate(at: vm.selection) },
                onActions: { link in
                    if let index = rows.firstIndex(of: link) { vm.selection = index }
                    openActions()
                }
            )
        }
    }
}

/// The ⌘K menu for a quicklink row.
@MainActor
enum QuicklinkActionsMenu {
    static func content(
        quicklink: Quicklink, coordinator: QuicklinkCoordinator, palette: PaletteCoordinator
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(title: "Open Quicklink", systemImage: symbol(quicklink), shortcut: "↵") {
                coordinator.openQuicklink(id: quicklink.id)
            }
        ]
        if quicklink.openWithBundleID != nil {
            items.append(
                PopoverMenuItem(
                    title: "Open With Default App", systemImage: "arrow.up.forward.app",
                    shortcut: "⌘↵"
                ) {
                    coordinator.openQuicklink(id: quicklink.id, forcingDefaultApp: true)
                })
        }
        items.append(
            PopoverMenuItem(title: "Edit Quicklink", systemImage: "pencil") {
                palette.hidePalette(restoreFocus: false)
                coordinator.editQuicklink(quicklink)
            })
        items.append(
            PopoverMenuItem(title: "Duplicate Quicklink", systemImage: "plus.square.on.square") {
                coordinator.duplicateQuicklink(id: quicklink.id)
            })
        items.append(
            quicklink.isPinned
                ? PopoverMenuItem(title: "Unpin Quicklink", systemImage: "pin.slash", shortcut: "⌘P")
                { coordinator.toggleQuicklinkPinned(id: quicklink.id) }
                : PopoverMenuItem(title: "Pin Quicklink", systemImage: "pin", shortcut: "⌘P") {
                    coordinator.toggleQuicklinkPinned(id: quicklink.id)
                })
        items.append(
            PopoverMenuItem(
                title: quicklink.showsInRootSearch
                    ? "Hide from Root Search" : "Show in Root Search",
                systemImage: quicklink.showsInRootSearch ? "eye.slash" : "eye"
            ) {
                coordinator.setQuicklinkShowsInRootSearch(
                    !quicklink.showsInRootSearch, id: quicklink.id)
            })
        if case .path(let path)? = QuicklinkDestination.detect(quicklink.link),
            !QuicklinkDestination.containsPlaceholder(quicklink.link) {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘F") {
                    palette.hidePalette(restoreFocus: false)
                    AppLauncher.showInFinder(URL(fileURLWithPath: path))
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Delete Quicklink", systemImage: "trash", shortcut: "⌘⌫",
                isDestructive: true
            ) {
                Task { await coordinator.deleteQuicklink(id: quicklink.id) }
            })
        return PopoverMenuContent(header: quicklink.name, items: items)
    }

    private static func symbol(_ quicklink: Quicklink) -> String {
        quicklink.iconSymbol ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol
            ?? Quicklink.sfSymbol
    }
}
