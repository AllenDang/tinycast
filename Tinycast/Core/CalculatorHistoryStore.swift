import Foundation

/// One past calculation, recorded when the user copies an answer.
struct CalcHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let result: String
    let createdAt: Date
}

/// Persists recent calculations as a JSON file — same shape as before (a small `@Published` array
/// written back on every mutation) but on disk under `~/Library/Caches/<bundle-id>/`, alongside
/// `ClipboardStore`'s sqlite db and image blobs, so `brew uninstall --zap` (which trashes that whole
/// directory) removes it too. Capped, so the file stays tiny and search is a plain scan.
@MainActor
final class CalculatorHistoryStore: ObservableObject {
    private static let cap = 200

    private let fileURL: URL

    @Published private(set) var entries: [CalcHistoryEntry]  // newest first

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("calculator-history.json")

        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([CalcHistoryEntry].self, from: data)
        {
            entries = decoded
        } else {
            entries = []
        }
    }

    func record(expression: String, result: String) {
        // Re-copying the same answer (Enter twice, or from history) shouldn't stack duplicates.
        if let latest = entries.first, latest.expression == expression, latest.result == result {
            return
        }
        entries.insert(
            CalcHistoryEntry(id: UUID(), expression: expression, result: result, createdAt: Date()),
            at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        persist()
    }

    func remove(_ entry: CalcHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clearAll() {
        entries = []
        persist()
    }

    /// Case-insensitive substring match over both sides of each calculation.
    func search(_ query: String) -> [CalcHistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.expression.localizedCaseInsensitiveContains(q)
                || $0.result.localizedCaseInsensitiveContains(q)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
