import AppKit

@MainActor
final class VolumeHUDController {
    private let presenter = HUDPresenter(
        anchor: .heightFraction(bottomFraction), dwell: Theme.Duration.volumeHUD,
        screen: { .underCursor })
    private let state = VolumeState(level: 0)

    func show(level: Float32, muted: Bool) {
        let showing = presenter.isShowing
        state.level = VolumeLevel.clamped(Double(level))
        state.muted = muted
        if showing {
            presenter.extend()
        } else {
            presenter.show(
                VolumeHUDView(state: state),
                size: CGSize(width: Theme.Size.hudWidth, height: Theme.Size.hudHeight))
        }
    }

    private static let bottomFraction: CGFloat = 0.12
}
