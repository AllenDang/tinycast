import AppKit
import SwiftUI

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard"
        case .calculatorHistory: return "Calculator History"
        case .emoji: return "Emoji & Symbols"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        }
    }
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
    let hyperKeyTap = HyperKeyTap()
    let settings = AppSettings()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let calcHistory = CalculatorHistoryStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteViewModel()

    private lazy var windowController = PaletteWindowController(core: self)
    private let auxWindows = AuxWindowController()

    private init() {
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        // Force dark: the Liquid Glass material is tuned for a deep dark surface and renders washed-out in Light mode.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        clipboardStore.load()
        clipboardManager.start()

        Task { await appIndex.refresh() }
        Task { await emojiIndex.load() }

        hotKeys.onTogglePalette = { [weak self] in self?.togglePalette() }
        hotKeys.onToggleClipboard = { [weak self] in self?.toggleClipboard() }
        hotKeys.onToggleEmoji = { [weak self] in self?.toggleEmoji() }
        hotKeys.start()
        // Deliberately keeps running while `hotKeys.recordingAction` pauses Carbon: the recorder relies on the tap's rewritten flags to capture Hyper shortcuts.
        hyperKeyTap.start(settings: settings)

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Flag is set at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !UserDefaults.standard.bool(forKey: SettingsKey.didCompleteOnboarding) {
            UserDefaults.standard.set(true, forKey: SettingsKey.didCompleteOnboarding)
            showOnboarding()
        }
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

    func toggleEmoji() {
        if windowController.isVisible, palette.mode == .emoji {
            hidePalette()
        } else {
            showPalette(mode: .emoji)
        }
    }

    func showPalette(mode: PaletteMode) {
        palette.prepare(mode: mode)
        windowController.show()
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// Settings runs in its own window (the SwiftUI `Settings` scene is unreliable for accessory apps), raised via the same controller as About.
    func showSettings() {
        auxWindows.show(
            id: "settings", title: "Settings", size: CGSize(width: 720, height: 600),
            seamlessTitleBar: true
        ) {
            SettingsRootView()
                .environmentObject(self.appIndex)
                .environmentObject(self.visibility)
        }
    }

    /// Open Settings on the Backup pane (used by the "Import from Raycast" command, which needs the passphrase field).
    func showBackupSettings() {
        showSettings()
        // Post on the next runloop so the freshly-mounted pane's observer is already listening.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .tinycastShowBackupSettings, object: nil)
        }
    }

    func showAbout() {
        auxWindows.show(id: "about", title: "About Tinycast", size: CGSize(width: 320, height: 320))
        {
            AboutView()
        }
    }

    /// The first-run wizard: palette shortcut, Accessibility, Raycast import. Also re-runnable from Settings.
    func showOnboarding() {
        auxWindows.show(
            id: "onboarding", title: "Welcome to Tinycast",
            size: OnboardingView.windowSize, seamlessTitleBar: true
        ) {
            OnboardingView()
        }
    }

    /// Final onboarding step: close the wizard and drop straight into the launcher.
    func finishOnboarding() {
        auxWindows.close(id: "onboarding")
        showPalette(mode: .launcher)
    }

    // MARK: - Actions invoked from the palette UI

    func launch(_ app: AppEntry) {
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if app.kind == .command {
            runCommand(app)
            return
        }
        hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command:
            break  // handled above
        }
    }

    private func runCommand(_ entry: AppEntry) {
        switch CommandRegistry.command(for: entry) {
        case .calculatorHistory:
            showPalette(mode: .calculatorHistory)
        case .clipboardHistory:
            showPalette(mode: .clipboard)
        case .searchEmoji:
            showPalette(mode: .emoji)
        case .exportSettings:
            hidePalette(restoreFocus: false)
            BackupActions.exportSettings()
        case .importSettings:
            hidePalette(restoreFocus: false)
            BackupActions.importSettings()
        case .importFromRaycast:
            hidePalette(restoreFocus: false)
            showBackupSettings()
        case .settings:
            hidePalette(restoreFocus: false)
            showSettings()
        case .about:
            hidePalette(restoreFocus: false)
            showAbout()
        case .quit:
            NSApp.terminate(nil)
        case nil:
            break
        }
    }

    /// Enter on the inline calculator card: copy the answer, remember the calculation, dismiss.
    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    /// Enter on a Calculator History row: re-copy the stored answer (no re-record).
    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.result.replacingOccurrences(of: ",", with: ""))
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.expression)
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

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        windowController.pasteKeepingWindowOpen(item, store: clipboardStore)
    }

    func copyToClipboard(_ item: ClipboardItem) {
        hidePalette(restoreFocus: false)
        Paster.copy(item, store: clipboardStore)
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    // MARK: - Emoji actions (frequency is tallied on the base glyph; the configured tone is applied at copy time)

    func pasteEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }
}
