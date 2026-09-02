import AppKit

struct BundleMetaCache: Sendable {
    private struct Entry: Sendable {
        let modified: Date?
        let name: String
        let bundleID: String?
        let executable: String?
    }

    private let previous: [String: Entry]
    private var current: [String: Entry] = [:]

    init() { previous = [:] }

    init(reusing cache: BundleMetaCache) { previous = cache.current }

    mutating func metadata(for url: URL) -> (name: String, bundleID: String?, executable: String?) {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cached = previous[url.path], cached.modified == modified {
            current[url.path] = cached
            return (cached.name, cached.bundleID, cached.executable)
        }
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier
        let name =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let executable = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        let entry = Entry(modified: modified, name: name, bundleID: bundleID, executable: executable)
        current[url.path] = entry
        return (name, bundleID, executable)
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []

    private var snippetEntries: [AppEntry] = []

    private struct MatchKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
    }

    private struct ResultsKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
        let visibilityRevision: Int
        let favoritesRevision: Int
    }

    /// Repeated renders for the same query reuse the ranking instead of re-matching every frame.
    @ObservationIgnored private var matchMemo = Memo<MatchKey, [AppEntry]>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, [AppEntry]>()
    /// Bumped whenever `apps` changes, so both memos above name the entry set they were built from.
    private var entriesRevision = 0

    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let allWindowCommandEntries: [AppEntry] = WindowCommandCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://window-command/" + command.id.rawValue)!,
                bundleID: nil, kind: .windowCommand)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var discoveredEntries: [AppEntry] = []
    private var customCommandEntries: [AppEntry] = []
    private var windowCommandEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    /// Built-in commands minus the quicklink ones while the feature is off.
    private var commandEntries: [AppEntry] = CommandCatalog.all
    private var alternateNameCache = SpotlightNames.Cache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var bundleMetaCache = BundleMetaCache()
    private var isRefreshing = false
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private var settings: AppSettings?

    init(ranking: LauncherRankingStore) {
        self.ranking = ranking
    }

    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://custom-command/" + command.id.uuidString)!,
                bundleID: nil, kind: .customCommand)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    func setQuicklinks(_ quicklinks: [Quicklink], commandsVisible: Bool) {
        let entries = quicklinks
            .filter(\.showsInRootSearch)
            .sorted(by: Quicklink.precedes)
            .map { quicklink in
                AppEntry(
                    id: quicklink.entryID, name: quicklink.name,
                    url: URL(string: "tinycast://quicklink/" + quicklink.id.uuidString)!,
                    bundleID: nil, kind: .quicklink,
                    symbolName: quicklink.iconSymbol
                        ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol)
            }
        let commands = commandsVisible
            ? CommandCatalog.all
            : CommandCatalog.all.filter { entry in
                CommandCatalog.command(for: entry).map { !$0.isQuicklinkCommand } ?? true
            }
        guard entries != quicklinkEntries || commands != commandEntries else { return }
        quicklinkEntries = entries
        commandEntries = commands
        publishEntries()
    }

    func setWindowCommandsVisible(_ visible: Bool) {
        let entries = visible ? Self.allWindowCommandEntries : []
        guard entries != windowCommandEntries else { return }
        windowCommandEntries = entries
        publishEntries()
    }

    func updateSnippets(_ records: [StoredSnippet]) {
        let entries = records
            .filter { $0.snippet.isEnabled }
            .map { record in
                AppEntry(
                    id: "snippet:\(record.id)",
                    name: record.snippet.name,
                    url: record.fileURL,
                    bundleID: nil,
                    kind: .snippet,
                    matchAliases: [record.snippet.keyword].compactMap { $0 })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != snippetEntries else { return }
        snippetEntries = entries
        publishEntries()
    }

    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then rescans.
    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let reusing = alternateNameCache
            let reusingPanes = paneCache
            let reusingMeta = BundleMetaCache(reusing: bundleMetaCache)
            let result = await Task.detached(priority: .utility) {
                AppIndex.scan(
                    scopes: scopes, cache: SpotlightNames.Cache(reusing: reusing),
                    paneCache: reusingPanes, metaCache: reusingMeta)
            }.value
            alternateNameCache = result.cache
            paneCache = result.paneCache
            bundleMetaCache = result.metaCache
            guard result.entries != discoveredEntries else { continue }
            discoveredEntries = result.entries
            publishEntries()
        } while refreshPending
    }

    private struct ScanResult: Sendable {
        let entries: [AppEntry]
        let cache: SpotlightNames.Cache
        let paneCache: SettingsPaneScanner.Cache?
        let metaCache: BundleMetaCache
    }

    nonisolated private static func scan(
        scopes: [String], cache: SpotlightNames.Cache, paneCache: SettingsPaneScanner.Cache?,
        metaCache: BundleMetaCache = BundleMetaCache()
    ) -> ScanResult {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var metaCache = metaCache
            var seenBundleIDs = Set<String>()
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let (name, bundleID, executable) = metaCache.metadata(for: url)
                // Dedup by bundle id; the earliest scope wins.
                if let bundleID, !seenBundleIDs.insert(bundleID).inserted { continue }

                result.append(
                    AppEntry(
                        id: url.path, name: name, url: url, bundleID: bundleID,
                        kind: .application,
                        alternateNames: cache.alternateNames(for: url, displayName: name),
                        executableName: executable.flatMap {
                            $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0
                        }))
            }
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
            let (panes, panesCache) = SettingsPaneScanner.scan(cache: paneCache)
            let entries = (apps + panes).map { entry -> AppEntry in
                var e = entry
                e.normalizedSearchFields = SearchFieldsNormalized(from: e.searchFields)
                return e
            }
            return ScanResult(entries: entries, cache: cache, paneCache: panesCache, metaCache: metaCache)
        }
    }

    private func publishEntries() {
        let combined =
            discoveredEntries + quicklinkEntries + snippetEntries + Self.systemActionEntries
            + windowCommandEntries + customCommandEntries + commandEntries
        let updated = combined.map { entry -> AppEntry in
            guard entry.normalizedSearchFields == nil else { return entry }
            var normalized = entry
            normalized.normalizedSearchFields = SearchFieldsNormalized(from: entry.searchFields)
            return normalized
        }
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    /// Ranked matches. Empty query returns the full alphabetical list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        let key = MatchKey(
            query: q, entriesRevision: entriesRevision, rankingRevision: ranking.revision)
        let cached = matchMemo.value(for: key) { rank(q, limit: limit) }
        return cached
    }

    /// The launcher's ordered list: ranked matches minus hidden entries, favorites pinned first.
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore
    ) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let key = ResultsKey(
            query: q, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            visibilityRevision: visibility.revision, favoritesRevision: favorites.revision)
        let result = resultsMemo.value(for: key) {
            // Filtering stays downstream of `matches` so that memo is never keyed on hidden state.
            let base = matches(q).filter(visibility.isVisible)
            guard q.isEmpty, !favorites.keys.isEmpty else { return base }
            let split = favorites.ordered(base)
            return split.favorites + split.rest
        }
        return result
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        let learned = ranking.boosts(query: q)
        let query = FuzzyMatch.Query(q)
        var scored: [(AppEntry, Int)] = []
        scored.reserveCapacity(apps.count)
        for app in apps {
            guard let match = scoreOne(
                app: app, query: query, queryChars: query.characterSet, learned: learned)
            else { continue }
            scored.append(match)
        }
        return
            scored
            .sorted {
                $0.1 != $1.1
                    ? $0.1 > $1.1
                    : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private func scoreOne(
        app: AppEntry, query: FuzzyMatch.Query, queryChars: Set<Character>,
        learned: [String: Int]
    ) -> (AppEntry, Int)? {
        let baseScore: Int?
        if let nf = app.normalizedSearchFields {
            guard queryChars.isSubset(of: nf.characterSet) else { return nil }
            baseScore = SearchRelevance.score(query: query, normalizedFields: nf)
        } else {
            baseScore = SearchRelevance.score(query: query.text, fields: app.searchFields)
        }
        guard let score = baseScore else { return nil }
        return (app, score + (learned[app.preferenceKey] ?? 0))
    }
}
