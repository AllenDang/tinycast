#!/usr/bin/env swift

import Foundation

// MARK: - Minimal timer

struct PerfTimer {
    let label: String
    let start: Date
    init(_ label: String) {
        self.label = label
        self.start = Date()
    }
    func stop() -> Double {
        let elapsed = Date().timeIntervalSince(start) * 1000
        print("  \(label): \(String(format: "%.2f", elapsed)) ms")
        return elapsed
    }
}

// MARK: - AppIndex scan measurement

func measureAppIndexScan() {
    print("\n=== AppIndex Scan ===")
    let scopes = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
    let cache = SpotlightNames.Cache()
    var paneCache: SettingsPaneScanner.Cache?

    // Warm-up
    _ = AppIndex.scanInternal(scopes: scopes, cache: SpotlightNames.Cache(), paneCache: nil)

    // Cold scan (no cache)
    let cold = PerfTimer("Cold scan")
    let (_, _, _) = AppIndex.scanInternal(scopes: scopes, cache: SpotlightNames.Cache(), paneCache: nil)
    let coldMs = cold.stop()

    // Warm scan (with cache)
    let warm = PerfTimer("Warm scan (reusing cache)")
    let (_, _, _) = AppIndex.scanInternal(scopes: scopes, cache: SpotlightNames.Cache(reusing: cache), paneCache: paneCache)
    let warmMs = warm.stop()

    print("  Cold/warm ratio: \(String(format: "%.1f", coldMs / max(warmMs, 0.01)))x")
}

// MARK: - Calculator measurement

func measureCalculator() {
    print("\n=== Calculator Engine ===")

    let appQueries = [
        "safari", "chrome", "visual studio code", "terminal", "messages",
        "system settings", "photos", "music", "calendar", "reminders",
        "notes", "mail", "finder", "xcode", "slack", "discord", "zoom",
        "firefox", "preview", "activity monitor"
    ]

    let calcQueries = [
        "2+2", "100*3.14", "sqrt(144)", "10 km to miles", "100 usd to eur",
        "20% of 500", "0xff to decimal", "2^10", "sin(0.5)", "100/3",
        "1e6", "1 hour to seconds", "1000g to kg", "32C to F", "42*42"
    ]

    // Warm-up
    for q in appQueries + calcQueries { _ = CalcEngine.evaluate(q) }

    // App queries (should be fast-rejected)
    let appTimer = PerfTimer("\(appQueries.count) app-name queries")
    for _ in 0..<100 {
        for q in appQueries { _ = CalcEngine.evaluate(q) }
    }
    let appMs = appTimer.stop()
    let appPerQuery = appMs / Double(appQueries.count * 100)

    // Calc queries
    let calcTimer = PerfTimer("\(calcQueries.count) calculator queries")
    for _ in 0..<100 {
        for q in calcQueries { _ = CalcEngine.evaluate(q) }
    }
    let calcMs = calcTimer.stop()
    let calcPerQuery = calcMs / Double(calcQueries.count * 100)

    print("  App query avg: \(String(format: "%.3f", appPerQuery)) ms")
    print("  Calc query avg: \(String(format: "%.3f", calcPerQuery)) ms")
}

// MARK: - Emoji load measurement

func measureEmojiLoad() {
    print("\n=== Emoji Catalog Load ===")
    let timer = PerfTimer("EmojiCatalog.parse")
    let entries = EmojiCatalog.parse(EmojiData.raw)
    let ms = timer.stop()
    print("  Entries: \(entries.count)")
}

// MARK: - Main

print("Tinycast Performance Baseline")
print("=============================")

measureAppIndexScan()
measureCalculator()
measureEmojiLoad()

print("\nDone.")