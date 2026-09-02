import Foundation

enum AdministratorTrashPolicy {
    static func allows(path: String, home: String) -> Bool {
        let path = (path as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        guard path.hasPrefix("/"), path != "/", path != home else { return false }

        if (path as NSString).pathExtension.lowercased() == "app",
            isDirectChild(path, of: "/Applications")
        {
            return true
        }

        for root in UninstallSearchRoot.all where root.base == .systemLibrary {
            let rootPath = root.path(home: home)
            guard UninstallRulesPath.isDescendant(path, of: rootPath) else { continue }
            let relative = path.dropFirst(rootPath.count + 1)
            let depth = relative.split(separator: "/", omittingEmptySubsequences: true).count
            if depth > 0, depth <= root.maxDepth { return true }
        }

        return isDirectChild(path, of: "/usr/local/bin")
    }

    private static func isDirectChild(_ path: String, of parent: String) -> Bool {
        (path as NSString).deletingLastPathComponent == (parent as NSString).standardizingPath
    }
}

private enum UninstallRulesPath {
    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor + "/")
    }
}
