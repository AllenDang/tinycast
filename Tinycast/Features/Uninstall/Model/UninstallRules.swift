import Foundation

enum UninstallRules {
    /// Stripped before matching, so `com.foo.Bar.plist` compares as `com.foo.Bar`.
    static let strippedExtensions: Set<String> = [
        "plist", "savedstate", "binarycookies", "lockfile", "lock", "sfl", "sfl2", "sfl3",
        // Plug-in wrappers, named after the product that installed them.
        "qlgenerator", "saver", "prefpane", "service", "workflow", "mdimporter", "appex",
        "component", "wdgt", "dext", "driver", "plugin", "bundle", "mailbundle",
        "colorpicker", "scriptingaddition", "vst", "vst3"
    ]

    static func matchableForms(_ name: String) -> [String] {
        var forms = [name]
        var current = name
        for _ in 0..<3 {
            let ext = (current as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, strippedExtensions.contains(ext) else { break }
            let stripped = (current as NSString).deletingPathExtension
            guard !stripped.isEmpty else { break }
            forms.append(stripped)
            current = stripped
        }
        return forms
    }

    private static let namespaceSeparators: Set<Character> = [".", "-"]

    /// The bundle ID itself, or a namespaced child of it.
    static func matchesBundleID(_ component: String, identity: UninstallIdentity) -> Bool {
        let ids = [identity.bundleID].compactMap { $0 } + identity.relatedBundleIDs.sorted()
        guard !ids.isEmpty else { return false }
        return matchableForms(component).contains { form in
            let folded = UninstallIdentity.folded(form)
            let owners = ids.filter { id in
                let allowingPrefix =
                    id == identity.bundleID
                    ? identity.allowsBundleIDPrefixMatch : id.split(separator: ".").count >= 3
                return owns(folded, id: id, allowingPrefix: allowingPrefix)
            }
            guard let owner = owners.max(by: { $0.count < $1.count }) else { return false }
            return !identity.otherBundleIDs.contains { other in
                other.count >= owner.count && owns(folded, id: other, allowingPrefix: true)
            }
        }
    }

    private static func owns(_ folded: String, id: String, allowingPrefix: Bool) -> Bool {
        if folded == id { return true }
        guard allowingPrefix, folded.count > id.count, folded.hasPrefix(id) else { return false }
        return namespaceSeparators.contains(folded[folded.index(folded.startIndex, offsetBy: id.count)])
    }

    /// Attribution by link target, never by name — the name is whatever the vendor chose.
    static func isBundleSymlink(target: String, bundlePath: String) -> Bool {
        let target = (target as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        return target == bundlePath || isDescendant(target, of: bundlePath)
    }

    static func groupContainerBase(_ component: String) -> String {
        var base = component
        for _ in 0..<2 {
            if base.lowercased().hasPrefix("group.") {
                base = String(base.dropFirst("group.".count))
                continue
            }
            guard let dot = base.firstIndex(of: "."), isTeamID(String(base[base.startIndex..<dot]))
            else { break }
            base = String(base[base.index(after: dot)...])
        }
        return base
    }

    static func isTeamID(_ value: String) -> Bool {
        value.count == 10
            && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) && !$0.isLowercase }
    }

    static func matchesGroupContainer(_ component: String, identity: UninstallIdentity) -> Bool {
        matchesBundleID(groupContainerBase(component), identity: identity)
    }

    static func matchesApplicationGroup(_ component: String, identity: UninstallIdentity) -> Bool {
        let group = UninstallIdentity.folded(component)
        return identity.applicationGroupIDs.contains(group)
            && !identity.otherApplicationGroupIDs.contains(group)
    }

    static func matchesExecutableArtifact(_ component: String, identity: UninstallIdentity) -> Bool {
        guard let executable = identity.executableName, executable.count >= 3 else { return false }
        let name = UninstallIdentity.folded(component)
        let ext = (name as NSString).pathExtension
        guard ["ips", "crash", "hang", "diag"].contains(ext) else { return false }
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix(executable), stem.count > executable.count else { return false }
        let boundary = stem[stem.index(stem.startIndex, offsetBy: executable.count)]
        return boundary == "-" || boundary == "_"
    }

    static func matchesDisplayName(_ component: String, identity: UninstallIdentity) -> Bool {
        guard !identity.names.isEmpty else { return false }
        return matchableForms(component).contains { form in
            identity.names.contains(UninstallIdentity.folded(form))
        }
    }

    static func evidence(
        for name: String, in root: UninstallSearchRoot, identity: UninstallIdentity
    ) -> UninstallEvidence? {
        if root.styles.contains(.bundleID), matchesBundleID(name, identity: identity) {
            return .bundleID
        }
        if root.styles.contains(.groupContainer), matchesGroupContainer(name, identity: identity) {
            return .groupContainer
        }
        if root.styles.contains(.applicationGroup),
            matchesApplicationGroup(name, identity: identity)
        {
            return .applicationGroup
        }
        if root.styles.contains(.executableArtifact),
            matchesExecutableArtifact(name, identity: identity)
        {
            return .executableArtifact
        }
        if root.styles.contains(.displayName), matchesDisplayName(name, identity: identity) {
            return .displayName
        }
        return nil
    }

    /// Belt and braces on every produced path, whatever matched it.
    static func isAcceptableCandidate(
        path: String, rootPath: String, home: String, bundlePath: String, maxDepth: Int = 1
    ) -> Bool {
        let path = (path as NSString).standardizingPath
        let rootPath = (rootPath as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        guard path.hasPrefix("/"), path != "/", path != home, path != rootPath else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..")
        else { return false }
        guard isDescendant(path, of: rootPath) else { return false }
        let relative = String(path.dropFirst(rootPath.count + 1))
        let depth = relative.split(separator: "/", omittingEmptySubsequences: true).count
        guard depth > 0, depth <= maxDepth else { return false }
        guard path != bundlePath, !isDescendant(path, of: bundlePath),
            !isDescendant(bundlePath, of: path)
        else { return false }
        return true
    }

    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor + "/")
    }

    /// Takes `home` rather than reading it, so it stays pure.
    static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        guard isDescendant(path, of: home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
