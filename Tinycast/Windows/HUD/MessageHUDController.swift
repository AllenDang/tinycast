import AppKit

@MainActor
final class MessageHUDController {
    private let presenter: HUDPresenter

    init(settings: AppSettings) {
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset),
            dwell: Theme.Duration.messageHUD,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    func show(message: String, tone: DialogTone = .success) {
        presenter.show(MessageHUDView(message: message, tone: tone))
    }
}
