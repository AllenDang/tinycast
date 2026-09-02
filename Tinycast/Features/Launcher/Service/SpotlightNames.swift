import CoreServices
import Foundation

enum SpotlightNames {
    private static let attribute = "kMDItemAlternateNames"

    nonisolated static func alternateNames(for url: URL, displayName: String) -> [String] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
            let raw = MDItemCopyAttribute(item, attribute as CFString) as? [String]
        else { return [] }
        return SearchFields.usableAlternateNames(
            raw, displayName: displayName, fileName: url.lastPathComponent)
    }

    struct Cache: Sendable {
        private struct Entry: Sendable {
            let modified: Date?
            let names: [String]
        }

        private let previous: [String: Entry]
        private var current: [String: Entry] = [:]

        init() { previous = [:] }

        init(reusing cache: Cache) { previous = cache.current }

        mutating func alternateNames(for url: URL, displayName: String) -> [String] {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let cached = previous[url.path], cached.modified == modified {
                current[url.path] = cached
                return cached.names
            }
            let names = SpotlightNames.alternateNames(for: url, displayName: displayName)
            current[url.path] = Entry(modified: modified, names: names)
            return names
        }
    }
}
