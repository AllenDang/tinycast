import Darwin
import Foundation

private func outcome(path: String, error: String? = nil) -> AdministratorTrashOutcome {
    AdministratorTrashOutcome(path: path, error: error)
}

private func invokingUser(_ value: String) -> (uid: uid_t, home: String)? {
    guard let parsed = UInt32(value), let password = getpwuid(uid_t(parsed)) else { return nil }
    return (uid_t(parsed), String(cString: password.pointee.pw_dir))
}

private func prepareIdentity(_ user: (uid: uid_t, home: String)) -> Bool {
    guard geteuid() == 0 || geteuid() == user.uid else { return false }
    setenv("HOME", user.home, 1)
    if let password = getpwuid(user.uid) {
        setenv("USER", password.pointee.pw_name, 1)
        setenv("LOGNAME", password.pointee.pw_name, 1)
    }
    return geteuid() == user.uid || setreuid(user.uid, 0) == 0
}

private func containsSymlinkAncestor(_ path: String) -> Bool {
    var ancestor = (path as NSString).deletingLastPathComponent
    while ancestor != "/" {
        var info = stat()
        guard lstat(ancestor, &info) == 0 else { return true }
        if (info.st_mode & S_IFMT) == S_IFLNK { return true }
        ancestor = (ancestor as NSString).deletingLastPathComponent
    }
    return false
}

let arguments = CommandLine.arguments
let results: [AdministratorTrashOutcome]
if arguments.count < 3 || arguments[1] != "trash" {
    results = [outcome(path: "", error: "Invalid administrator trash request.")]
} else if let user = invokingUser(arguments[2]), prepareIdentity(user) {
    results = arguments.dropFirst(3).map { rawPath in
        let path = (rawPath as NSString).standardizingPath
        guard AdministratorTrashPolicy.allows(path: path, home: user.home),
            !containsSymlinkAncestor(path)
        else {
            return outcome(path: rawPath, error: "Tinycast refused this path.")
        }
        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return outcome(path: rawPath)
        } catch {
            return outcome(path: rawPath, error: error.localizedDescription)
        }
    }
} else {
    results = arguments.dropFirst(3).map {
        outcome(path: $0, error: "Couldn’t assume administrator privileges.")
    }
}

let data = try JSONEncoder().encode(results)
FileHandle.standardOutput.write(data)
