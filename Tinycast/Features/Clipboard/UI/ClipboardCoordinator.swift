import Foundation

@MainActor
@Observable
final class ClipboardCoordinator {
    private let store: ClipboardStore
    private let paletteState: PaletteState
    private let windowController: PaletteWindowController
    private let palette: PaletteCoordinator
    private let presentation: PresentationActions

    init(
        store: ClipboardStore,
        paletteState: PaletteState,
        windowController: PaletteWindowController,
        palette: PaletteCoordinator,
        presentation: PresentationActions
    ) {
        self.store = store
        self.paletteState = paletteState
        self.windowController = windowController
        self.palette = palette
        self.presentation = presentation
    }

    func clearHistory() async {
        guard
            await presentation.confirm(
                "Clear clipboard history?", "This can't be undone.", "trash", "Clear History",
                .danger, .destructive)
        else { return }
        store.clearAll()
    }

    func paste(_ item: ClipboardItem) {
        let previous = palette.previousApp
        palette.hidePalette(restoreFocus: false)
        if Paster.paste(item, store: store, previousApp: previous) {
            select(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: store) {
            select(item)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        palette.hidePalette(restoreFocus: false)
        if Paster.copy(item, store: store) {
            select(item)
        }
    }

    func revealImage(_ item: ClipboardItem) {
        guard let url = store.imageURL(for: item) else { return }
        palette.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    func togglePinned(_ item: ClipboardItem) {
        store.togglePinned(item)
        select(item)
        paletteState.followToken = UUID()
    }

    private func select(_ item: ClipboardItem) {
        paletteState.selection = store.rowIndex(of: item, in: paletteState.query) ?? 0
    }
}
