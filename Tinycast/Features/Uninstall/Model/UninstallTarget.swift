import Foundation

/// What an uninstall is aimed at. Pure, for `Tools/uninstall-test.swift`.
struct UninstallTarget: Hashable, Sendable {
    let bundleURL: URL
    let bundleID: String?
    let displayName: String
    /// Some apps name their support folder after `CFBundleName` rather than the display name.
    let bundleName: String?
    let relatedBundleIDs: Set<String>
    let applicationGroupIDs: Set<String>
    let executableName: String?

    init(
        bundleURL: URL, bundleID: String?, displayName: String, bundleName: String?,
        relatedBundleIDs: Set<String> = [], applicationGroupIDs: Set<String> = [],
        executableName: String? = nil
    ) {
        self.bundleURL = bundleURL
        self.bundleID = bundleID
        self.displayName = displayName
        self.bundleName = bundleName
        self.relatedBundleIDs = relatedBundleIDs
        self.applicationGroupIDs = applicationGroupIDs
        self.executableName = executableName
    }
}

/// How a candidate was attributed to the target.
enum UninstallEvidence: String, Hashable, Sendable, CaseIterable {
    case bundle
    case bundleID
    case groupContainer
    case applicationGroup
    case displayName
    case executableArtifact
    case binSymlink

    /// Weak evidence names itself on the row; proof-grade matches stay silent.
    var label: String? {
        switch self {
        case .displayName: return "matched by name"
        case .executableArtifact: return "diagnostic report"
        case .binSymlink: return "command-line tool"
        case .bundle, .bundleID, .groupContainer, .applicationGroup: return nil
        }
    }
}

struct UninstallIdentity: Hashable, Sendable {
    /// Case-folded bundle ID, or nil when the target has none.
    let bundleID: String?
    let allowsBundleIDPrefixMatch: Bool
    let relatedBundleIDs: Set<String>
    let applicationGroupIDs: Set<String>
    let otherApplicationGroupIDs: Set<String>
    let otherBundleIDs: Set<String>
    /// Case-folded names safe enough to claim a whole directory.
    let names: [String]
    let executableName: String?
    let bundleURL: URL

    static let minimumNameLength = 3

    /// Standard Library subdirectories, so an app sharing the name can never claim them.
    static let reservedNames: Set<String> = [
        "apple", "application support", "application scripts", "autosave information", "caches",
        "containers", "cookies", "crashreporter", "fonts", "frameworks", "group containers",
        "httpstorages", "keychains", "launchagents", "launchdaemons", "logs", "metadata",
        "mobilesync", "preferences", "privilegedhelpertools", "scripts", "services", "sync",
        "syncservices", "webkit"
    ]

    static func make(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String] = [],
        otherApplicationGroupIDs: [String] = [], otherExecutableNames: [String] = [],
        ownBundleID: String?, ownBundleURL: URL
    ) -> UninstallIdentity? {
        if let ownBundleID, let bundleID = target.bundleID,
            folded(bundleID) == folded(ownBundleID)
        {
            return nil
        }
        if target.bundleURL.standardizedFileURL == ownBundleURL.standardizedFileURL { return nil }

        let bundleID = target.bundleID.map(folded).flatMap { $0.isEmpty ? nil : $0 }
        let names = safeNames(
            displayName: target.displayName, bundleName: target.bundleName,
            otherAppNames: otherAppNames)
        guard bundleID != nil || !target.relatedBundleIDs.isEmpty
            || !target.applicationGroupIDs.isEmpty || !names.isEmpty
        else { return nil }

        let relatedBundleIDs = Set(target.relatedBundleIDs.map(folded)).filter { !$0.isEmpty }
        let takenExecutables = Set(otherExecutableNames.map(folded))
        let executableName = target.executableName.map(folded).flatMap {
            $0.isEmpty || takenExecutables.contains($0) ? nil : $0
        }
        return UninstallIdentity(
            bundleID: bundleID,
            allowsBundleIDPrefixMatch: (bundleID?.split(separator: ".").count ?? 0) >= 3,
            relatedBundleIDs: relatedBundleIDs.subtracting([bundleID].compactMap { $0 }),
            applicationGroupIDs: Set(target.applicationGroupIDs.map(folded)).filter { !$0.isEmpty },
            otherApplicationGroupIDs: Set(otherApplicationGroupIDs.map(folded)),
            otherBundleIDs: Set(otherBundleIDs.map(folded)),
            names: names,
            executableName: executableName,
            bundleURL: target.bundleURL.standardizedFileURL)
    }

    static func safeNames(
        displayName: String, bundleName: String?, otherAppNames: [String]
    ) -> [String] {
        let taken = Set(otherAppNames.map(folded))
        var result: [String] = []
        for candidate in [displayName, bundleName].compactMap({ $0 }) {
            let name = folded(candidate)
            guard name.count >= minimumNameLength, !reservedNames.contains(name),
                !taken.contains(name), !result.contains(name)
            else { continue }
            result.append(name)
        }
        return result
    }

    static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
