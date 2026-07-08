import AppKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ClipboardItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case text, image }

    let id: UUID
    let kind: Kind
    let text: String?
    let imageFileName: String?
    let createdAt: Date
    /// Bundle ID of the app frontmost when the copy was captured (see `ClipboardManager.poll`).
    let sourceBundleID: String?

    init(text: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .text, text: text, imageFileName: nil, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    init(imageFileName: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .image, text: nil, imageFileName: imageFileName, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    init(
        id: UUID, kind: Kind, text: String?, imageFileName: String?, createdAt: Date,
        sourceBundleID: String?
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
    }
}

/// How long clipboard history is kept before entries are pruned. Raw value is the age in days,
/// which is also what gets persisted to UserDefaults. `forever` is -1 (not 0) because an unset
/// UserDefaults key reads as 0 and must keep falling through to the default.
enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .year: return "1 Year"
        case .forever: return "Forever"
        }
    }

    var maxAge: TimeInterval {
        self == .forever ? .greatestFiniteMagnitude : TimeInterval(rawValue) * 86_400
    }
}

/// SQLite-backed clipboard history: rows + FTS5 index in `clipboard.sqlite3`, image blobs on disk.
/// The trigram tokenizer gives case-insensitive *substring* search over the full table, while
/// `items` mirrors only the newest rows for browsing. If the database can't be opened the store
/// degrades to session-only in-memory history.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    private static let memoryWindow = 1000

    private static let schema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_file TEXT,
          created_at REAL NOT NULL,
          source_app TEXT
        );
        CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
          text, content='items', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
        """

    private let imagesDir: URL
    private let dbURL: URL
    private var db: OpaquePointer?
    private var insertStmt: OpaquePointer?
    private var loadStmt: OpaquePointer?
    private var searchStmt: OpaquePointer?
    private var deleteByIDStmt: OpaquePointer?
    private var staleImagesStmt: OpaquePointer?
    private var deleteStaleStmt: OpaquePointer?

    init() {
        // Stored under ~/Library/Caches/<bundle-id>, the same convention Raycast uses — clipboard
        // history is regenerable, and the in-app "Clear History" button is the durable control.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: base.appendingPathComponent("clipboard.json"))
        if !openDatabase() {
            // The database is a regenerable cache: discard a corrupt one and start over.
            closeDatabase()
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
            }
            if !openDatabase() { closeDatabase() }
        }
    }

    // Isolated so teardown may touch the main-actor statement/db pointers; the store is only ever
    // released on the main actor (AppCore owns it), so the deinit runs there with no hop.
    isolated deinit {
        closeDatabase()
    }

    func load() {
        guard let stmt = loadStmt else { return }
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow))
        var loaded: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = Self.row(stmt) { loaded.append(item) }
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        items = loaded
        // Age passes while the app isn't running; insert-time pruning alone can't catch that.
        enforceLimits()
    }

    /// Called on load and when the retention setting changes.
    func enforceLimits() {
        prune()
    }

    func addText(_ text: String, sourceBundleID: String?) {
        if items.first?.kind == .text, items.first?.text == text { return }
        insert(ClipboardItem(text: text, sourceBundleID: sourceBundleID))
    }

    func addImage(_ data: Data, sourceBundleID: String?) {
        let name = UUID().uuidString + ".png"
        let url = imagesDir.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        insert(ClipboardItem(imageFileName: name, sourceBundleID: sourceBundleID))
    }

    func remove(_ item: ClipboardItem) {
        if let stmt = deleteByIDStmt {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
    }

    func clearAll() {
        if db != nil { sqlite3_exec(db, "DELETE FROM items", nil, nil, nil) }
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        items = []
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func search(_ query: String) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        // Trigram FTS needs at least 3 characters; shorter queries (and the no-database degrade
        // path) fall back to filtering the in-memory window.
        guard let stmt = searchStmt, q.count >= 3 else { return fallbackSearch(q) }
        let match = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        var results: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt) { results.append(item) }
            status = sqlite3_step(stmt)
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        return status == SQLITE_DONE ? results : fallbackSearch(q)
    }

    // MARK: - Private

    private func fallbackSearch(_ q: String) -> [ClipboardItem] {
        items.filter { ($0.text?.localizedCaseInsensitiveContains(q)) ?? false }
    }

    private func insert(_ item: ClipboardItem) {
        if let stmt = insertStmt {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
            if let text = item.text {
                sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            if let name = item.imageFileName {
                sqlite3_bind_text(stmt, 4, name, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
            if let source = item.sourceBundleID {
                sqlite3_bind_text(stmt, 6, source, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        items.insert(item, at: 0)
        if items.count > Self.memoryWindow { items.removeLast() }
        prune()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        if let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt {
            sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
            while sqlite3_step(imagesStmt) == SQLITE_ROW {
                if let name = Self.columnString(imagesStmt, 0) {
                    try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
                }
            }
            sqlite3_reset(imagesStmt)
            sqlite3_clear_bindings(imagesStmt)
            sqlite3_bind_double(deleteStmt, 1, cutoff.timeIntervalSince1970)
            sqlite3_step(deleteStmt)
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
        }
        if items.last.map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff }
        }
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let name = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
    }

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        // Migrates pre-source_app databases; fails harmlessly ("duplicate column") on current ones.
        sqlite3_exec(db, "ALTER TABLE items ADD COLUMN source_app TEXT", nil, nil, nil)
        insertStmt = prepare(
            "INSERT INTO items(id, kind, text, image_file, created_at, source_app) VALUES(?,?,?,?,?,?)"
        )
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_file, created_at, source_app FROM items
            ORDER BY rowid DESC LIMIT ?
            """)
        searchStmt = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_file, i.created_at, i.source_app FROM items_fts f
            JOIN items i ON i.rowid = f.rowid WHERE items_fts MATCH ? ORDER BY f.rowid DESC LIMIT 200
            """)
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        staleImagesStmt = prepare(
            "SELECT image_file FROM items WHERE created_at < ? AND image_file IS NOT NULL")
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ?")
        return insertStmt != nil && loadStmt != nil && searchStmt != nil
            && deleteByIDStmt != nil && staleImagesStmt != nil && deleteStaleStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func closeDatabase() {
        [insertStmt, loadStmt, searchStmt, deleteByIDStmt, staleImagesStmt, deleteStaleStmt]
            .forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        searchStmt = nil
        deleteByIDStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imageFileName: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5))
    }

    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
