import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind

    var kindLabel: String {
        switch kind {
        case .application: return "Application"
        case .systemSettings: return "System Setting"
        case .command: return "Command"
        }
    }

    /// The global-hotkey action that opens this entry, or `nil` when it has no bundle ID
    /// (nothing stable to key the binding on). Commands have no bundle ID, so no hotkeys.
    var hotKeyAction: HotKeyAction? {
        guard let bundleID else { return nil }
        switch kind {
        case .application: return .app(bundleID: bundleID)
        case .systemSettings: return .settingsPane(bundleID: bundleID)
        case .command: return nil
        }
    }

    @MainActor var icon: NSImage {
        if kind == .command {
            return IconCache.symbolIcon(
                named: CommandRegistry.command(for: self)?.sfSymbol ?? "questionmark")
        }
        return IconCache.icon(forFile: url.path)
    }
}

/// Caches app icons by file path so list rows don't re-hit `NSWorkspace` on every render.
///
/// `NSWorkspace` returns a multi-representation icon with reps up to 512/1024px, but we only ever draw
/// it at ≤24pt — caching those raw is what spiked Settings' App-Hotkeys list to hundreds of MB. So we
/// downsample each icon once to a small fixed bitmap and byte-bound the cache (system-evicted under
/// pressure, like `ImageThumbnail`).
@MainActor
enum IconCache {
    // Icons display at ≤24pt, so 48pt (2× for Retina) is plenty crisp. Keeping each icon this small is
    // also what stops the launcher from ballooning: a `LazyVStack` scrolled to the bottom materializes
    // every app row and pins its icon, so per-icon size sets the ceiling. At ~36KB the whole app set is
    // a shared ~18MB (fits the cache with no eviction) instead of 500 distinct 256KB copies (~128MB).
    private static let displayPixel: CGFloat = 48

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Command "icons": an SF Symbol centered on a rounded tile, rendered once into the same small
    /// bitmap shape as app icons so `AppRow`/`ShortcutRow` treat every entry identically.
    static func symbolIcon(named name: String) -> NSImage {
        let key = "symbol:" + name as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let side = displayPixel
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Tile inset mirrors the margin macOS app icons carry inside their canvas.
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
            NSColor.white.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9).fill()

            let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
                .applying(.init(paletteColors: [.white.withAlphaComponent(0.85)]))
            guard
                let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            else { return true }
            let size = symbol.size
            symbol.draw(
                in: NSRect(
                    x: (side - size.width) / 2, y: (side - size.height) / 2,
                    width: size.width, height: size.height))
            return true
        }
        let (icon, cost) = downsampled(image)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Rasterize the multi-rep workspace icon into one `displayPixel`-square bitmap so the cache holds
    /// ~64–256KB per app instead of multi-MB. Returns the image and its decoded byte cost.
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int(displayPixel * scale)
        let fallbackCost = Int(displayPixel * displayPixel * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPixel, height: displayPixel)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return (source, fallbackCost) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
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
                result.append(
                    AppEntry(
                        id: url.path, name: name, url: url, bundleID: bundleID,
                        kind: .application))
            }
        }
        // Apps (sorted by name), then Settings panes, then Commands (each sorted by name). The
        // launcher's sectioned list relies on this invariant: with an empty query the results are
        // contiguous runs of favorites/apps/panes/commands, so the flat selection index maps 1:1
        // onto sectioned rows.
        let apps = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return apps + SettingsPaneScanner.scan() + CommandRegistry.all
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
