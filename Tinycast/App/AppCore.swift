import AppKit
import SwiftUI

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()
    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let aiCommands = AICommandStore()
    let aiProvider = AIProviderStore()
    let aiCommandSession = AICommandSession()
    let quicklinks = QuicklinkStore()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardMonitor
    let snippetsStore: SnippetsStore
    let snippetListener = SnippetKeywordListener(syntheticEventTag: Paster.tinycastEventTag)
    let snippetTextInjector: SnippetTextInjector
    let hotKeys = HotKeyBindings()
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let settings: AppSettings
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let uninstall = UninstallSession()
    let quicklinkArguments = QuicklinkArgumentSession()

    @ObservationIgnored private lazy var windowController = PaletteWindowController(
        settings: settings,
        palette: palette,
        quicklinkArguments: quicklinkArguments,
        rootContent: { [unowned self] in self.makePaletteContent() })
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    @ObservationIgnored private lazy var presentation = PresentationActions(
        confirm: { [unowned self] title, message, symbol, action, tone, role in
            await self.dialogs.confirm(
                title: title, message: message, symbol: symbol, tone: tone,
                confirmTitle: action, confirmRole: role)
        },
        notice: { [unowned self] title, message, symbol, tone in
            await self.dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
        },
        reportFailure: { [unowned self] title, message, symbol, recovery in
            await self.dialogs.reportFailure(
                title: title, message: message, symbol: symbol, recovery: recovery)
        },
        showMessage: { [unowned self] message, tone in
            self.messageHUD.show(message: message, tone: tone)
        },
        pickVolume: { [unowned self] current in
            await self.dialogs.pickVolume(current: current)
        })
    @ObservationIgnored private(set) lazy var snippetCoordinator = SnippetExpansionCoordinator(
        store: snippetsStore,
        listener: snippetListener,
        injector: snippetTextInjector,
        clipboardStore: clipboardStore,
        appIndex: appIndex,
        settings: settings,
        presentation: presentation,
        promptArguments: { [unowned self] id, snippetName, arguments in
            let fields = arguments.map { DialogField(name: $0.name, options: $0.options) }
            return await self.dialogs.promptFields(
                id: id, title: "Snippet: \(snippetName)", fields: fields)
        },
        cancelPrompt: { [unowned self] id in self.dialogs.cancel(id: id) })
    @ObservationIgnored private(set) lazy var quicklinkCoordinator = QuicklinkCoordinator(
        store: quicklinks,
        argumentSession: quicklinkArguments,
        settings: settings,
        appIndex: appIndex,
        injector: snippetTextInjector,
        hotKeys: hotKeys,
        favorites: favorites,
        visibility: visibility,
        ranking: launcherRanking,
        palette: paletteCoordinator,
        presentation: presentation,
        clipboardHistory: { [unowned self] in
            self.snippetCoordinator.clipboardHistoryForExpansion()
        })
    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        controller: windowController, auxWindows: auxWindows, settings: settings,
        palette: palette, aiProvider: aiProvider, appIndex: appIndex, emojiIndex: emojiIndex,
        settingsContent: { [unowned self] tab in self.makeSettingsContent(tab: tab) },
        onboardingContent: { [unowned self] in self.makeOnboardingContent() })
    @ObservationIgnored private(set) lazy var aiCommandCoordinator = AICommandCoordinator(
        providerStore: aiProvider, commandStore: aiCommands, session: aiCommandSession,
        paletteState: palette, palette: paletteCoordinator, presentation: presentation)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        history: calcHistory, palette: paletteCoordinator)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        store: clipboardStore, paletteState: palette, windowController: windowController,
        palette: paletteCoordinator, presentation: presentation)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequency: frequentEmoji, settings: settings, windowController: windowController,
        palette: paletteCoordinator)
    @ObservationIgnored private(set) lazy var windowManagementCoordinator =
        WindowManagementCoordinator(
            settings: settings, appIndex: appIndex, mover: windowMover,
            palette: paletteCoordinator)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        palette: paletteCoordinator, volumeHUD: volumeHUD, presentation: presentation)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, appIndex: appIndex, runningApps: runningApps,
        palette: palette, paletteCoordinator: paletteCoordinator, hotKeys: hotKeys,
        favorites: favorites, visibility: visibility, ranking: launcherRanking,
        presentation: presentation)
    @ObservationIgnored private(set) lazy var customCommandCoordinator = CustomCommandCoordinator(
        store: customCommands, settings: settings, appIndex: appIndex,
        palette: paletteCoordinator, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, presentation: presentation)
    @ObservationIgnored private(set) lazy var backupCoordinator = BackupCoordinator(
        context: SettingsBackup.Context(
            settings: settings, clipboardStore: clipboardStore, hotKeys: hotKeys,
            customCommands: customCommands, quicklinks: quicklinks, favorites: favorites,
            visibility: visibility,
            replaceCustomCommands: { [unowned self] in
                self.customCommandCoordinator.replaceCustomCommands($0)
            },
            replaceQuicklinks: { [unowned self] in
                self.quicklinkCoordinator.replaceQuicklinks($0)
            }),
        snippetsStore: snippetsStore,
        confirm: { [unowned self] title, message, symbol, confirmTitle, tone, role in
            await self.presentation.confirm(title, message, symbol, confirmTitle, tone, role)
        },
        notice: { [unowned self] title, message, symbol, tone in
            await self.presentation.notice(title, message, symbol, tone)
        })
    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, runningApps: runningApps, palette: paletteCoordinator,
        customCommands: customCommandCoordinator, systemActions: systemActionCoordinator,
        windowManagement: windowManagementCoordinator, quicklinks: quicklinkCoordinator,
        snippets: snippetCoordinator, backup: backupCoordinator, uninstall: uninstallCoordinator,
        presentation: presentation)
    private let volumeHUD = VolumeHUDController()
    private let auxWindows = AuxWindowController()
    private let dialogs = DialogController()
    private let healthTicker = HealthTicker()

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        self.launcherRanking = launcherRanking
        self.settings = settings
        appIndex = AppIndex(ranking: launcherRanking)
        let clipboardManager = ClipboardMonitor(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        snippetsStore = SnippetsStore()
        snippetTextInjector = SnippetTextInjector(
            clipboardManager: clipboardManager,
            settings: settings)
    }

    func start() {
        Signposts.interval("AppCore.start") {
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            NSApp.appearance = NSAppearance(named: .darkAqua)

            windowController.collapsed = { [weak self] in
                self?.paletteCoordinator.paletteIsCollapsed ?? false
            }
            windowController.showSettings = { [weak self] in
                self?.paletteCoordinator.showSettings()
            }

            clipboardStore.maxAge = settings.clipboardRetention.maxAge
            // Defer the SQLite read + prune off the launch path; the palette fills in later.
            Task { clipboardStore.load() }
            clipboardManager.start()

            appIndex.start(settings: settings)
            customCommands.onChange = { [weak self] _ in
                self?.customCommandCoordinator.applyCustomCommandsPresence()
            }
            customCommandCoordinator.applyCustomCommandsPresence()
            windowManagementCoordinator.applyPresence()
            quicklinks.onChange = { [weak self] _ in
                self?.quicklinkCoordinator.applyQuicklinksPresence()
            }
            quicklinks.load()
            quicklinkCoordinator.applyQuicklinksPresence()
            Task { await appIndex.refresh() }
            currencyRates.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.doubleTapMonitor.healthTicker = healthTicker
            snippetListener.healthTicker = healthTicker

            hotKeys.displayNameResolver = { [weak self] action in
                guard let self else { return nil }
                switch action {
                case .app(let bundleID):
                    return self.appIndex.apps.first {
                        $0.kind == .application && $0.bundleID == bundleID
                    }?.name
                case .settingsPane(let bundleID):
                    return self.appIndex.apps.first {
                        $0.kind == .systemSettings && $0.bundleID == bundleID
                    }?.name
                case .customCommand(let id):
                    return self.customCommands.command(id: id)?.name
                case .quicklink(let id):
                    return self.quicklinks.quicklink(id: id)?.name
                default:
                    return nil
                }
            }
            SystemActionRunner.onAsyncFailure = { [weak self] id, failure in
                self?.systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
            }
            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.onToggleClipboard = { [weak self] in self?.paletteCoordinator.toggleClipboard() }
            hotKeys.onToggleEmoji = { [weak self] in self?.paletteCoordinator.toggleEmoji() }
            hotKeys.onRunCustomCommand = { [weak self] id in
                self?.customCommandCoordinator.runCustomCommand(id: id)
            }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowManagementCoordinator.run(id: id)
            }
            hotKeys.onOpenQuicklink = { [weak self] id in
                self?.quicklinkCoordinator.openQuicklink(id: id)
            }
            hotKeys.start(
                customCommandIDs: Set(customCommands.commands.map(\.id)),
                quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)))
            hyperKeyTap.start(settings: settings)

            snippetsStore.onSnapshot = { [weak self] snapshot in
                guard let self else { return }
                self.snippetCoordinator.applySnippetsLauncherPresence()
                self.snippetListener.update(snapshot.records)
            }
            if settings.snippetsEnabled {
                Task { await snippetsStore.start() }
                snippetCoordinator.startSnippetKeywordListener()
            }

            observeFeatureSwitches()

            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                paletteCoordinator.showOnboarding()
            }
        }
    }

    private func makePaletteContent() -> AnyView {
        AnyView(
            RootPaletteView()
                .environment(paletteCoordinator)
                .environment(launcherCoordinator)
                .environment(aiCommandCoordinator)
                .environment(calculatorCoordinator)
                .environment(clipboardCoordinator)
                .environment(emojiCoordinator)
                .environment(quicklinkCoordinator)
                .environment(uninstallCoordinator)
                .environment(settings)
                .environment(palette)
                .environment(appIndex)
                .environment(clipboardStore)
                .environment(favorites)
                .environment(visibility)
                .environment(calcHistory)
                .environment(currencyRates)
                .environment(emojiIndex)
                .environment(frequentEmoji)
                .environment(runningApps)
                .environment(hotKeys)
                .environment(uninstall)
                .environment(quicklinks)
                .environment(quicklinkArguments)
                .environment(aiCommands)
                .environment(aiProvider)
                .environment(aiCommandSession)
        )
    }

    private func makeSettingsContent(tab: SettingsTab) -> AnyView {
        AnyView(
            SettingsRootView(initialTab: tab)
                .environment(paletteCoordinator)
                .environment(launcherCoordinator)
                .environment(clipboardCoordinator)
                .environment(customCommandCoordinator)
                .environment(aiCommandCoordinator)
                .environment(snippetCoordinator)
                .environment(quicklinkCoordinator)
                .environment(backupCoordinator)
                .environment(settings)
                .environment(appIndex)
                .environment(visibility)
                .environment(customCommands)
                .environment(aiCommands)
                .environment(aiProvider)
                .environment(snippetsStore)
                .environment(quicklinks)
                .environment(hotKeys)
                .environment(hyperKeyTap)
                .environment(clipboardStore)
                .environment(currencyRates)
                .environment(runningApps)
                .environment(snippetListener)
        )
    }

    private func makeOnboardingContent() -> AnyView {
        AnyView(
            OnboardingView()
                .environment(backupCoordinator)
                .environment(paletteCoordinator)
                .environment(settings)
                .environment(hotKeys)
        )
    }

    func prepareForTermination() {
        hyperKeyTap.prepareForTermination()
        snippetTextInjector.prepareForTermination()
        snippetListener.stop()
        snippetsStore.stop()
        launcherRanking.flush()
    }

    // MARK: - Feature switches

    private func observeFeatureSwitches() {
        track({
            _ = $0.windowManagementEnabled
            _ = $0.windowManagementShowInLauncher
        }, reproject: { $0.windowManagementCoordinator.applyPresence() })
        track({
            _ = $0.customCommandsEnabled
            _ = $0.customCommandsShowInLauncher
        }, reproject: { $0.customCommandCoordinator.applyCustomCommandsPresence() })
        track({
            _ = $0.quicklinksEnabled
            _ = $0.quicklinksShowInLauncher
        }, reproject: { $0.quicklinkCoordinator.applyQuicklinksPresence() })
        track({ _ = $0.snippetsEnabled }, reproject: {
            $0.snippetCoordinator.applySnippetsEnabled()
        })
        track({ _ = $0.snippetsShowInLauncher }, reproject: {
            $0.snippetCoordinator.applySnippetsLauncherPresence()
        })
    }

    /// Fires synchronously on main before the write lands, so the task re-arms and re-reads.
    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(reads, reproject: reproject)
                reproject(self)
            }
        }
    }

}
