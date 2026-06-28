import AppKit

@MainActor
final class ClipboardManager {
    /// Marker we attach to the pasteboard when *we* write to it, so polling ignores our own pastes.
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")

    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount = 0

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if pb.types?.contains(Self.internalType) == true { return }

        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addText(text)
            return
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            if type == .png {
                store.addImage(data)
            } else if let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                store.addImage(png)
            }
        }
    }
}
