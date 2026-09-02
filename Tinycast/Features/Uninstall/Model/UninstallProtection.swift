import Foundation

struct PathFacts: Hashable, Sendable {
    let path: String
    var exists = true
    /// Never followed: sizing through one could walk the whole disk.
    var isSymbolicLink = false
    var volumeIsReadOnly = false
    /// `SF_RESTRICTED` / `SF_IMMUTABLE` — SIP.
    var isSystemRestricted = false
    /// `UF_IMMUTABLE` — Finder's "Locked" checkbox, which the user can clear themselves.
    var isUserImmutable = false
    /// Only decides anything under a sticky parent — see `classify`.
    var isOwnedByCurrentUser = true
    var parentIsWritable = true
    var parentIsSticky = false
}

/// Process-wide facts, probed once per scan rather than once per candidate.
struct UninstallEnvironment: Hashable, Sendable {
    let home: String
    let hasFullDiskAccess: Bool
}

enum UninstallProtection: String, Hashable, Sendable, CaseIterable {
    case removable
    case systemProtected
    case userLocked
    case notOwned
    case needsFullDiskAccess
    case parentNotWritable
    case missing

    var isRemovable: Bool { self == .removable }

    /// Nil for exactly `.removable`; the row's lock icon keys off it.
    var lockReason: String? {
        switch self {
        case .removable:
            return nil
        case .systemProtected:
            return "Part of macOS and protected by the system."
        case .userLocked:
            return "Locked in Finder. Unlock it in Get Info, then try again."
        case .notOwned:
            return "Owned by another user, in a folder that only lets owners remove things."
        case .needsFullDiskAccess:
            return "Needs Full Disk Access, which Tinycast doesn’t request. "
                + "Grant it in System Settings › Privacy & Security to include this item."
        case .parentNotWritable:
            return "Its enclosing folder isn’t writable by you, and Tinycast never asks for an "
                + "administrator password."
        case .missing:
            return "No longer on disk."
        }
    }
}

enum UninstallProtectionRules {
    static func classify(_ facts: PathFacts, environment: UninstallEnvironment) -> UninstallProtection
    {
        guard facts.exists else { return .missing }
        if facts.isSystemRestricted || facts.volumeIsReadOnly { return .systemProtected }
        if facts.isUserImmutable { return .userLocked }
        if !environment.hasFullDiskAccess,
            isTCCProtected(path: facts.path, home: environment.home)
        {
            return .needsFullDiskAccess
        }
        if !facts.parentIsWritable { return .parentNotWritable }
        // The one case where ownership does decide: a sticky parent lets only an owner unlink.
        if facts.parentIsSticky, !facts.isOwnedByCurrentUser { return .notOwned }
        return .removable
    }

    static func isTCCProtected(path: String, home: String) -> Bool {
        let relative = tccRelativePrefixes.contains { path.hasPrefix(home + "/" + $0) }
        return relative || path.hasPrefix("/Library/Application Support/com.apple.TCC")
    }

    static let tccRelativePrefixes: [String] = [
        "Library/Containers/",
        "Library/Group Containers/",
        "Library/Cookies/",
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Calendars",
        "Library/Suggestions",
        "Library/HomeKit",
        "Library/IdentityServices",
        "Library/Sharing",
        "Library/Biome",
        "Library/Trial",
        "Library/Metadata/CoreSpotlight",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/MobileSync"
    ]
}
