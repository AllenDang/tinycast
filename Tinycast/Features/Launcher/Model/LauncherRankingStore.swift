import Foundation

/// One learned launcher choice for a normalized query prefix.
struct LauncherRankingRecord: Codable, Hashable, Sendable {
    let itemKey: String
    let query: String
    var count: Int
    var lastUsed: Date
}

@MainActor
@Observable
final class LauncherRankingStore {
    private static let cap = 1_000
    private static let maximumBoost = 4_500

    private let fileURL: URL
    private let now: () -> Date

    private(set) var records: [LauncherRankingRecord] = []
    private(set) var revision = 0

    /// `boosts(query:)` builds this from a launcher render; tracked, the write lands mid-body.
    @ObservationIgnored private var lookup: [String: [String: LauncherRankingRecord]]?
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var pendingWrite = false

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now
    }

    private func ensureLoaded() {
        guard !isLoaded else { return }
        isLoaded = true
        if let data = try? Data(contentsOf: self.fileURL),
            let decoded = try? JSONDecoder().decode([LauncherRankingRecord].self, from: data) {
            records = decoded.filter {
                !$0.itemKey.isEmpty && !$0.query.isEmpty && $0.count > 0
            }
        }
    }

    var isEmpty: Bool { records.isEmpty }

    func record(itemKey: String, query: String) {
        ensureLoaded()
        let query = Self.normalize(query)
        guard !itemKey.isEmpty, !query.isEmpty else { return }

        let timestamp = now()
        for prefix in Self.prefixes(of: query) {
            if let index = records.firstIndex(where: {
                $0.itemKey == itemKey && $0.query == prefix
            }) {
                records[index].count += 1
                records[index].lastUsed = timestamp
            } else {
                records.append(
                    LauncherRankingRecord(
                        itemKey: itemKey, query: prefix, count: 1, lastUsed: timestamp))
            }
        }

        if records.count > Self.cap {
            records.sort {
                $0.count != $1.count ? $0.count > $1.count : $0.lastUsed > $1.lastUsed
            }
            records.removeLast(records.count - Self.cap)
        }
        didMutate()
    }

    func boosts(query: String) -> [String: Int] {
        ensureLoaded()
        let query = Self.normalize(query)
        guard !query.isEmpty, let learned = rankingLookup()[query] else { return [:] }
        let timestamp = now()
        let result = learned.mapValues { boost($0, at: timestamp) }
        return result
    }

    private func boost(_ record: LauncherRankingRecord, at timestamp: Date) -> Int {
        let ageInDays = max(0, timestamp.timeIntervalSince(record.lastUsed)) / 86_400
        let frequency = min(3_000, log2(Double(record.count) + 1) * 600)
        let recency = 1_500 * exp(-ageInDays / 14)
        return min(Self.maximumBoost, Int((frequency + recency).rounded()))
    }

    func hasRanking(for itemKey: String) -> Bool {
        ensureLoaded()
        return records.contains { $0.itemKey == itemKey }
    }

    func reset(itemKey: String) {
        ensureLoaded()
        let oldCount = records.count
        records.removeAll { $0.itemKey == itemKey }
        guard records.count != oldCount else { return }
        didMutate()
    }

    func resetAll() {
        ensureLoaded()
        guard !records.isEmpty else { return }
        records = []
        didMutate()
    }

    static func normalize(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func prefixes(of query: String) -> [String] {
        let limit = min(query.count, 64)
        var result: [String] = []
        result.reserveCapacity(limit)
        var end = query.startIndex
        for _ in 0..<limit {
            end = query.index(after: end)
            result.append(String(query[..<end]))
        }
        return result
    }

    private func rankingLookup() -> [String: [String: LauncherRankingRecord]] {
        if let lookup { return lookup }
        var built: [String: [String: LauncherRankingRecord]] = [:]
        for record in records {
            built[record.query, default: [:]][record.itemKey] = record
        }
        lookup = built
        return built
    }

    private func didMutate() {
        lookup = nil
        revision &+= 1
        scheduleWrite()
    }

    private func scheduleWrite() {
        guard !pendingWrite else { return }
        pendingWrite = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.pendingWrite = false
            self?.flush()
        }
    }

    func flush() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launcher-ranking.json")
    }
}
