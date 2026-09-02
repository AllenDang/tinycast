import AppKit

@MainActor
@Observable
final class QuicklinkCoordinator {
    private let store: QuicklinkStore
    private let argumentSession: QuicklinkArgumentSession
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let injector: SnippetTextInjector
    private let hotKeys: HotKeyBindings
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let palette: PaletteCoordinator
    private let presentation: PresentationActions
    private let clipboardHistory: @MainActor () -> [String]
    @ObservationIgnored private var pendingForcesDefaultApp = false
    var pendingEdit: QuicklinkEditRequest?

    init(
        store: QuicklinkStore,
        argumentSession: QuicklinkArgumentSession,
        settings: AppSettings,
        appIndex: AppIndex,
        injector: SnippetTextInjector,
        hotKeys: HotKeyBindings,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        palette: PaletteCoordinator,
        presentation: PresentationActions,
        clipboardHistory: @escaping @MainActor () -> [String]
    ) {
        self.store = store
        self.argumentSession = argumentSession
        self.settings = settings
        self.appIndex = appIndex
        self.injector = injector
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.palette = palette
        self.presentation = presentation
        self.clipboardHistory = clipboardHistory
    }

    func applyQuicklinksPresence() {
        let enabled = settings.quicklinksEnabled
        appIndex.setQuicklinks(
            enabled && settings.quicklinksShowInLauncher ? store.quicklinks : [],
            commandsVisible: enabled)
    }

    func openQuicklink(id: UUID, forcingDefaultApp: Bool = false) {
        guard settings.quicklinksEnabled, let quicklink = store.quicklink(id: id) else { return }
        let target = palette.targetApplication
        let encoding: SnippetTemplateEngine.ValueEncoding =
            QuicklinkDestination.usesURLEncoding(quicklink.link) ? .percentEncoding : .none
        var context = injector.captureExpansionContext(
            targetApp: target, clipboardHistory: clipboardHistory())
        var arguments: [SnippetTemplateEngine.MissingArgument] = []

        if context.selection.isEmpty, SnippetTemplateEngine.usesSelection(quicklink.link) {
            switch settings.quicklinkSelectionFallback {
            case .clipboard:
                context = context.replacingSelection(with: context.clipboard)
            case .ask:
                arguments.append(Self.selectionArgument)
            }
        }

        let expansion = SnippetTemplateEngine.expand(
            text: quicklink.link, context: context, encoding: encoding)
        arguments += expansion.missingArguments
        guard arguments.isEmpty else {
            argumentSession.begin(
                quicklink: quicklink, context: context, encoding: encoding, arguments: arguments)
            pendingForcesDefaultApp = forcingDefaultApp
            // Never `restoreAnyMode`: this screen is always a fresh prompt, never a restored one.
            palette.showPalette(mode: .quicklinkArguments)
            return
        }
        performQuicklinkOpen(quicklink, link: expansion.text, forcingDefaultApp: forcingDefaultApp)
    }

    private static let selectionArgument = SnippetTemplateEngine.MissingArgument(
        name: "Selected Text", options: [])

    /// ↵ in the argument form. Returns false while more arguments remain.
    @discardableResult
    func submitQuicklinkArgument(_ value: String) -> Bool {
        guard let request = argumentSession.request else { return false }
        guard let values = argumentSession.submit(value) else { return false }

        var context = request.context
        if let selection = values[Self.selectionArgument.name] {
            context = context.replacingSelection(with: selection)
        }
        let expansion = SnippetTemplateEngine.expand(
            text: request.quicklink.link, context: context, userArguments: values,
            encoding: request.encoding)
        let forcesDefault = pendingForcesDefaultApp
        cancelQuicklinkArguments()
        performQuicklinkOpen(request.quicklink, link: expansion.text, forcingDefaultApp: forcesDefault)
        return true
    }

    func cancelQuicklinkArguments() {
        argumentSession.cancel()
        pendingForcesDefaultApp = false
    }

    private func performQuicklinkOpen(
        _ quicklink: Quicklink, link: String, forcingDefaultApp: Bool
    ) {
        if palette.isVisible { palette.hidePalette(restoreFocus: false) }
        let openWith = forcingDefaultApp ? nil : quicklink.openWithBundleID
        Task {
            do throws(QuicklinkLauncher.Failure) {
                try await QuicklinkLauncher.open(
                    link, openWithBundleID: openWith,
                    inNewWindow: settings.quicklinkOpensNewWindow)
            } catch {
                await presentQuicklinkFailure(quicklink, link: link, failure: error)
            }
        }
    }

    private func presentQuicklinkFailure(
        _ quicklink: Quicklink, link: String, failure: QuicklinkLauncher.Failure
    ) async {
        let symbol = quicklink.iconSymbol ?? Quicklink.sfSymbol
        guard let bundleID = failure.missingApplicationBundleID else {
            await presentation.notice(
                "Couldn’t Open \(quicklink.name)", failure.localizedDescription, symbol, .danger)
            return
        }
        // The only failure with a usable second option, so it offers it rather than dead-ending.
        let name = applicationName(forBundleID: bundleID) ?? bundleID
        guard
            await presentation.reportFailure(
                "Couldn’t Open \(quicklink.name)", "\(name) isn’t installed any more.", symbol,
                "Open with Default")
        else { return }
        performQuicklinkOpen(quicklink, link: link, forcingDefaultApp: true)
    }

    private func applicationName(forBundleID bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { FileManager.default.displayName(atPath: $0.path) }
    }

    @discardableResult
    func addQuicklink(_ draft: Quicklink) throws -> Quicklink {
        try store.add(draft)
    }

    func updateQuicklink(_ draft: Quicklink) throws {
        try store.update(draft)
    }

    func deleteQuicklink(id: UUID, confirming: Bool = true) async {
        guard let quicklink = store.quicklink(id: id) else { return }
        if confirming, settings.quicklinkConfirmsBeforeDelete {
            guard
                await presentation.confirm(
                    "Delete “\(quicklink.name)”?",
                    "Its shortcut, favorite slot and learned ranking go with it.",
                    quicklink.iconSymbol ?? Quicklink.sfSymbol, "Delete", .danger, .destructive)
            else { return }
        }
        removeQuicklink(quicklink)
    }

    func deleteQuicklinkFromSettings(id: UUID) async {
        guard let quicklink = store.quicklink(id: id) else { return }
        guard
            await presentation.confirm(
                "Delete “\(quicklink.name)”?",
                "Its global shortcut and launcher references will also be removed.",
                quicklink.iconSymbol ?? Quicklink.sfSymbol, "Delete", .danger, .destructive)
        else { return }
        removeQuicklink(quicklink)
    }

    private func removeQuicklink(_ quicklink: Quicklink) {
        removeQuicklinkReferences(ids: [quicklink.id], entryIDs: [quicklink.entryID])
        try? store.remove(id: quicklink.id)
    }

    func toggleQuicklinkPinned(id: UUID) {
        try? store.togglePinned(id: id)
    }

    func setQuicklinkShowsInRootSearch(_ shows: Bool, id: UUID) {
        try? store.setShowsInRootSearch(shows, id: id)
    }

    func duplicateQuicklink(id: UUID) {
        _ = try? store.duplicate(id: id)
    }

    func editQuicklink(_ quicklink: Quicklink?) {
        pendingEdit = QuicklinkEditRequest(quicklink: quicklink)
        palette.showSettings(tab: .quicklinks)
    }

    @discardableResult
    func replaceQuicklinks(_ incoming: [Quicklink]) -> Int {
        let previous = store.quicklinks
        let count = store.replace(with: incoming)
        let liveIDs = Set(store.quicklinks.map(\.id))
        let removed = previous.filter { !liveIDs.contains($0.id) }
        removeQuicklinkReferences(
            ids: Set(removed.map(\.id)), entryIDs: Set(removed.map(\.entryID)))
        return count
    }

    private func removeQuicklinkReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.quicklink(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    func exportQuicklinks() async {
        guard !store.quicklinks.isEmpty else {
            await presentation.notice(
                "Nothing to Export", "You haven’t created any quicklinks yet.",
                Quicklink.sfSymbol, .neutral)
            return
        }
        guard let url = BackupActions.chooseSaveLocation(named: "Tinycast-Quicklinks") else { return }
        do {
            try QuicklinkArchive.encode(store.quicklinks).write(to: url, options: .atomic)
            presentation.showMessage("Exported \(store.quicklinks.count) Quicklinks", .success)
        } catch {
            await presentation.notice(
                "Export Failed", error.localizedDescription, Quicklink.sfSymbol, .danger)
        }
    }

    func importQuicklinks() async {
        guard let url = BackupActions.chooseJSONFile() else { return }
        do {
            let incoming = try QuicklinkArchive.decode(Data(contentsOf: url))
            let merge = QuicklinkArchive.merge(incoming, into: store.quicklinks)
            let added = store.append(merge.additions)
            guard !added.isEmpty else {
                await presentation.notice(
                    "Nothing to Import",
                    "Every quicklink in this file is already in your library.",
                    Quicklink.sfSymbol, .neutral)
                return
            }
            let skipped = merge.skipped + (merge.additions.count - added.count)
            let summary = skipped == 0
                ? "Imported \(added.count) quicklinks."
                : "Imported \(added.count) quicklinks. Skipped \(skipped) already in your library."
            await presentation.notice(
                "Quicklinks Imported", summary, Quicklink.sfSymbol, .success)
        } catch {
            await presentation.notice(
                "Import Failed", error.localizedDescription, Quicklink.sfSymbol, .danger)
        }
    }
}
