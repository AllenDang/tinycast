import AppKit
// `kAXTrustedCheckOptionPrompt` is imported as a mutable C global; the AX module predates
// Sendable annotations, so downgrade its concurrency diagnostics (the value is process-constant).
@preconcurrency import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Returns current trust state and prompts the user to grant it if needed.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @MainActor
    static func openAccessibilitySettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
