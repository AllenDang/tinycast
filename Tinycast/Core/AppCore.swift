import AppKit
import SwiftUI

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard

    var id: String { rawValue }
    var title: String { self == .launcher ? "Apps" : "Clipboard" }
    var systemImage: String { self == .launcher ? "magnifyingglass" : "doc.on.clipboard" }
    var placeholder: String { self == .launcher ? "Search apps…" : "Search clipboard…" }
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var mode: PaletteMode = .launcher
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    @Published var focusToken = UUID()

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        focusToken = UUID()
    }
}

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let appIndex = AppIndex()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let hotKeys = HotKeyManager()
    let settings = AppSettings()
    let favorites = FavoritesStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteViewModel()

    private lazy var windowController = PaletteWindowController(core: self)
    private let auxWindows = AuxWindowController()

    private init() {
        clipboardManager = ClipboardManager(store: clipboardStore)
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        // Tinycast is always dark — the Liquid Glass palette is tuned for a deep, Raycast-style
        // dark surface, and forcing the appearance keeps the material from rendering washed-out
        // when the system is in Light mode.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        clipboardStore.maxItems = settings.clipboardMaxItems
        clipboardStore.load()
        clipboardManager.start()

        Task { await appIndex.refresh() }

        hotKeys.onTogglePalette = { [weak self] in self?.togglePalette() }
        hotKeys.onToggleClipboard = { [weak self] in self?.toggleClipboard() }
        hotKeys.start()
    }

    // MARK: - Palette control

    func togglePalette() {
        if windowController.isVisible, palette.mode == .launcher {
            hidePalette()
        } else {
            showPalette(mode: .launcher)
        }
    }

    func toggleClipboard() {
        if windowController.isVisible, palette.mode == .clipboard {
            hidePalette()
        } else {
            showPalette(mode: .clipboard)
        }
    }

    func showPalette(mode: PaletteMode) {
        palette.prepare(mode: mode)
        windowController.show()
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// Settings runs in its own window (the SwiftUI `Settings` scene is unreliable for accessory
    /// apps), raised to the front via the same controller as About/Changelog.
    func showSettings() {
        auxWindows.show(id: "settings", title: "Settings", size: CGSize(width: 500, height: 440)) {
            SettingsRootView().environmentObject(self.appIndex)
        }
    }

    func showAbout() {
        auxWindows.show(id: "about", title: "About Tinycast", size: CGSize(width: 320, height: 320)) {
            AboutView()
        }
    }

    func showChangelog() {
        auxWindows.show(id: "changelog", title: "Changelog", size: CGSize(width: 460, height: 480)) {
            ChangelogView()
        }
    }

    // MARK: - Actions invoked from the palette UI

    func launch(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        AppLauncher.launch(app.url)
    }

    func showInFinder(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        Paster.paste(item, store: clipboardStore, previousApp: previous)
    }
}
