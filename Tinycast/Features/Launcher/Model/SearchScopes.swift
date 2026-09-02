import Foundation

enum SearchScopes {
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        "/System/Library/CoreServices/Finder.app",
        "~/Applications"
    ]

    static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    /// Abbreviates every path and drops duplicates, preserving order.
    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Every `.app` the scopes point at. One subfolder deep; deeper nesting needs its own scope.
    static func appBundles(in scopes: [String]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(url) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        return result
    }

    /// `.app` is a leaf here — never descended into, only real subfolders recurse.
    private static func appBundles(under url: URL, subfolderDepth: Int) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        for item in items {
            if item.pathExtension == "app" {
                result.append(item)
            } else if subfolderDepth > 0,
                (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            {
                result.append(contentsOf: appBundles(under: item, subfolderDepth: subfolderDepth - 1))
            }
        }
        return result
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
