import Foundation

struct UninstallFailedItem: Hashable, Sendable {
    let name: String
    let reason: String
}

struct UninstallReport: Sendable {
    let trashed: [UninstallCandidate]
    let failed: [UninstallFailedItem]

    var trashedCount: Int { trashed.count }
    var freedBytes: Int64 { trashed.reduce(0) { $0 + ($1.size?.bytes ?? 0) } }
    var hasFailures: Bool { !failed.isEmpty }
    /// Gates the reference cleanup: a leftovers-only run leaves the app installed.
    var removedBundle: Bool { trashed.contains { $0.evidence == .bundle } }
}

enum UninstallRunner {
    static func moveToTrash(_ candidates: [UninstallCandidate]) async -> UninstallReport {
        let removable = candidates.filter { !$0.isLocked }
        let leftovers = removable.filter { $0.evidence != .bundle }
        let bundles = removable.filter { $0.evidence == .bundle }

        return await Task.detached(priority: .userInitiated) {
            var trashed: [UninstallCandidate] = []
            var failed: [UninstallFailedItem] = []
            var administrator: [UninstallCandidate] = []

            for candidate in leftovers {
                attempt(candidate, trashed: &trashed, failed: &failed, administrator: &administrator)
            }
            administrator.append(contentsOf: bundles.filter(\.requiresAdministrator))
            applyAdministratorResults(
                await AdministratorTrashRunner.moveToTrash(administrator), candidates: administrator,
                trashed: &trashed, failed: &failed)

            for candidate in bundles where !candidate.requiresAdministrator {
                attempt(candidate, trashed: &trashed, failed: &failed, administrator: &administrator)
            }
            return UninstallReport(trashed: trashed, failed: failed)
        }.value
    }

    private static func attempt(
        _ candidate: UninstallCandidate, trashed: inout [UninstallCandidate],
        failed: inout [UninstallFailedItem], administrator: inout [UninstallCandidate]
    ) {
        if candidate.requiresAdministrator {
            administrator.append(candidate)
            return
        }
        do {
            try FileManager.default.trashItem(at: candidate.url, resultingItemURL: nil)
            trashed.append(candidate)
        } catch {
            failed.append(UninstallFailedItem(name: candidate.name, reason: error.localizedDescription))
        }
    }

    private static func applyAdministratorResults(
        _ outcomes: [AdministratorTrashOutcome], candidates: [UninstallCandidate],
        trashed: inout [UninstallCandidate], failed: inout [UninstallFailedItem]
    ) {
        let byPath = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.path, $0) })
        for candidate in candidates {
            guard let outcome = byPath[candidate.path] else {
                failed.append(
                    UninstallFailedItem(
                        name: candidate.name, reason: "The administrator helper returned no result."))
                continue
            }
            if let error = outcome.error {
                failed.append(UninstallFailedItem(name: candidate.name, reason: error))
            } else {
                trashed.append(candidate)
            }
        }
    }
}
