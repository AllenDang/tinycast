import AppKit
import SwiftUI

@MainActor
@Observable
final class PaletteCoordinator {
    private let controller: PaletteWindowController
    private let auxWindows: AuxWindowController
    private let settings: AppSettings
    private let palette: PaletteState
    private let aiProvider: AIProviderStore
    private let appIndex: AppIndex
    private let emojiIndex: EmojiIndex
    private let settingsContent: @MainActor (SettingsTab) -> AnyView
    private let onboardingContent: @MainActor () -> AnyView

    init(
        controller: PaletteWindowController,
        auxWindows: AuxWindowController,
        settings: AppSettings,
        palette: PaletteState,
        aiProvider: AIProviderStore,
        appIndex: AppIndex,
        emojiIndex: EmojiIndex,
        settingsContent: @escaping @MainActor (SettingsTab) -> AnyView,
        onboardingContent: @escaping @MainActor () -> AnyView
    ) {
        self.controller = controller
        self.auxWindows = auxWindows
        self.settings = settings
        self.palette = palette
        self.aiProvider = aiProvider
        self.appIndex = appIndex
        self.emojiIndex = emojiIndex
        self.settingsContent = settingsContent
        self.onboardingContent = onboardingContent
    }

    var isVisible: Bool { controller.isVisible }
    var previousApp: NSRunningApplication? { controller.previousApp }

    var targetApplication: NSRunningApplication? {
        controller.isVisible ? controller.previousApp : NSWorkspace.shared.frontmostApplication
    }

    func togglePalette() {
        if controller.isVisible, palette.mode == .launcher {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func toggleClipboard() {
        if controller.isVisible, palette.mode == .clipboard {
            hidePalette()
        } else {
            showPalette(mode: .clipboard)
        }
    }

    func toggleEmoji() {
        if controller.isVisible, palette.mode == .emoji {
            hidePalette()
        } else {
            showPalette(mode: .emoji)
        }
    }

    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        let preserved = controller.consumePreservedState()
        if !(preserved && (restoreAnyMode || palette.mode == mode)) {
            palette.prepare(mode: mode)
        }
        palette.aiConfigured = aiProvider.isConfigured
        controller.show()
        if palette.mode == .launcher { Task { await appIndex.refresh() } }
        if palette.mode == .emoji, !emojiIndex.isLoaded { Task { await emojiIndex.load() } }
    }

    func hidePalette(restoreFocus: Bool = true) {
        controller.hide(restoreFocus: restoreFocus)
    }

    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func expandFromCompact() {
        palette.forceExpanded = true
    }

    func syncPaletteSize() {
        controller.applyCollapsed(paletteIsCollapsed)
    }

    func handleReopen() {
        if auxWindows.focusExisting() { return }
        showPalette(mode: .launcher, restoreAnyMode: true)
    }

    func showSettings(tab: SettingsTab = .general) {
        let isNew = auxWindows.show(
            id: "settings", title: "Settings", size: CGSize(width: 720, height: 550),
            seamlessTitleBar: true
        ) {
            settingsContent(tab)
        }
        if !isNew {
            NotificationCenter.default.post(name: .tinycastSelectSettingsTab, object: tab)
        }
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showOnboarding() {
        auxWindows.show(
            id: "onboarding", title: "Welcome to Tinycast",
            size: OnboardingView.windowSize, seamlessTitleBar: true
        ) {
            onboardingContent()
        }
    }

    func finishOnboarding() {
        auxWindows.close(id: "onboarding")
        showPalette(mode: .launcher)
    }
}
