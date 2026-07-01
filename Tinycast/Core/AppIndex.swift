import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    let id: String  // file path — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?

    @MainActor var icon: NSImage {
        IconCache.icon(forFile: url.path)
    }
}

/// Caches app icons by file path so list rows don't re-hit `NSWorkspace` on every render. The app
/// set is small and stable, so a plain count-capped `NSCache` (system-evicted under pressure) is
/// enough — mirrors the `ImageThumbnail` cache.
enum IconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    @MainActor
    static func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

@MainActor
final class AppIndex: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    /// One-entry memo so repeated renders for the same query (e.g. while hovering moves the
    /// selection) reuse the ranking instead of re-running the fuzzy match every frame.
    private var matchCache: (query: String, result: [AppEntry])?

    func refresh() async {
        let found = await Task.detached(priority: .utility) { AppIndex.scan() }.value
        apps = found
        matchCache = nil
    }

    nonisolated private static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var searchDirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ].map { URL(fileURLWithPath: $0) }
        searchDirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))

        var seenBundleIDs = Set<String>()
        var result: [AppEntry] = []
        for dir in searchDirs {
            guard
                let items = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )
            else { continue }
            for url in items where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                // Dedup by bundle id; first directory (/Applications) wins.
                if let bundleID, !seenBundleIDs.insert(bundleID).inserted { continue }

                let name =
                    (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                result.append(AppEntry(id: url.path, name: name, url: url, bundleID: bundleID))
            }
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Ranked matches. Empty query returns the full alphabetical list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        if let matchCache, matchCache.query == q { return matchCache.result }
        let result = rank(q, limit: limit)
        matchCache = (q, result)
        return result
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            guard let score = FuzzyMatch.score(query: q, candidate: app.name) else { return nil }
            return (app, score)
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
}

enum FuzzyMatch {
    /// Tiered relevance score; higher is better. Returns nil when the query doesn't match at all.
    /// Tiers are spaced far enough apart that a better kind always beats a worse one.
    static func score(query: String, candidate: String) -> Int? {
        let q = query.lowercased()
        let c = candidate.lowercased()
        guard !q.isEmpty else { return 0 }

        if c == q { return 100_000 }
        if c.hasPrefix(q) { return 90_000 - c.count }

        if let range = c.range(of: q) {
            let atWordStart = isWordStart(c, range.lowerBound)
            return (atWordStart ? 80_000 : 70_000) - c.count
        }

        guard let sub = subsequenceScore(Array(q), Array(c)) else { return nil }
        return sub
    }

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    /// Subsequence match with bonuses for consecutive hits and word boundaries.
    /// Returns nil when `q` is not a subsequence of `c`. Always below the substring tier.
    private static func subsequenceScore(_ q: [Character], _ c: [Character]) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var bonus = 1
            if ci == prev + 1 {
                run += 1
                bonus += run * 3
            } else {
                run = 0
            }
            if ci == 0 {
                bonus += 12
            } else {
                let before = c[ci - 1]
                if !before.isLetter && !before.isNumber { bonus += 8 }
            }
            score += bonus
            prev = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score
    }
}
