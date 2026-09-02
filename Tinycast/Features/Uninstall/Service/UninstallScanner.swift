import Darwin
import Foundation
import Security

enum UninstallScanner {
    struct SizeBudget: Sendable {
        var maxEntries = 250_000
        static let `default` = SizeBudget()
    }

    enum Failure: LocalizedError, Sendable {
        case refused

        var errorDescription: String? {
            switch self {
            case .refused:
                return "Tinycast can't uninstall this app."
            }
        }
    }

    /// Every candidate with directory sizes still nil; fast enough that the list can paint on it.
    nonisolated static func discover(
        target: UninstallTarget, otherAppNames: [String], otherBundleIDs: [String],
        otherAppURLs: [URL] = [], isTargetRunning: Bool, roots: [UninstallSearchRoot] = UninstallSearchRoot.all
    ) async throws -> UninstallPlan {
        try await Signposts.interval("UninstallScanner.discover") {
            let home = NSHomeDirectory()
            let target = enrichedTarget(target)
            let otherMetadata = otherAppURLs.map(installedMetadata)
            let environment = UninstallEnvironment(
                home: home, hasFullDiskAccess: detectFullDiskAccess(home: home))
            guard
                let identity = UninstallIdentity.make(
                    target: target, otherAppNames: otherAppNames,
                    otherBundleIDs: otherBundleIDs + otherMetadata.flatMap(\.bundleIDs),
                    otherApplicationGroupIDs: otherMetadata.flatMap(\.applicationGroupIDs),
                    otherExecutableNames: otherMetadata.compactMap(\.executableName),
                    ownBundleID: Bundle.main.bundleIdentifier, ownBundleURL: Bundle.main.bundleURL)
            else { throw Failure.refused }

            let bundlePath = target.bundleURL.standardizedFileURL.path
            let bundle = row(
                path: bundlePath, evidence: .bundle, environment: environment,
                displayName: target.bundleURL.deletingPathExtension().lastPathComponent)

            var buckets = [[UninstallCandidate]](repeating: [], count: roots.count)
            try await withThrowingTaskGroup(of: (Int, [UninstallCandidate]).self) { group in
                for (index, root) in roots.enumerated() {
                    group.addTask {
                        try Task.checkCancellation()
                        return (
                            index,
                            rows(
                                in: root, identity: identity, environment: environment,
                                bundlePath: bundlePath)
                        )
                    }
                }
                // At its own index, so `UninstallSearchRoot.all` order outlives completion order.
                for try await (index, found) in group { buckets[index] = found }
            }

            let gathered =
                [bundle].compactMap { $0 } + buckets.flatMap { $0 }
                + (try binRows(environment: environment, bundlePath: bundlePath))

            // One pass, in gathered order: a `Set` shared across tasks is what would race.
            var seen = Set<String>()
            let candidates = gathered.filter { seen.insert($0.path).inserted }

            // Bundle pinned first; the rest by path, which is the order the list shows.
            let leftovers = candidates.filter { $0.evidence != .bundle }.sorted { $0.path < $1.path }
            return UninstallPlan(
                target: target, candidates: candidates.filter { $0.evidence == .bundle } + leftovers,
                isTargetRunning: isTargetRunning)
        }
    }

    /// Streams each walk as it lands, so a row never waits on its neighbours; nil means unmeasured.
    nonisolated static func measure(
        paths: [String], budget: SizeBudget = .default,
        onMeasured: @escaping @Sendable @MainActor (String, MeasuredSize) -> Void
    ) async {
        await Signposts.interval("UninstallScanner.measure") {
            await withTaskGroup(of: (String, MeasuredSize)?.self) { group in
                for path in paths {
                    group.addTask {
                        guard let size = try? directorySize(of: path, budget: budget) else {
                            return nil
                        }
                        return (path, size)
                    }
                }
                // A cancelled or unreadable walk yields nothing, so its row stays pending.
                for await measured in group {
                    guard let (path, size) = measured else { continue }
                    await onMeasured(path, size)
                }
            }
        }
    }

    // MARK: - Private

    private struct InstalledMetadata {
        let bundleIDs: Set<String>
        let applicationGroupIDs: Set<String>
        let executableName: String?
    }

    private static func installedMetadata(_ url: URL) -> InstalledMetadata {
        let bundle = Bundle(url: url)
        let nested = nestedBundleURLs(in: url)
        let componentURLs = [url] + nested
        return InstalledMetadata(
            bundleIDs: Set(componentURLs.compactMap { Bundle(url: $0)?.bundleIdentifier }),
            applicationGroupIDs: Set(
                componentURLs.flatMap { signingApplicationGroups(at: $0) }),
            executableName: bundle?.infoDictionary?["CFBundleExecutable"] as? String)
    }

    private static func enrichedTarget(_ target: UninstallTarget) -> UninstallTarget {
        let bundle = Bundle(url: target.bundleURL)
        let info = bundle?.infoDictionary
        let nested = nestedBundleURLs(in: target.bundleURL)
        var relatedBundleIDs = target.relatedBundleIDs
        if let helpers = info?["SMPrivilegedExecutables"] as? [String: Any] {
            relatedBundleIDs.formUnion(helpers.keys)
        }
        relatedBundleIDs.formUnion(nested.compactMap { Bundle(url: $0)?.bundleIdentifier })

        var applicationGroupIDs = target.applicationGroupIDs
        applicationGroupIDs.formUnion(signingApplicationGroups(at: target.bundleURL))
        for url in nested {
            applicationGroupIDs.formUnion(signingApplicationGroups(at: url))
        }
        return UninstallTarget(
            bundleURL: target.bundleURL, bundleID: target.bundleID,
            displayName: target.displayName, bundleName: target.bundleName,
            relatedBundleIDs: relatedBundleIDs, applicationGroupIDs: applicationGroupIDs,
            executableName: target.executableName ?? info?["CFBundleExecutable"] as? String)
    }

    private static func nestedBundleURLs(in bundleURL: URL) -> [URL] {
        let relativeRoots = [
            "Contents/PlugIns", "Contents/XPCServices", "Contents/Library/LoginItems",
            "Contents/Library/Services"
        ]
        let bundleExtensions: Set<String> = ["app", "appex", "xpc", "service", "qlgenerator"]
        var result: [URL] = []
        for relativeRoot in relativeRoots {
            let root = bundleURL.appendingPathComponent(relativeRoot)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            else { continue }
            for case let url as URL in enumerator {
                let relative = url.path.dropFirst(root.path.count)
                if relative.split(separator: "/").count > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard bundleExtensions.contains(url.pathExtension.lowercased()) else { continue }
                result.append(url)
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private static func signingApplicationGroups(at url: URL) -> Set<String> {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return [] }
        var signingInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &signingInfo) == errSecSuccess,
            let info = signingInfo as? [String: Any],
            let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
            let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return Set(groups)
    }

    private static func rows(
        in root: UninstallSearchRoot, identity: UninstallIdentity,
        environment: UninstallEnvironment, bundlePath: String
    ) -> [UninstallCandidate] {
        let rootPath = root.path(home: environment.home)
        guard let names = childNames(of: rootPath) else { return [] }
        let rootParent = parentFacts(of: rootPath)

        func candidate(
            name: String, path: String, parent: ParentFacts
        ) -> UninstallCandidate? {
            guard let evidence = UninstallRules.evidence(for: name, in: root, identity: identity),
                UninstallRules.isAcceptableCandidate(
                    path: path, rootPath: rootPath, home: environment.home,
                    bundlePath: bundlePath, maxDepth: root.maxDepth)
            else { return nil }
            return row(path: path, evidence: evidence, environment: environment, parent: parent)
        }

        var found: [UninstallCandidate] = []
        for name in names {
            let path = (rootPath + "/" + name as NSString).standardizingPath
            if let matched = candidate(name: name, path: path, parent: rootParent) {
                found.append(matched)
                continue
            }
            guard root.maxDepth > 1, isRealDirectory(path), let nested = childNames(of: path)
            else { continue }
            let nestedParent = parentFacts(of: path)
            for child in nested {
                let childPath = (path + "/" + child as NSString).standardizingPath
                if let matched = candidate(name: child, path: childPath, parent: nestedParent) {
                    found.append(matched)
                }
            }
        }
        return found
    }

    /// Serial: four directories of cheap symlink reads, and nothing here needs a walk.
    private static func binRows(environment: UninstallEnvironment, bundlePath: String) throws
        -> [UninstallCandidate]
    {
        var rows: [UninstallCandidate] = []
        for directory in UninstallSearchRoot.binDirectories {
            try Task.checkCancellation()
            let rootPath = (directory as NSString).expandingTildeInPath
            guard let names = childNames(of: rootPath) else { continue }
            let parent = parentFacts(of: rootPath)
            for name in names {
                let path = (rootPath + "/" + name as NSString).standardizingPath
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
                else { continue }
                // A relative link resolves against its own directory, not the cwd.
                let resolved =
                    target.hasPrefix("/")
                    ? target : (rootPath as NSString).appendingPathComponent(target)
                guard UninstallRules.isBundleSymlink(target: resolved, bundlePath: bundlePath),
                    let row = row(
                        path: path, evidence: .binSymlink, environment: environment, parent: parent)
                else { continue }
                rows.append(row)
            }
        }
        return rows
    }

    private static func isRealDirectory(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private static func childNames(of directory: String) -> [String]? {
        // Not `.skipsHiddenFiles`: dot-named leftovers are the ones a user would never find.
        try? FileManager.default.contentsOfDirectory(atPath: directory)
    }

    private static func row(
        path: String, evidence: UninstallEvidence, environment: UninstallEnvironment,
        displayName: String? = nil, parent: ParentFacts? = nil
    ) -> UninstallCandidate? {
        guard let scanned = inspect(path, parent: parent, home: environment.home) else { return nil }
        let protection = UninstallProtectionRules.classify(scanned.facts, environment: environment)
        guard protection != .missing else { return nil }
        // A symlink is trashed as the link, so it never costs more than its own bytes.
        let walkable = scanned.isDirectory && !scanned.facts.isSymbolicLink
        return UninstallCandidate(
            path: path,
            name: displayName ?? (path as NSString).lastPathComponent,
            locationLabel: UninstallRules.abbreviate(
                (path as NSString).deletingLastPathComponent, home: environment.home),
            evidence: evidence,
            isDirectory: scanned.isDirectory,
            size: walkable ? nil : MeasuredSize(bytes: scanned.byteSize),
            protection: protection)
    }

    /// `lstat`, never `stat`: a symlink is judged as the link, not as whatever it points at.
    private static func inspect(_ path: String, parent: ParentFacts?, home: String)
        -> (facts: PathFacts, isDirectory: Bool, byteSize: Int64)?
    {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let parent = parent ?? parentFacts(of: (path as NSString).deletingLastPathComponent)
        let volumeIsReadOnly =
            (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey]))?
            .volumeIsReadOnly ?? false
        let facts = PathFacts(
            path: path,
            isSymbolicLink: (info.st_mode & S_IFMT) == S_IFLNK,
            volumeIsReadOnly: volumeIsReadOnly,
            isSystemRestricted: info.st_flags & UInt32(SF_RESTRICTED | SF_IMMUTABLE) != 0,
            isUserImmutable: info.st_flags & UInt32(UF_IMMUTABLE) != 0,
            isOwnedByCurrentUser: info.st_uid == geteuid(),
            parentIsWritable: parent.isWritable,
            parentIsSticky: parent.isSticky,
            parentRequiresAdministrator: parent.requiresAdministrator,
            allowsAdministrator: AdministratorTrashPolicy.allows(path: path, home: home))
        // `st_size`, not `st_blocks`: a 593-byte plist occupies a block and must not read as 4 kB.
        return (facts, (info.st_mode & S_IFMT) == S_IFDIR, Int64(info.st_size))
    }

    /// The permission that actually governs a trash, resolved once per root.
    private static func parentFacts(of directory: String) -> ParentFacts {
        var info = stat()
        let found = stat(directory, &info) == 0
        return ParentFacts(
            isWritable: FileManager.default.isWritableFile(atPath: directory),
            isSticky: found && (info.st_mode & S_ISVTX) != 0,
            requiresAdministrator: found && info.st_flags & UInt32(SF_NOUNLINK) != 0)
    }

    private struct ParentFacts {
        let isWritable: Bool
        let isSticky: Bool
        let requiresAdministrator: Bool
    }

    /// Logical bytes, like Finder; an unreadable subtree is skipped, not abandoned.
    private static func directorySize(of path: String, budget: SizeBudget) throws -> MeasuredSize {
        let url = URL(fileURLWithPath: path)
        // Not the allocated keys: Xcode ships decmpfs-compressed, and blocks read 4.19 GB of 9.45.
        let keys: [URLResourceKey] = [.totalFileSizeKey, .fileSizeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in true })
        else { return .zero }

        // Hoisted: the loop runs up to `maxEntries` times, and this allocated a `Set` on each one.
        let keySet = Set(keys)
        var size = MeasuredSize()
        var entries = 0
        for case let item as URL in enumerator {
            // The long pole: cancellation has to land inside the walk, not just between walks.
            try Task.checkCancellation()
            entries += 1
            if entries > budget.maxEntries {
                size.isLowerBound = true
                break
            }
            let values = try? item.resourceValues(forKeys: keySet)
            size.bytes += Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
        }
        return size
    }

    private static func detectFullDiskAccess(home: String) -> Bool {
        let descriptor = open(home + "/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
