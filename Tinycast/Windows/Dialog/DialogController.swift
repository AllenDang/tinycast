import AppKit
import SwiftUI

@MainActor
final class DialogController: NSObject, NSWindowDelegate {
    private var panel: DialogPanel?
    private var continuation: CheckedContinuation<Int, Never>?
    private var currentCancelIndex: Int?
    private var currentRequestID: UUID?

    func confirm(
        title: String, message: String?, symbol: String, tone: DialogTone, confirmTitle: String,
        confirmRole: DialogAction.Role
    ) async -> Bool {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone,
            actions: [
                DialogAction(title: confirmTitle, role: confirmRole),
                DialogAction(title: "Cancel", role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1)
        return await present(request) == 0
    }

    func notice(title: String, message: String, symbol: String, tone: DialogTone) async {
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: tone,
            actions: [DialogAction(title: "OK", role: .cancel)], defaultIndex: 0, cancelIndex: 0)
        _ = await present(request)
    }

    func reportFailure(title: String, message: String, symbol: String, recovery: String?) async
        -> Bool {
        var actions = [DialogAction(title: "OK", role: .cancel)]
        if let recovery { actions.append(DialogAction(title: recovery)) }
        // ↵ lands on the recovery action when there is one to take, not on the OK dismissal.
        let recoveryIndex = recovery == nil ? nil : actions.count - 1
        let request = DialogRequest(
            title: title, message: message, symbol: symbol, tone: .danger,
            actions: actions, defaultIndex: recoveryIndex ?? 0, cancelIndex: 0)
        return await present(request) == recoveryIndex
    }

    func pickVolume(current: Float32) async -> Float32? {
        let volume = VolumeState(level: Double(current))
        let request = DialogRequest(
            title: "Set Volume", message: "Choose the output volume.", symbol: "speaker.wave.2",
            tone: .neutral,
            actions: [
                DialogAction(title: "Set Volume"),
                DialogAction(title: "Cancel", role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, volume: volume)
        guard await present(request) == 0 else { return nil }
        return Float32(volume.level)
    }

    func promptFields(
        id: UUID, title: String, fields: [DialogField]
    ) async -> [String: String]? {
        guard !fields.isEmpty else { return [:] }
        let state = DialogFieldState(fields: fields)
        let request = DialogRequest(
            title: title, message: "Fill in the template fields:", symbol: "curlybraces",
            tone: .neutral,
            actions: [
                DialogAction(title: "Expand"),
                DialogAction(title: "Cancel", role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, fields: state)
        guard await present(request, id: id) == 0 else { return nil }
        return state.collected
    }

    func cancel(id: UUID) {
        guard currentRequestID == id, let currentCancelIndex else { return }
        finish(currentCancelIndex)
    }

    private func present(_ request: DialogRequest, id: UUID = UUID()) async -> Int {
        guard continuation == nil else { return request.cancelIndex }
        if request.fields != nil { NSApp.activate(ignoringOtherApps: true) }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            currentCancelIndex = request.cancelIndex
            currentRequestID = id
            let content = hostingView(
                DialogView(request: request, onChoose: { [weak self] index in self?.finish(index) }),
                width: Theme.Size.dialogWidth, minHeight: 0)
            let panel = DialogPanel(content: content)
            panel.delegate = self
            panel.onKey = { [weak self] key in
                guard let self else { return false }
                switch key {
                case .cancel:
                    finish(request.cancelIndex)
                    return true
                case .confirm:
                    finish(request.defaultIndex)
                    return true
                case .increment, .decrement:
                    guard let volume = request.volume else { return false }
                    volume.level = VolumeLevel.stepped(volume.level, up: key == .increment)
                    return true
                }
            }
            self.panel = panel
            place(panel)
            panel.fadeIn(duration: Theme.Duration.enter) {
                panel.makeKeyAndOrderFront(nil)
                panel.orderFrontRegardless()
            }
        }
    }

    private func finish(_ index: Int) {
        guard let continuation else { return }
        self.continuation = nil
        currentCancelIndex = nil
        currentRequestID = nil
        let closing = panel
        panel = nil
        closing?.delegate = nil
        closing?.onKey = nil
        continuation.resume(returning: index)
        closing?.fadeOut(duration: Theme.Duration.exit)
    }

    private func hostingView(_ view: some View, width: CGFloat, minHeight: CGFloat) -> NSView {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.setFrameSize(NSSize(width: width, height: minHeight))
        let fitted = hosting.fittingSize
        hosting.setFrameSize(NSSize(width: width, height: max(fitted.height, minHeight)))
        return hosting
    }

    private func place(_ panel: NSPanel) {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    private static let centerLift: CGFloat = 0.08

    // MARK: - NSWindowDelegate

    /// Click-away resolves as a dismissal rather than leaving an orphaned dialog behind.
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        _ = panel.onKey?(.cancel)
    }
}
