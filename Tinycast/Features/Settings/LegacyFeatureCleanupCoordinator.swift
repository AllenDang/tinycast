import Foundation

@MainActor
@Observable
final class LegacyFeatureCleanupCoordinator {
    private(set) var isAvailable = false
    private(set) var isRunning = false
    private let makeRunner: () throws -> LegacyFeatureCleanupRunner
    private let confirm: () async -> Bool
    private let report: (LegacyFeatureCleanupRunner.Outcome) async -> Void

    init(
        makeRunner: @escaping () throws -> LegacyFeatureCleanupRunner,
        confirm: @escaping () async -> Bool,
        report: @escaping (LegacyFeatureCleanupRunner.Outcome) async -> Void
    ) {
        self.makeRunner = makeRunner
        self.confirm = confirm
        self.report = report
    }

    func refresh() {
        isAvailable = (try? makeRunner().hasLegacyData) ?? true
    }

    func cleanUp() async {
        guard !isRunning else { return }
        isRunning = true
        defer {
            isRunning = false
            refresh()
        }
        guard await confirm() else { return }
        let outcome: LegacyFeatureCleanupRunner.Outcome
        do {
            outcome = try makeRunner().run()
        } catch {
            outcome = .init(failures: [error.localizedDescription])
        }
        await report(outcome)
    }
}
