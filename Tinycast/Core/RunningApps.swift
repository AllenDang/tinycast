import AppKit

/// Tracks which apps are currently running so the launcher can show a running indicator.
/// Updates live from NSWorkspace launch/terminate notifications.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    @Published private(set) var runningBundleIDs: Set<String> = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func refresh() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
