import Foundation

@MainActor
@Observable
final class CurrencyRateStore {
    static let provider = "Frankfurter"
    static let providerURL = URL(string: "https://frankfurter.dev")!
    private nonisolated static let endpoint = URL(
        string: "https://api.frankfurter.dev/v2/rates?base=USD")!
    static let refreshInterval: TimeInterval = 24 * 3600
    private static let retryInterval: TimeInterval = 15 * 60

    private(set) var isEnabled: Bool

    private(set) var rates: CurrencyRates?

    private static let consentKey = "currencyRatesEnabled"
    private let defaults = UserDefaults.standard
    private let fileURL: URL
    @ObservationIgnored private var pump: Task<Void, Never>?

    init() {
        // Absent reads as false, which is the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Self.consentKey)
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")

        // Guard 1 — a disabled feature doesn't even read back a snapshot left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL) else { return }
        rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
    }

    var source: CurrencySource { isEnabled ? .on(rates) : .off }

    func start() {
        guard isEnabled else { return }
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self, self.isEnabled {
                let age = max(0, self.rates.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        if enabled {
            start()
        } else {
            pump?.cancel()
            pump = nil
            rates = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func refreshNow() async -> Bool {
        guard isEnabled else { return false }
        return await fetchAndStore()
    }

    private func fetchAndStore() async -> Bool {
        guard isEnabled, let fetched = try? await Self.fetch() else { return false }
        guard isEnabled else { return false }
        rates = fetched
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return true
    }

    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private nonisolated static func fetch() async throws -> CurrencyRates {
        let request = URLRequest(url: endpoint, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Frankfurter v2 answers with one flat row per pair rather than a keyed table.
        let rows = try JSONDecoder().decode([RateRow].self, from: data)
        guard let base = rows.first?.base else { throw URLError(.cannotParseResponse) }
        var rates: [String: Double] = [:]
        rates.reserveCapacity(rows.count + 1)
        for row in rows where row.rate > 0 && row.rate.isFinite && row.base == base {
            rates[row.quote] = row.rate
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        rates[base] = 1

        return CurrencyRates(base: base, rates: rates, fetchedAt: Date())
    }

    private struct RateRow: Decodable {
        let base: String
        let quote: String
        let rate: Double
    }
}
