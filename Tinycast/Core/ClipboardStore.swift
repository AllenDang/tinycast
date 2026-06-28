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

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tinycast", isDirectory: true)
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
        persist()
    }

    func clearAll() {
        items.forEach(deleteBlob)
        items = []
        persist()
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func search(_ query: String) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { item in
            if let text = item.text { return text.localizedCaseInsensitiveContains(q) }
            return "image".contains(q.lowercased())
        }
    }

    // MARK: - Private

    private func insert(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        prune()
        persist()
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
