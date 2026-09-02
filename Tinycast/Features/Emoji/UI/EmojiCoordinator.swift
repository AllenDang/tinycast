import Foundation

@MainActor
@Observable
final class EmojiCoordinator {
    private let frequency: FrequentEmojiStore
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let palette: PaletteCoordinator

    init(
        frequency: FrequentEmojiStore,
        settings: AppSettings,
        windowController: PaletteWindowController,
        palette: PaletteCoordinator
    ) {
        self.frequency = frequency
        self.settings = settings
        self.windowController = windowController
        self.palette = palette
    }

    func paste(_ entry: EmojiEntry) {
        frequency.record(entry.glyph)
        let previous = palette.previousApp
        palette.hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copy(_ entry: EmojiEntry) {
        frequency.record(entry.glyph)
        palette.hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    func pasteKeepingWindowOpen(_ entry: EmojiEntry) {
        frequency.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(
            entry.display(tone: settings.emojiSkinTone))
    }
}
