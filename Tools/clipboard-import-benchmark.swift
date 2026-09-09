import Darwin
import Foundation
import SQLite3

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@main
@MainActor
enum ClipboardImportBenchmark {
    static func main() throws {
        let history = Int(CommandLine.arguments.dropFirst().first ?? "20000")!
        let incoming = Int(CommandLine.arguments.dropFirst(2).first ?? "2000")!
        let duplicatePercent = Int(CommandLine.arguments.dropFirst(3).first ?? "50")!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-import-benchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(directory: root)
        store.maxAge = .greatestFiniteMagnitude
        let database = root.appendingPathComponent("clipboard.sqlite3")
        var db: OpaquePointer?
        precondition(sqlite3_open(database.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var insert: OpaquePointer?
        precondition(sqlite3_prepare_v2(db,
            "INSERT INTO items(id,kind,text,image_path,created_at) VALUES(?,?,?,?,?)", -1, &insert, nil) == SQLITE_OK)
        precondition(sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK)
        for index in 0..<history {
            let item = item(index)
            sqlite3_bind_text(insert, 1, item.id.uuidString, -1, transient)
            sqlite3_bind_text(insert, 2, item.kind.rawValue, -1, transient)
            if let text = item.text { sqlite3_bind_text(insert, 3, text, -1, transient) }
            if let path = item.imagePath { sqlite3_bind_text(insert, 4, path, -1, transient) }
            sqlite3_bind_double(insert, 5, item.createdAt.timeIntervalSince1970)
            precondition(sqlite3_step(insert) == SQLITE_DONE)
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
        }
        sqlite3_finalize(insert)
        precondition(sqlite3_exec(db, "COMMIT; PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil) == SQLITE_OK)
        var entries: [ClipboardItem] = []
        for index in 0..<incoming {
            let source = index % 100 < duplicatePercent ? (index * 7919) % history : history + index
            entries.append(item(source))
            if index % 10 == 0 { entries.append(item(source)) }
        }
        let beforeSize = fileSize(database)
        var memoryBefore = rusage()
        getrusage(RUSAGE_SELF, &memoryBefore)
        let start = ContinuousClock.now
        let count = store.importEntries(entries)
        let elapsed = start.duration(to: .now)
        var memoryAfter = rusage()
        getrusage(RUSAGE_SELF, &memoryAfter)
        precondition(count == incoming * (100 - duplicatePercent) / 100, "wrong import count")
        precondition(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil) == SQLITE_OK)
        print("history=\(history) incoming=\(entries.count) existingDuplicates=\(duplicatePercent)% withinBatchDuplicates=\(incoming / 10)")
        print("inserted=\(count) elapsed=\(elapsed) peakRSSBeforeMiB=\(Double(memoryBefore.ru_maxrss) / 1048576) peakRSSAfterMiB=\(Double(memoryAfter.ru_maxrss) / 1048576)")
        print("databaseBeforeMiB=\(Double(beforeSize) / 1048576) databaseAfterMiB=\(Double(fileSize(database)) / 1048576)")
        var plan: OpaquePointer?
        sqlite3_prepare_v2(db, "EXPLAIN QUERY PLAN SELECT 1 FROM items WHERE text = ? LIMIT 1", -1, &plan, nil)
        while sqlite3_step(plan) == SQLITE_ROW {
            print("equalityPlan=" + String(cString: sqlite3_column_text(plan, 3)))
        }
        sqlite3_finalize(plan)
    }

    static func item(_ index: Int) -> ClipboardItem {
        let isImage = index % 10 == 1
        let text = index % 20 == 0
            ? String(repeating: "long clipboard text café \n", count: 650) + "\(index)"
            : "clipboard record \(index) ordinary exact text"
        return ClipboardItem(
            id: UUID(), kind: isImage ? .image : .text, text: isImage ? nil : text,
            imagePath: isImage ? "/fixture-only/images/" + String(repeating: "folder/", count: 12) + "\(index).png" : nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)), sourceBundleID: nil)
    }

    static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
