import AppKit

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case text, image }

    let id: UUID
    let kind: Kind
    let text: String?
    let imageFileName: String?
    let createdAt: Date

    init(text: String) {
        id = UUID()
        kind = .text
        self.text = text
        imageFileName = nil
        createdAt = Date()
    }

    init(imageFileName: String) {
        id = UUID()
        kind = .image
        text = nil
        self.imageFileName = imageFileName
        createdAt = Date()
    }
}

/// File-backed clipboard history: small JSON index + image blobs on disk.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    var maxItems: Int = 500

    private let imagesDir: URL
    private let indexURL: URL
    /// The in-flight (or scheduled) disk write. Replaced on each change so a burst of copies
    /// collapses into a single write instead of re-encoding the whole history every time.
    private var writeTask: Task<Void, Never>?

    init() {
        // Stored under ~/Library/Caches/<bundle-id>, the same convention Raycast uses — clipboard
        // history is regenerable, and the in-app "Clear History" button is the durable control.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        indexURL = base.appendingPathComponent("clipboard.json")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        items = decoded
    }

    func addText(_ text: String) {
        if items.first?.kind == .text, items.first?.text == text { return }
        insert(ClipboardItem(text: text))
    }

    func addImage(_ data: Data) {
        let name = UUID().uuidString + ".png"
        let url = imagesDir.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        insert(ClipboardItem(imageFileName: name))
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
        persist(debounced: false)
    }

    func clearAll() {
        items.forEach(deleteBlob)
        items = []
        persist(debounced: false)
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func search(_ query: String) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { ($0.text?.localizedCaseInsensitiveContains(q)) ?? false }
    }

    // MARK: - Private

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        prune()
        persist(debounced: true)
    }

    private func prune() {
        guard items.count > maxItems else { return }
        items[maxItems...].forEach(deleteBlob)
        items = Array(items.prefix(maxItems))
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let name = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
    }

    /// Snapshot the history and write it off the main actor. `debounced` coalesces rapid copies
    /// into one write; the immediate path (remove/clear) still goes through the same single-flight
    /// task so writes never overlap.
    private func persist(debounced: Bool) {
        writeTask?.cancel()
        let snapshot = items
        let url = indexURL
        writeTask = Task {
            if debounced {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await Self.write(snapshot, to: url)
        }
    }

    /// `nonisolated async` so the encode + atomic write run on the cooperative pool, never on main.
    nonisolated private static func write(_ items: [ClipboardItem], to url: URL) async {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
