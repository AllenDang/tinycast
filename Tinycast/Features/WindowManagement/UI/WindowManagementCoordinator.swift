import AppKit

@MainActor
final class WindowManagementCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let mover: WindowMover
    private let palette: PaletteCoordinator

    init(
        settings: AppSettings,
        appIndex: AppIndex,
        mover: WindowMover,
        palette: PaletteCoordinator
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.mover = mover
        self.palette = palette
    }

    func applyPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    func run(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        let target = palette.targetApplication
        if palette.isVisible { palette.hidePalette(restoreFocus: true) }
        mover.perform(
            id, target: target, gap: CGFloat(settings.windowGap),
            cycleOnRepeat: settings.windowCycleOnRepeat)
    }
}
