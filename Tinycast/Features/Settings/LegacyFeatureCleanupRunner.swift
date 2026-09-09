import Darwin
import Foundation

struct LegacyFeatureCleanupRunner {
    enum Feature: String, CaseIterable {
        case emoji = "Emoji"
        case snippets = "Snippets"
        case quicklinks = "Quicklinks"

        var defaultsKeys: Set<String> {
            switch self {
            case .emoji: return ["emojiSkinTone", "hotkey.toggleEmoji"]
            case .snippets: return ["snippetsEnabled", "snippetsShowInLauncher"]
            case .quicklinks:
                return [
                    "quicklinksEnabled", "quicklinksShowInLauncher", "quicklinkOpensNewWindow",
                    "quicklinkSelectionFallback", "quicklinkConfirmsBeforeDelete", "boundQuicklinkIDs"
                ]
            }
        }
    }

    struct Outcome {
        var completed: [String] = []
        var failures: [String] = []
    }

    private static let databaseNames = [
        "quicklinks.sqlite3", "quicklinks.sqlite3-wal", "quicklinks.sqlite3-shm",
        "quicklinks.sqlite3-journal"
    ]
    private static let stagingName = ".tinycast-retired-quicklinks"
    private static let ownershipName = "cleanup-owner.txt"
    private let bundleID: String
    private let support: URL
    private let caches: URL
    private let defaults: UserDefaults
    private let trash: (URL) throws -> Void
    private let move: (URL, URL) throws -> Void
    private let channelIsIdle: () -> Bool
    private let writeOwnership: (Data, URL) throws -> Void

    init(
        bundleID: String, supportRoot: URL, cachesRoot: URL, defaults: UserDefaults,
        channelIsIdle: @escaping () -> Bool,
        trash: @escaping (URL) throws -> Void,
        move: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        writeOwnership: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .withoutOverwriting)
        }
    ) throws {
        guard !bundleID.isEmpty, bundleID != ".", bundleID != "..",
            bundleID.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || $0 == 45 || $0 == 46
            })
        else { throw CleanupError("Invalid running bundle identifier.") }
        self.bundleID = bundleID
        support = supportRoot.appendingPathComponent(bundleID, isDirectory: true)
        caches = cachesRoot.appendingPathComponent(bundleID, isDirectory: true)
        self.defaults = defaults
        self.channelIsIdle = channelIsIdle
        self.trash = trash
        self.move = move
        self.writeOwnership = writeOwnership
    }

    var hasLegacyData: Bool {
        Feature.allCases.contains { feature in
            !keys(for: feature).isEmpty || paths(for: feature).contains { path in
                // An unsafe or unreadable path still needs a discoverable failure/retry action.
                (try? exists(path)) != false
            }
        }
    }

    func run() -> Outcome {
        var outcome = Outcome()
        for feature in Feature.allCases {
            do {
                let keys = keys(for: feature)
                let paths = paths(for: feature)
                guard try !keys.isEmpty || paths.contains(where: exists) else { continue }
                try requireIdle()
                for path in paths { try validate(path) }
                if feature == .quicklinks {
                    try trashDatabaseGroup()
                } else {
                    for path in paths where try exists(path) {
                        try requireIdle()
                        try validate(path)
                        try trash(path)
                        guard try !exists(path) else {
                            throw CleanupError("Trash did not move \(path.lastPathComponent).")
                        }
                    }
                }
                for path in paths {
                    guard try !exists(path) else {
                        throw CleanupError("Legacy files reappeared; preferences were retained for retry.")
                    }
                }
                for key in keys { defaults.removeObject(forKey: key) }
                outcome.completed.append(feature.rawValue)
            } catch {
                outcome.failures.append("\(feature.rawValue): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    private func keys(for feature: Feature) -> Set<String> {
        let domain = defaults.persistentDomain(forName: bundleID) ?? [:]
        var keys = feature.defaultsKeys.intersection(domain.keys)
        if feature == .quicklinks {
            for key in domain.keys where key.hasPrefix("hotkey.quicklink.") {
                let suffix = String(key.dropFirst("hotkey.quicklink.".count))
                if UUID(uuidString: suffix) != nil { keys.insert(key) }
            }
        }
        return keys
    }

    private func paths(for feature: Feature) -> [URL] {
        switch feature {
        case .emoji: return [caches.appendingPathComponent("emoji-frequency.json")]
        case .snippets: return [support.appendingPathComponent("Snippets", isDirectory: true)]
        case .quicklinks:
            return Self.databaseNames.map { support.appendingPathComponent($0) }
                + [support.appendingPathComponent(Self.stagingName, isDirectory: true)]
        }
    }

    private func trashDatabaseGroup() throws {
        let staging = support.appendingPathComponent(Self.stagingName, isDirectory: true)
        let sources = Self.databaseNames.map { support.appendingPathComponent($0) }
        guard try exists(staging) || sources.contains(where: exists) else { return }
        if try !exists(staging) { try initializeStaging(staging) }
        try validateStaging(staging)
        for source in sources where try exists(source) {
            guard try !exists(staging.appendingPathComponent(source.lastPathComponent)) else {
                throw CleanupError("Both original and staged \(source.lastPathComponent) exist; neither was overwritten.")
            }
        }
        var moved: [URL] = []
        do {
            for source in sources where try exists(source) {
                try requireIdle()
                try validate(source)
                try validateStaging(staging)
                try move(source, staging.appendingPathComponent(source.lastPathComponent))
                moved.append(source)
            }
        } catch {
            var rollbackFailures: [String] = []
            for source in moved.reversed() {
                do {
                    try validate(source)
                    try validateStaging(staging)
                    guard try !exists(source) else { throw CleanupError("Original path exists.") }
                    try move(staging.appendingPathComponent(source.lastPathComponent), source)
                } catch { rollbackFailures.append(source.lastPathComponent) }
            }
            let detail = rollbackFailures.isEmpty ? "Original files restored; retry is safe."
                : "Some files remain staged: \(rollbackFailures.joined(separator: ", ")). Retry to finish grouping."
            throw CleanupError("\(error.localizedDescription) \(detail)")
        }
        try requireIdle()
        try validateStaging(staging)
        for source in sources {
            guard try !exists(source) else {
                throw CleanupError("Legacy database files reappeared. Quit other copies and retry.")
            }
        }
        try trash(staging)
        guard try !exists(staging) else { throw CleanupError("Staged files were not moved to Trash.") }
    }

    private func initializeStaging(_ staging: URL) throws {
        let setup = support.appendingPathComponent(Self.stagingName + "-setup-" + UUID().uuidString)
        try validate(setup, directory: true)
        guard mkdir(setup.path, 0o700) == 0 else {
            throw CleanupError("Cannot create private cleanup setup folder: \(String(cString: strerror(errno)))")
        }
        var identity = stat()
        guard lstat(setup.path, &identity) == 0 else {
            throw CleanupError("Cannot verify setup folder at \(setup.path). Originals are untouched; retry is safe.")
        }
        do {
            try validateSetup(setup, identity: identity)
            try writeOwnership(ownershipData, setup.appendingPathComponent(Self.ownershipName))
            try validateSetup(setup, identity: identity)
            try validateStaging(setup)
            try requireIdle()
            try validate(staging)
            guard try !exists(staging) else {
                throw CleanupError("Staging appeared during setup; it was not overwritten.")
            }
            try move(setup, staging)
        } catch {
            let failure = error.localizedDescription
            do {
                try validateSetup(setup, identity: identity)
                try trash(setup)
                guard try !exists(setup) else { throw CleanupError("Setup folder was not moved to Trash.") }
            } catch {
                throw CleanupError(
                    "\(failure) Setup metadata could not be cleaned up at \(setup.path): "
                        + "\(error.localizedDescription) Originals and preferences are untouched; retry is safe.")
            }
            throw CleanupError("\(failure) Setup metadata moved to Trash. Originals and preferences are untouched; retry is safe.")
        }
    }

    private func validateSetup(_ setup: URL, identity: stat) throws {
        try validate(setup, directory: true)
        var current = stat()
        guard lstat(setup.path, &current) == 0,
            current.st_dev == identity.st_dev, current.st_ino == identity.st_ino,
            current.st_uid == getuid(), current.st_mode & 0o7777 == 0o700
        else { throw CleanupError("Setup folder identity or ownership changed; nothing was trashed.") }
        let children = try FileManager.default.contentsOfDirectory(atPath: setup.path)
        guard Set(children).isSubset(of: [Self.ownershipName]) else {
            throw CleanupError("Unexpected setup contents; nothing was trashed.")
        }
        let marker = setup.appendingPathComponent(Self.ownershipName)
        if try exists(marker) {
            try validate(marker)
            var info = stat()
            guard lstat(marker.path, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
                info.st_size <= ownershipData.count
            else { throw CleanupError("Unexpected setup metadata; nothing was trashed.") }
        }
    }

    private var ownershipData: Data {
        Data("Tinycast retired Quicklinks cleanup v1\n\(bundleID)\n".utf8)
    }

    private func validateStaging(_ staging: URL) throws {
        try validate(staging, directory: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: staging.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else { throw CleanupError("Unrecognized staging folder ownership or permissions.") }
        let children = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        let allowed = Set(Self.databaseNames + [Self.ownershipName])
        guard children.contains(Self.ownershipName), Set(children).isSubset(of: allowed) else {
            throw CleanupError("Unrecognized staging contents; nothing was trashed.")
        }
        for child in children { try validate(staging.appendingPathComponent(child)) }
        let marker = staging.appendingPathComponent(Self.ownershipName)
        let markerAttributes = try FileManager.default.attributesOfItem(atPath: marker.path)
        guard (markerAttributes[.size] as? NSNumber)?.intValue == ownershipData.count,
            try Data(contentsOf: marker) == ownershipData
        else { throw CleanupError("Unrecognized staging marker; nothing was trashed.") }
    }

    private func requireIdle() throws {
        guard channelIsIdle() else {
            throw CleanupError("Quit every other copy of this Tinycast channel and retry.")
        }
    }

    private func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw CleanupError("Cannot inspect \(url.path): \(String(cString: strerror(errno)))")
    }

    private func validate(_ url: URL, directory expectsDirectory: Bool = false) throws {
        let components = url.pathComponents
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            if lstat(current.path, &info) != 0 {
                if errno == ENOENT { return }
                throw CleanupError("Cannot inspect \(current.path).")
            }
            let type = info.st_mode & S_IFMT
            let directory = current.path != url.path || expectsDirectory
                || ["Snippets", Self.stagingName].contains(component)
            guard type == (directory ? S_IFDIR : S_IFREG) else {
                throw CleanupError("Unsafe file type or symbolic link at \(current.path); nothing followed it.")
            }
        }
    }

    private struct CleanupError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
