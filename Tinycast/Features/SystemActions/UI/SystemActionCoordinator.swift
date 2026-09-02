import AppKit

@MainActor
final class SystemActionCoordinator {
    private let palette: PaletteCoordinator
    private let volumeHUD: VolumeHUDController
    private let presentation: PresentationActions

    init(
        palette: PaletteCoordinator, volumeHUD: VolumeHUDController,
        presentation: PresentationActions
    ) {
        self.palette = palette
        self.volumeHUD = volumeHUD
        self.presentation = presentation
    }

    func runSystemAction(id: SystemAction.ID) {
        let target = palette.targetApplication
        if palette.isVisible { palette.hidePalette(restoreFocus: false) }
        Task { await perform(SystemActionCatalog.action(id: id), previousApp: target) }
    }

    private func perform(_ action: SystemAction, previousApp: NSRunningApplication?) async {
        switch action.confirmation {
        case .computed:
            await quitAllApps()
            return
        case .required(let title, let message):
            guard
                await presentation.confirm(
                    title, message, action.sfSymbol, action.name, .danger, .destructive)
            else { return }
        case .none:
            break
        }
        do {
            var feedback: SystemActionFeedback?
            if action.id == .setVolume {
                let current = try SystemActionRunner.currentVolume()
                guard let selected = await presentation.pickVolume(current) else { return }
                try SystemActionRunner.setVolume(selected)
            } else {
                feedback = try await SystemActionRunner.run(action.id, previousApp: previousApp)
            }
            if Self.showsVolumeFeedback.contains(action.id) {
                let state = try SystemActionRunner.outputState()
                volumeHUD.show(level: state.level, muted: state.muted)
            } else if let feedback {
                presentation.showMessage(
                    feedback.title, feedback.isNoOp ? .neutral : .success)
            }
        } catch let failure as SystemActionFailure {
            await presentFailure(action: action, failure: failure)
        } catch {
            await presentFailure(
                action: action, failure: SystemActionFailure(error.localizedDescription))
        }
    }

    private static let showsVolumeFeedback: Set<SystemAction.ID> = [
        .setVolume, .volumeUp, .volumeDown, .toggleMute,
        .volume0, .volume25, .volume50, .volume75, .volume100
    ]

    func presentSystemActionFailure(id: SystemAction.ID, failure: SystemActionFailure) {
        Task { await presentFailure(action: SystemActionCatalog.action(id: id), failure: failure) }
    }

    private func presentFailure(action: SystemAction, failure: SystemActionFailure) async {
        guard
            await presentation.reportFailure(
                "“\(action.name)” Failed", failure.message, action.sfSymbol,
                failure.settings == nil ? nil : "Open System Settings…"),
            let settings = failure.settings
        else { return }
        let pane: String
        switch settings {
        case .accessibility: pane = "Privacy_Accessibility"
        case .automation: pane = "Privacy_Automation"
        case .bluetooth: pane = "Privacy_Bluetooth"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func quitAllApps() async {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty,
            await presentation.confirm(
                targets.count == 1
                    ? "Quit 1 application?" : "Quit \(targets.count) applications?",
                "Applications with unsaved changes will ask you to save.",
                SystemActionCatalog.action(id: .quitAllApps).sfSymbol, "Quit All", .danger,
                .destructive)
        else { return }
        for app in targets { app.terminate() }
    }
}
