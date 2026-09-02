import SwiftUI

/// The clipboard browser: a filtered list beside the selected entry's preview.
struct ClipboardScreen: PaletteScreen {
    let store: ClipboardStore
    let coordinator: ClipboardCoordinator
    let vm: PaletteState
    let openActions: () -> Void
    let scrollToFollow: () -> Void

    var rows: [ClipboardItem] { store.search(vm.query) }

    var primaryActionTitle: String { vm.pasteTarget?.pasteTitle ?? "Paste" }

    private func item(at selection: Int) -> ClipboardItem? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        return ClipboardActionsMenu.content(
            item: item, coordinator: coordinator, store: store, target: vm.pasteTarget)
    }

    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        coordinator.paste(item)
    }

    /// ⌘↵ copies without pasting.
    func secondary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        coordinator.copyToClipboard(item)
        return true
    }

    func perform(_ command: PaletteCommand, at selection: Int) -> Bool {
        switch command {
        case .alternateActivate:
            guard let item = item(at: selection) else { return false }
            coordinator.pasteKeepingWindowOpen(item)
            return true
        case .delete:
            if let item = item(at: selection) { store.remove(item) }
            return true
        case .pin:
            guard let item = item(at: selection) else { return false }
            coordinator.togglePinned(item)
            return true
        case .quit:
            return false
        }
    }

    private func follow(from old: ClipFollowKey, to new: ClipFollowKey) {
        guard old.id != nil else { return }
        let rows = rows
        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty, old.id != new.id, let id = new.id,
            let index = rows.firstIndex(where: { $0.id == id }) {
            vm.selection = index
        }
        scrollToFollow()
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                .onChange(of: ClipFollowKey(id: store.items.first?.id, token: vm.followToken)) { old, new in
                    follow(from: old, to: new)
                }
        )
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: "Clipboard history is empty")
        } else {
            let selected = item(at: selection)
            HStack(spacing: 0) {
                ClipboardList(
                    results: rows,
                    selectedID: selected?.id,
                    scroll: scroll,
                    onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { item in
                        if let index = rows.firstIndex(of: item) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: Theme.Size.clipboardListWidth)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1)
                ClipboardPreview(item: selected)
            }
        }
    }
}

private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}
