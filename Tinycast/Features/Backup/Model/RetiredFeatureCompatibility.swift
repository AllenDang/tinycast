import Foundation

/// Bounded legacy identification for backup imports/exports, never live launcher classification.
enum RetiredFeatureCompatibility {
    static func keepsItem(_ key: String) -> Bool {
        !key.hasPrefix("snippet:") && !key.hasPrefix("quicklink:")
            && !commands.contains(key)
    }

    static func keepsKind(_ kind: String) -> Bool {
        kind != "snippet" && kind != "quicklink"
    }

    private static let commands: Set<String> = [
        "command:search-emoji", "command:create-quicklink", "command:search-quicklinks",
        "command:import-quicklinks", "command:export-quicklinks"
    ]
}
