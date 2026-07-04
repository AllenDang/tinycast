import Foundation

/// One past calculation, recorded when the user copies an answer.
struct CalcHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let expression: String
    let result: String
    let createdAt: Date
}

/// Persists recent calculations as a JSON blob in UserDefaults — same shape as `FavoritesStore`:
/// a small `@Published` array written back on every mutation. Capped, so the blob stays tiny and
/// search is a plain scan.
@MainActor
final class CalculatorHistoryStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let key = "calculatorHistory"
    private static let cap = 200

    @Published private(set) var entries: [CalcHistoryEntry]  // newest first

    init() {
        if let data = defaults.data(forKey: key),
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
            defaults.set(data, forKey: key)
        }
    }
}
