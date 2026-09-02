import AppKit
import SwiftUI

/// State shared between the panel's SwiftUI tree and the coordinator.
@MainActor
@Observable
final class PaletteState {
    var mode: PaletteMode = .launcher
    var query: String = ""
    var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    var focusToken = UUID()
    var resetToken = UUID()
    var followToken = UUID()
    var forceExpanded = false
    var pasteTarget: PasteTarget?
    @ObservationIgnored var hoverHighlightArmed = false
    @ObservationIgnored var searchFieldFrozen = false { didSet { onSearchFieldFrozenChanged?(searchFieldFrozen) } }
    @ObservationIgnored var onSearchFieldFrozenChanged: ((Bool) -> Void)?

    var isComposing = false
    var aiConfigured = false

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        hoverHighlightArmed = false
        searchFieldFrozen = false
        isComposing = false
        focusToken = UUID()
        resetToken = UUID()
    }
}
