import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    let id: String          // bundle identifier, or path if none
    let name: String
    let url: URL
    let bundleID: String?

    @MainActor var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

@MainActor
final class AppIndex: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    func refresh() async {
        let found = await Task.detached(priority: .utility) { AppIndex.scan() }.value
        apps = found
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

        var seen = Set<String>()
        var result: [AppEntry] = []
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension == "app" {
                let bundleID = Bundle(url: url)?.bundleIdentifier
                let key = bundleID ?? url.path
                guard seen.insert(key).inserted else { continue }
                let name = fm.displayName(atPath: url.path)
                result.append(AppEntry(id: key, name: name, url: url, bundleID: bundleID))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Fuzzy-ranked matches. Empty query returns the alphabetical list.
    func matches(_ query: String, limit: Int = 60) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(apps.prefix(limit)) }
        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            guard let score = FuzzyMatch.score(query: q, candidate: app.name) else { return nil }
            return (app, score)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name.count < $1.0.name.count }
            .prefix(limit)
            .map(\.0)
    }
}

enum FuzzyMatch {
    /// Subsequence match with bonuses for consecutive hits, word boundaries and prefixes.
    /// Returns nil when `query` is not a subsequence of `candidate`.
    static func score(query: String, candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }

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
        if c.starts(with: q) { score += 15 }
        return score
    }
}
