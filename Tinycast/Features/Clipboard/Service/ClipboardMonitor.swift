import AppKit

@MainActor
final class ClipboardMonitor {
    /// Marker we attach to the pasteboard when *we* write to it, so polling ignores our own pastes.
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")

    static let maxTextLength = 32_000

    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var sessionTokens: [NotificationToken] = []
    private var lastChangeCount = 0

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        installSessionObservers()
        startPolling()
    }

    // Fast user switching: another session's clipboard isn't ours, so stop waking up for it.
    private func installSessionObservers() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopPolling() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.startPolling() }
                }, center: center)
        ]
    }

    // Re-baselining first is what stops a clip made in another session reading as new on resume.
    private func startPolling() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func prepareForTinycastPasteboardMutation() {
        poll()
    }

    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {
        guard NSPasteboard.general.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if pb.types?.contains(Self.internalType) == true { return }

        if let types = pb.types, !Set(types).isDisjoint(with: Self.sensitiveTypes) { return }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }

        if let text = pb.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.count <= Self.maxTextLength else { return }
            store.addText(text, sourceBundleID: sourceBundleID)
            return
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            let isPNG = type == .png
            let store = store
            Task.detached(priority: .utility) {
                let png =
                    isPNG
                    ? data
                    : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                guard let png else { return }
                await store.addImage(png, sourceBundleID: sourceBundleID)
            }
        }
    }
}
