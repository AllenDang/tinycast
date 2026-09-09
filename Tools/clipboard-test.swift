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
        importEquality()
        importMixedFieldsAndFailures()
        importBeyondWindowAndLongText()
        importHistoryFailure()

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

    static func importEquality() {
        withStore { store, dir in
            store.maxAge = .greatestFiniteMagnitude
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            store.addText("é", sourceBundleID: nil)
            expect(store.importEntries([entry("e\u{301}", at: base)]) == 1,
                   "historical text equality is binary, not Unicode canonical equality")
            expect(sqlite(dir.appendingPathComponent("clipboard.sqlite3"),
                          "SELECT hex(text) FROM items") == ["C3A9", "65CC81"],
                   "composed and decomposed text bytes both persist")
            store.clearAll()
            expect(store.importEntries([entry("é", at: base),
                                        entry("e\u{301}", at: base.addingTimeInterval(1))]) == 1,
                   "existing canonical within-batch seen-set semantics are preserved")
            expect(store.importEntries([entry("é", at: base),
                                        entry("e\u{301}", at: base.addingTimeInterval(1))]) == 1,
                   "skipped historical duplicate does not enter the within-batch seen set")
            store.clearAll()
            store.addText("prefix", sourceBundleID: nil)
            expect(store.importEntries([entry("prefix\0tail", at: base)]) == 0,
                   "historical lookup matches the binding's first-NUL truncation")
            store.clearAll()
            expect(store.importEntries([entry("prefix\0first", at: base),
                                        entry("prefix\0second", at: base.addingTimeInterval(1))]) == 1,
                   "successful insert prevents a later equivalent NUL-truncated value")
            expect(store.items.first?.text == "prefix", "stored text still truncates at NUL")
            store.clearAll()
            let db = dir.appendingPathComponent("clipboard.sqlite3")
            sqlite(db, "INSERT INTO items(id,kind,text,created_at) VALUES('\(UUID())','text','prefix'||char(0)||'stored',1700000000)")
            expect(store.importEntries([entry("prefix\0tail", at: base)]) == 1,
                   "a historical embedded NUL is not truncated during matching")
            expect(sqlite(db, "SELECT count(*) FROM items") == ["2"],
                   "historical embedded-NUL and bound-prefix records remain distinct")
            store.clearAll()
            let image = ClipboardItem(imagePath: "/fixture/image.png", sourceBundleID: nil)
            expect(store.importEntries([image, image]) == 1, "within-batch image duplicate skipped")
            expect(store.importEntries([image]) == 0, "historical image path duplicate skipped")
            expect(store.importEntries([ClipboardItem(imagePath: "/fixture/Image.png", sourceBundleID: nil)]) == 1,
                   "image path equality remains case-sensitive")
            expect(store.importEntries([ClipboardItem(imagePath: "/fixture/image.png\0suffix", sourceBundleID: nil)]) == 0,
                   "image path binding also truncates at NUL")
            store.clearAll()
            let nilText = ClipboardItem(id: UUID(), kind: .text, text: nil, imagePath: nil,
                                        createdAt: base, sourceBundleID: nil)
            expect(store.importEntries([nilText]) == 0, "nil primary payload is skipped")
            expect(store.importEntries([entry("", at: base), entry("\0suffix", at: base.addingTimeInterval(1))]) == 1,
                   "empty and first-NUL values match SQLite empty text")
        }
    }

    static func importMixedFieldsAndFailures() {
        withStore { store, dir in
            store.maxAge = .greatestFiniteMagnitude
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            func mixed(_ kind: ClipboardItem.Kind, _ text: String, _ path: String, _ offset: Double) -> ClipboardItem {
                ClipboardItem(id: UUID(), kind: kind, text: text, imagePath: path,
                              createdAt: base.addingTimeInterval(offset), sourceBundleID: nil)
            }
            let both = mixed(.text, "shared text", "/fixture/shared.png", 0)
            let image = ClipboardItem(imagePath: "/fixture/shared.png", createdAt: base.addingTimeInterval(1), sourceBundleID: nil)
            expect(store.importEntries([both, image]) == 1,
                   "text-kind insert also participates in path deduplication")
            expect(store.importEntries([image]) == 0, "historical path lookup ignores kind")
            store.clearAll()
            let bothImage = mixed(.image, "shared text", "/fixture/shared.png", 0)
            expect(store.importEntries([bothImage, entry("shared text", at: base.addingTimeInterval(1))]) == 1,
                   "image-kind insert also participates in text deduplication")
            expect(store.importEntries([entry("shared text", at: base)]) == 0,
                   "historical text lookup ignores kind")
            store.clearAll()
            let occupied = entry("occupied", at: base)
            expect(store.importEntries([occupied]) == 1, "seed occupied UUID")
            let failed = ClipboardItem(id: occupied.id, kind: .text, text: "new\0failed", imagePath: nil,
                                       createdAt: base.addingTimeInterval(1), sourceBundleID: nil)
            let successful = entry("new\0success", at: base.addingTimeInterval(2))
            expect(store.importEntries([failed, successful]) == 2,
                   "pre-existing API counts insert attempts, including UUID constraint failures")
            expect(sqlite(dir.appendingPathComponent("clipboard.sqlite3"), "SELECT count(*) FROM items") == ["2"],
                   "failed insert does not falsely add its SQL key to historical matches")
            expect(store.items.first?.id == successful.id, "later valid NUL-equivalent insert succeeds")
            let sameFailed = ClipboardItem(id: occupied.id, kind: .text, text: "not stored", imagePath: nil,
                                           createdAt: base.addingTimeInterval(3), sourceBundleID: nil)
            expect(store.importEntries([sameFailed, entry("not stored", at: base.addingTimeInterval(4))]) == 1,
                   "failed insertion still enters the pre-existing within-batch seen set")
            expect(!store.items.contains { $0.text == "not stored" }, "same-batch failed duplicate is not retried")
        }
    }

    static func importBeyondWindowAndLongText() {
        withStore { store, dir in
            store.maxAge = .greatestFiniteMagnitude
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            let history = (0..<1400).map { entry("history \($0)", at: base.addingTimeInterval(Double($0))) }
            expect(store.importEntries(history) == 1400, "seed history beyond memory window")
            expect(store.items.count == 1000, "resident history stays bounded")
            expect(store.importEntries([history[0], history[100], history[1399]]) == 0,
                   "deduplication includes nonresident history")
            let long = String(repeating: "long exact text café ", count: 3200)
            let oldest = entry(long, at: base.addingTimeInterval(2000))
            let newest = entry(long + "!", at: base.addingTimeInterval(2001))
            expect(store.importEntries([newest, oldest, oldest]) == 2, "long text exact dedup and count")
            expect(Array(store.items.prefix(2).map(\.id)) == [newest.id, oldest.id],
                   "unsorted incoming records retain oldest-first insertion/newest-first load")
            expect(store.importEntries([oldest, newest]) == 0, "long historical duplicates skipped")
            let db = dir.appendingPathComponent("clipboard.sqlite3")
            expect(sqlite(db, "SELECT name FROM sqlite_master WHERE type='index'")
                   == ["sqlite_autoindex_items_1", "items_created_at", "items_pinned_at"],
                   "no persistent large-text or image equality index added")
        }
    }

    static func importHistoryFailure() {
        withStore { store, dir in
            store.addText("unchanged", sourceBundleID: nil)
            let before = store.items
            let db = dir.appendingPathComponent("clipboard.sqlite3")
            sqlite(db, "ALTER TABLE items RENAME TO held_items")
            expect(store.importEntries([entry("incoming", at: Date())]) == 0,
                   "history-statement schema error aborts import before inserting")
            expect(store.items == before, "history read failure leaves resident state unchanged")
            expect(sqlite(db, "SELECT text FROM held_items") == ["unchanged"],
                   "history read failure leaves persisted rows unchanged")
            sqlite(db, "ALTER TABLE held_items RENAME TO items")
            expect(store.importEntries([entry("incoming", at: Date())]) == 1,
                   "failed read resets statement and rolls back its transaction for successful retry")
            expect(store.importEntries([entry("unchanged", at: Date())]) == 0,
                   "historical deduplication remains usable after retry")
        }
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
