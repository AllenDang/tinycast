import Foundation

enum OnboardingState {
    private static let markerURL = AppPaths.applicationSupport()
        .appendingPathComponent("onboarded")

    /// True once onboarding has been shown.
    static var hasOnboarded: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    static func markShown() {
        try? Data().write(to: markerURL)
    }
}
