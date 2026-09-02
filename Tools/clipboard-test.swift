// Standalone test for the clipboard store — compiles the *real* source (no copy to sync):
// swiftc -swift-version 6 Tinycast/Features/Clipboard/Model/ClipboardStore.swift \
//     Tools/clipboard-test.swift -o /tmp/clipboard-test && /tmp/clipboard-test
//
// Every store here is built on a throwaway directory under the system temp dir, so a run can never
// see or touch a real clipboard history.

import Foundation

@main
@MainActor
struct ClipboardTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        let args = CommandLine.arguments
        if args.contains("--bench") {
            benchInsertThroughput()
            return
        }
        if args.contains("--bench-import") {
            benchImportThroughput()
            return
        }

        pinOrder()
        unpinRejoinsAsNewest()
        pasteLeavesPinsAlone()
        pinsSurvivePruningAndTheWindow()
        pinsLeadFilteredSearches()
        persistence()
        freshSchema()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    /// Pins stack in pin order, oldest pin first, regardless of how old the entries are.
    static func pinOrder() {
        withStore { store, _ in
            store.addText("oldest", sourceBundleID: nil)
            store.addText("middle", sourceBundleID: nil)
            store.addText("newest", sourceBundleID: nil)

            store.togglePinned(item(store, "oldest"))
            expect(texts(store) == ["oldest", "newest", "middle"], "first pin leads the list")

            store.togglePinned(item(store, "middle"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "second pin joins below the first, and does not sort by recency")

            store.togglePinned(item(store, "newest"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "pins hold pin order, not the recency order they had in the history")
        }
    }

    /// Unpinning drops the row in as today's newest entry rather than back where it came from.
    static func unpinRejoinsAsNewest() {
        withStore { store, _ in
            store.addText("a", sourceBundleID: nil)
            store.addText("b", sourceBundleID: nil)
            store.addText("c", sourceBundleID: nil)
            let before = item(store, "a").createdAt

            store.togglePinned(item(store, "a"))
            store.togglePinned(item(store, "a"))

            expect(texts(store) == ["a", "c", "b"], "unpinned row leads the history")
            expect(!item(store, "a").isPinned, "pin stamp cleared")
            expect(item(store, "a").createdAt > before, "unpin re-recencies the row")
        }
    }

    /// Pasting a pinned entry must not reshuffle the Pinned section.
    static func pasteLeavesPinsAlone() {
        withStore { store, _ in
            store.addText("one", sourceBundleID: nil)
            store.addText("two", sourceBundleID: nil)
            store.togglePinned(item(store, "one"))
            store.togglePinned(item(store, "two"))
            let stamp = item(store, "one").createdAt

            store.promote(item(store, "one"))

            expect(texts(store) == ["one", "two"], "promote leaves a pinned row in place")
            expect(item(store, "one").createdAt == stamp, "promote does not rewrite a pinned row")

            store.addText("three", sourceBundleID: nil)
            store.addText("four", sourceBundleID: nil)
            store.promote(item(store, "three"))
            expect(
                texts(store) == ["one", "two", "three", "four"],
                "an unpinned row still promotes to the head of the history")
        }
    }

    /// Retention sweeps everything around a pin but never the pin itself.
    static func pinsSurvivePruningAndTheWindow() {
        withStore { store, dir in
            // Older than the 1-day retention the case sets below, but inside the default the import prunes against.
            let old = Date().addingTimeInterval(-2 * 86_400)
            _ = store.importEntries([
                entry("ancient-pinned", at: old),
                entry("ancient-loose", at: old.addingTimeInterval(1)),
                entry("fresh", at: Date()),
            ])
            store.togglePinned(item(store, "ancient-pinned"))

            store.maxAge = 86_400
            store.enforceLimits()
            expect(
                Set(texts(store)) == ["ancient-pinned", "fresh"],
                "pruning skips pinned rows and takes the rest")

            // Reopen: the pin must come back even though it is far outside the retention window.
            let reopened = ClipboardStore(directory: dir)
            reopened.maxAge = 86_400
            reopened.load()
            expect(
                Set(texts(reopened)) == ["ancient-pinned", "fresh"],
                "a pin outlives retention across a relaunch")
        }
    }

    /// A pin must lead a filtered search even when the FTS statement's LIMIT cannot reach it.
    static func pinsLeadFilteredSearches() {
        withStore { store, _ in
            var seed: [ClipboardItem] = []
            let base = Date().addingTimeInterval(-10_000)
            // The pinned hit is the oldest of 260 matches; the FTS statement stops at 200.
            seed.append(entry("needle in the haystack", at: base))
            for i in 1...259 {
                seed.append(entry("haystack filler \(i)", at: base.addingTimeInterval(Double(i))))
            }
            _ = store.importEntries(seed)
            store.togglePinned(item(store, "needle in the haystack"))

            let results = store.search("haystack")
            expect(results.count > 200, "FTS results plus the pinned block")
            expect(
                results.first?.text == "needle in the haystack",
                "the pinned match leads the filtered results")
            expect(
                results.filter(\.isPinned).count == 1, "the pinned row is not duplicated")

            let short = store.search("ne")  // below the trigram threshold: the fallback path
            expect(
                short.first?.text == "needle in the haystack",
                "the pinned match leads the fallback search too")
        }
    }

    /// Pin stamps and their order survive a reopen.
    static func persistence() {
        withStore { store, dir in
            store.addText("first", sourceBundleID: nil)
            store.addText("second", sourceBundleID: nil)
            store.addText("third", sourceBundleID: nil)
            store.togglePinned(item(store, "third"))
            store.togglePinned(item(store, "first"))

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(
                texts(reopened) == ["third", "first", "second"],
                "pin order is restored from disk, not recomputed from recency")

            reopened.togglePinned(item(reopened, "third"))
            expect(texts(reopened) == ["first", "third", "second"], "unpin after a reload")

            reopened.clearAll()
            expect(reopened.items.isEmpty, "Clear History takes pins too")
        }
    }

    static func freshSchema() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("clipboard.sqlite3")
        let store = ClipboardStore(directory: dir)

        let columns = sqlite(db, "SELECT name FROM pragma_table_info('items')")
        expect(
            columns == ["id", "kind", "text", "image_path", "created_at", "source_app", "pinned_at"],
            "the fresh schema declares all seven item columns")
        expect(
            sqlite(db, "SELECT name FROM sqlite_master WHERE type = 'index'")
                .contains("items_pinned_at"),
            "the fresh schema creates the pin index")

        store.addText("captured", sourceBundleID: "com.example.source")
        store.togglePinned(item(store, "captured"))
        let reopened = ClipboardStore(directory: dir)
        reopened.load()
        expect(reopened.items.first?.sourceBundleID == "com.example.source", "source app persists")
        expect(reopened.items.first?.isPinned == true, "pin stamp persists")
    }

    // MARK: - Benchmark

    /// Measure import throughput: time to import `count` entries via `importEntries()`, reporting total and per-insert averages.
    static func benchImportThroughput() {
        let count = 500
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)

        let base = Date().addingTimeInterval(-10_000)
        var entries: [ClipboardItem] = []
        for i in 0..<count {
            entries.append(entry("import bench item \(i)", at: base.addingTimeInterval(Double(i))))
        }

        let start = CFAbsoluteTimeGetCurrent()
        let inserted = store.importEntries(entries)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("Imported \(inserted) of \(count) entries in \(String(format: "%.2f", elapsed))ms")
        print("Per-entry: \(String(format: "%.3f", elapsed / Double(count)))ms")
        print("Store item count: \(store.items.count)")
    }

    /// Measure insert throughput: time to insert `count` items, reporting total and per-insert averages.
    static func benchInsertThroughput() {
        let count = 200
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)

        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<count {
            store.addText("bench item \(i)", sourceBundleID: nil)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("Inserted \(count) items in \(String(format: "%.2f", elapsed))ms")
        print("Per-insert: \(String(format: "%.3f", elapsed / Double(count)))ms")
        print("Store item count: \(store.items.count)")
    }

    // MARK: - Harness

    /// Runs `body` against a store rooted in a fresh temp directory, torn down afterwards.
    static func withStore(_ body: (ClipboardStore, URL) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ClipboardStore(directory: dir), dir)
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tinycast-clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func sqlite(_ database: URL, _ sql: String) -> Set<String> {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [database.path, sql]
        task.standardOutput = pipe
        guard (try? task.run()) != nil else {
            fail("could not run sqlite3")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 { fail("sqlite3 failed: \(sql.prefix(60))") }
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    static func entry(_ text: String, at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: date,
            sourceBundleID: nil)
    }

    static func texts(_ store: ClipboardStore) -> [String] {
        store.search("").compactMap(\.text)
    }

    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            fail("no entry named \(text)")
            exit(1)
        }
        return match
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
