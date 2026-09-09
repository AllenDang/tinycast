import Darwin
import Foundation

@main
@MainActor
enum LegacyFeatureCleanupTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    nonisolated static var temporaryRoot: URL {
        let path = realpath(FileManager.default.temporaryDirectory.path, nil)!
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }

    final class Fixture {
        let root = temporaryRoot
            .appendingPathComponent("tinycast-retirement-test-" + UUID().uuidString)
        let bundleID = "test.tinycast." + UUID().uuidString
        let defaults: UserDefaults
        var idle = true
        var failTrash = false
        var failMove: String?
        var failRollback = false
        var failPublication = false
        var writeOwnership: ((Data, URL) throws -> Void)?
        var lastSetup: URL?
        var trashed: [[String]] = []
        var support: URL { root.appendingPathComponent("Support").appendingPathComponent(bundleID) }
        var caches: URL { root.appendingPathComponent("Caches").appendingPathComponent(bundleID) }
        var staging: URL { support.appendingPathComponent(".tinycast-retired-quicklinks") }

        init() throws {
            defaults = UserDefaults(suiteName: bundleID)!
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        }

        func finish() throws {
            defaults.removePersistentDomain(forName: bundleID)
            try FileManager.default.removeItem(at: root)
        }

        func file(_ name: String, in directory: URL? = nil) throws {
            try Data(name.utf8).write(to: (directory ?? support).appendingPathComponent(name))
        }

        func runner() throws -> LegacyFeatureCleanupRunner {
            try LegacyFeatureCleanupRunner(
                bundleID: bundleID, supportRoot: root.appendingPathComponent("Support"),
                cachesRoot: root.appendingPathComponent("Caches"), defaults: defaults,
                channelIsIdle: { self.idle },
                trash: { url in
                    if self.failTrash { throw CocoaError(.fileWriteNoPermission) }
                    let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path))
                        ?? [url.lastPathComponent]
                    self.trashed.append(contents)
                    // A fixture-local rename substitutes for Trash; no real Trash API is called.
                    try FileManager.default.moveItem(
                        at: url, to: self.root.appendingPathComponent("fake-trash-" + UUID().uuidString))
                },
                move: { source, destination in
                    if source.lastPathComponent == self.failMove
                        || (self.failPublication && destination.path == self.staging.path)
                        || (self.failRollback && source.deletingLastPathComponent() == self.staging) {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    try FileManager.default.moveItem(at: source, to: destination)
                },
                writeOwnership: { data, url in
                    self.lastSetup = url.deletingLastPathComponent()
                    if let write = self.writeOwnership {
                        try write(data, url)
                    } else {
                        try data.write(to: url, options: .withoutOverwriting)
                    }
                })
        }
    }

    static let databaseNames = [
        "quicklinks.sqlite3", "quicklinks.sqlite3-wal", "quicklinks.sqlite3-shm", "quicklinks.sqlite3-journal"
    ]

    static func seedDatabase(_ fixture: Fixture) throws {
        for name in databaseNames { try fixture.file(name) }
        fixture.defaults.set(true, forKey: "quicklinksEnabled")
    }

    static func expectOriginalsIntact(_ fixture: Fixture) throws {
        for name in databaseNames {
            expect(try Data(contentsOf: fixture.support.appendingPathComponent(name)) == Data(name.utf8),
                   "setup failure preserves original bytes of \(name)")
        }
        expect(fixture.defaults.bool(forKey: "quicklinksEnabled"), "setup failure preserves preferences")
        expect(!FileManager.default.fileExists(atPath: fixture.staging.path),
               "incomplete setup is never published to the fixed staging path")
    }

    static func initializationFailures() throws {
        for failure in ["before-write", "partial-write", "publication", "metadata-trash"] {
            let fixture = try Fixture()
            try seedDatabase(fixture)
            fixture.failPublication = failure == "publication"
            fixture.failTrash = failure == "metadata-trash"
            if failure != "publication" {
                fixture.writeOwnership = { data, url in
                    if failure != "before-write" {
                        try data.prefix(12).write(to: url, options: .withoutOverwriting)
                    }
                    throw CocoaError(.fileWriteOutOfSpace)
                }
            }
            let outcome = try fixture.runner().run()
            expect(outcome.failures.count == 1 && outcome.completed.isEmpty, "\(failure) is reported")
            try expectOriginalsIntact(fixture)
            let setup = fixture.lastSetup!
            if failure == "metadata-trash" {
                expect(outcome.failures[0].contains(setup.path), "failed metadata cleanup names the orphan path")
                expect(FileManager.default.fileExists(atPath: setup.path), "failed metadata Trash retains setup")
                expect(fixture.trashed.isEmpty, "failed metadata Trash reports no successful removal")
            } else {
                expect(!FileManager.default.fileExists(atPath: setup.path), "failed setup metadata is unwound")
                expect(fixture.trashed.count == 1, "only this invocation's setup metadata is trashed")
                expect(Set(fixture.trashed[0]).isSubset(of: ["cleanup-owner.txt"]),
                       "no authored file reaches setup rollback Trash")
            }
            expect(try fixture.runner().hasLegacyData, "setup failure remains discoverable through originals")
            fixture.writeOwnership = nil
            fixture.failPublication = false
            fixture.failTrash = false
            expect(try fixture.runner().run().failures.isEmpty, "\(failure) permits ordinary successful retry")
            expect(!fixture.defaults.bool(forKey: "quicklinksEnabled"), "retry clears preferences only after success")
            expect(Set(fixture.trashed.last ?? []) == Set(databaseNames + ["cleanup-owner.txt"]),
                   "retry trashes the complete database group")
            if failure == "metadata-trash" {
                expect(FileManager.default.fileExists(atPath: setup.path), "retry never claims a prior orphan setup")
            }
            try fixture.finish()
        }
    }

    static func unsafeInitialization() throws {
        for substitution in ["contents", "symlink", "identity"] {
            let fixture = try Fixture()
            try seedDatabase(fixture)
            fixture.writeOwnership = { _, marker in
                let setup = marker.deletingLastPathComponent()
                switch substitution {
                case "contents":
                    try Data("unrelated".utf8).write(to: setup.appendingPathComponent("unrelated.txt"))
                case "symlink":
                    try FileManager.default.createSymbolicLink(
                        at: marker, withDestinationURL: fixture.support.appendingPathComponent("quicklinks.sqlite3"))
                default:
                    try FileManager.default.moveItem(at: setup, to: fixture.root.appendingPathComponent("original-setup"))
                    try FileManager.default.createDirectory(
                        at: setup, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                }
                throw CocoaError(.fileWriteOutOfSpace)
            }
            let outcome = try fixture.runner().run()
            expect(outcome.failures.count == 1, "unsafe setup \(substitution) reported")
            expect(outcome.failures[0].contains(fixture.lastSetup!.path), "unsafe setup path reported for inspection")
            expect(fixture.trashed.isEmpty, "setup \(substitution) substitution refuses Trash")
            try expectOriginalsIntact(fixture)
            try fixture.finish()
        }
        let markerless = try Fixture()
        try seedDatabase(markerless)
        try FileManager.default.createDirectory(
            at: markerless.staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        expect(try markerless.runner().run().failures.count == 1, "preexisting private markerless staging still refused")
        expect(markerless.lastSetup == nil && markerless.trashed.isEmpty, "preexisting markerless folder never claimed")
        expect(markerless.defaults.bool(forKey: "quicklinksEnabled"), "preexisting unsafe folder preserves preferences")
        for name in databaseNames {
            expect(try Data(contentsOf: markerless.support.appendingPathComponent(name)) == Data(name.utf8),
                   "preexisting unsafe folder preserves \(name)")
        }
        try markerless.finish()
    }

    static func main() async throws {
        try initializationFailures()
        try unsafeInitialization()
        let empty = try Fixture()
        expect(try empty.runner().hasLegacyData == false, "fresh channel has no cleanup action")
        try empty.finish()

        let f = try Fixture()
        let neighbor = f.root.appendingPathComponent("Support/another.channel")
        try FileManager.default.createDirectory(at: neighbor, withIntermediateDirectories: true)
        try f.file("quicklinks.sqlite3", in: neighbor)
        try f.file("unrelated.json")
        try f.file("emoji-frequency.json", in: f.caches)
        try FileManager.default.createDirectory(
            at: f.support.appendingPathComponent("Snippets"), withIntermediateDirectories: false)
        try f.file("authored.md", in: f.support.appendingPathComponent("Snippets"))
        for name in ["quicklinks.sqlite3", "quicklinks.sqlite3-wal", "quicklinks.sqlite3-shm",
                     "quicklinks.sqlite3-journal"] { try f.file(name) }
        f.defaults.set(true, forKey: "snippetsEnabled")
        f.defaults.set("old", forKey: "hotkey.toggleEmoji")
        let oldBinding = "hotkey.quicklink." + UUID().uuidString.lowercased()
        f.defaults.set("old", forKey: oldBinding)
        f.defaults.set("keep", forKey: "hotkey.quicklink.not-a-uuid")
        f.defaults.set(true, forKey: "compactMode")
        var approved = false
        var reports = 0
        let coordinator = LegacyFeatureCleanupCoordinator(
            makeRunner: { try f.runner() }, confirm: { approved }, report: { _ in reports += 1 })
        coordinator.refresh()
        expect(coordinator.isAvailable, "legacy data is discoverable")
        await coordinator.cleanUp()
        expect(f.trashed.isEmpty && reports == 0, "cancellation has no effects or report")
        expect(f.defaults.bool(forKey: "snippetsEnabled"), "cancel keeps preferences")
        approved = true
        f.idle = false
        await coordinator.cleanUp()
        expect(f.trashed.isEmpty && coordinator.isAvailable, "other channel process blocks cleanup")
        f.idle = true
        await coordinator.cleanUp()
        expect(!coordinator.isAvailable, "successful cleanup disappears without marker")
        expect(f.trashed.count == 3, "three groups go to fixture Trash")
        expect(f.trashed.last?.count == 5, "DB and three sidecars plus ownership marker grouped")
        expect(f.defaults.object(forKey: oldBinding) == nil, "old per-link binding cleared")
        expect(f.defaults.bool(forKey: "compactMode"), "surviving preferences retained")
        expect(f.defaults.string(forKey: "hotkey.quicklink.not-a-uuid") == "keep", "bounded UUID keys")
        expect(FileManager.default.fileExists(atPath: neighbor.appendingPathComponent("quicklinks.sqlite3").path),
               "another channel untouched")
        expect(FileManager.default.fileExists(atPath: f.support.appendingPathComponent("unrelated.json").path),
               "unrelated file untouched")
        try f.finish()

        let partial = try Fixture()
        try partial.file("quicklinks.sqlite3")
        try partial.file("quicklinks.sqlite3-wal")
        partial.defaults.set(true, forKey: "quicklinksEnabled")
        partial.defaults.set(true, forKey: "emojiSkinTone")
        partial.failMove = "quicklinks.sqlite3-wal"
        var outcome = try partial.runner().run()
        expect(outcome.failures.count == 1 && outcome.completed == ["Emoji"], "per-feature partial result")
        expect(FileManager.default.fileExists(atPath: partial.support.appendingPathComponent("quicklinks.sqlite3").path),
               "move failure rolls DB back")
        expect(partial.defaults.bool(forKey: "quicklinksEnabled"), "failed group keeps preferences")
        partial.failRollback = true
        outcome = try partial.runner().run()
        expect(outcome.failures.first?.contains("remain staged") == true, "rollback failure is reported")
        partial.failRollback = false
        partial.failMove = nil
        partial.failTrash = true
        outcome = try partial.runner().run()
        expect(outcome.failures.count == 1, "Trash failure reported")
        expect(try partial.runner().hasLegacyData, "staging-only failure remains discoverable")
        expect(!FileManager.default.fileExists(atPath: partial.support.appendingPathComponent("quicklinks.sqlite3").path),
               "all DB files safely retained in staging")
        partial.failTrash = false
        outcome = try partial.runner().run()
        expect(outcome.failures.isEmpty && outcome.completed == ["Quicklinks"], "staged-only retry completes")
        expect(partial.defaults.object(forKey: "quicklinksEnabled") == nil, "prefs cleared only after success")
        try partial.finish()

        let sidecar = try Fixture()
        try sidecar.file("quicklinks.sqlite3-shm")
        expect(try sidecar.runner().hasLegacyData, "orphan sidecar is discoverable")
        expect(try sidecar.runner().run().failures.isEmpty, "sidecar-only cleanup works")
        try sidecar.finish()

        let unsafe = try Fixture()
        let sentinel = unsafe.root.appendingPathComponent("sentinel")
        try Data("untouched".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: unsafe.support.appendingPathComponent("quicklinks.sqlite3"), withDestinationURL: sentinel)
        expect(try unsafe.runner().run().failures.count == 1, "target symlink refused")
        expect(try Data(contentsOf: sentinel) == Data("untouched".utf8), "symlink destination untouched")
        try unsafe.finish()

        let ancestor = try Fixture()
        try FileManager.default.moveItem(at: ancestor.support, to: ancestor.root.appendingPathComponent("elsewhere"))
        try FileManager.default.createSymbolicLink(
            at: ancestor.support, withDestinationURL: ancestor.root.appendingPathComponent("elsewhere"))
        ancestor.defaults.set(true, forKey: "snippetsEnabled")
        expect(try ancestor.runner().run().failures.contains { $0.hasPrefix("Snippets:") },
               "symlink ancestor refused even for prefs-only cleanup")
        expect(ancestor.defaults.bool(forKey: "snippetsEnabled"), "unsafe ancestor keeps defaults")
        try ancestor.finish()

        let foreign = try Fixture()
        try FileManager.default.createDirectory(at: foreign.staging, withIntermediateDirectories: false)
        try foreign.file("unrelated", in: foreign.staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: foreign.staging.path)
        expect(try foreign.runner().run().failures.count == 1, "preexisting foreign staging refused")
        expect(foreign.trashed.isEmpty, "unrecognized staging never trashed")
        try foreign.finish()

        let staged = try Fixture()
        try staged.file("quicklinks.sqlite3")
        staged.failTrash = true
        expect(try staged.runner().run().failures.count == 1, "create owned retry staging")
        staged.failTrash = false
        try staged.file("unexpected.txt", in: staged.staging)
        expect(try staged.runner().run().failures.first?.contains("Unrecognized staging contents") == true,
               "valid ownership marker cannot authorize unexpected staged content")
        expect(staged.trashed.isEmpty, "unexpected staged contents remain untouched")
        try FileManager.default.moveItem(at: staged.staging.appendingPathComponent("unexpected.txt"),
                                        to: staged.root.appendingPathComponent("preserved-unexpected.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.staging.path)
        expect(try staged.runner().run().failures.first?.contains("ownership or permissions") == true,
               "nonprivate staged directory refused despite valid marker")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.staging.path)
        let stagedDB = staged.staging.appendingPathComponent("quicklinks.sqlite3")
        let preservedDB = staged.root.appendingPathComponent("preserved-database")
        try FileManager.default.moveItem(at: stagedDB, to: preservedDB)
        try FileManager.default.createSymbolicLink(at: stagedDB, withDestinationURL: preservedDB)
        expect(try staged.runner().run().failures.first?.contains("symbolic link") == true,
               "symlink inside an otherwise valid staged group is refused")
        try FileManager.default.removeItem(at: stagedDB)
        try FileManager.default.moveItem(at: preservedDB, to: stagedDB)
        try staged.file("quicklinks.sqlite3")
        expect(try staged.runner().run().failures.first?.contains("neither was overwritten") == true,
               "original and staged collisions preserve both files")
        expect(staged.trashed.isEmpty, "all unsafe staging cases avoid Trash")
        try FileManager.default.moveItem(at: staged.support.appendingPathComponent("quicklinks.sqlite3"),
                                        to: staged.root.appendingPathComponent("preserved-collision"))
        expect(try staged.runner().run().failures.isEmpty, "revalidated staging retries after fixture repair")
        try staged.finish()

        let late = try Fixture()
        late.defaults.set(true, forKey: "snippetsEnabled")
        let lateCoordinator = LegacyFeatureCleanupCoordinator(
            makeRunner: { try late.runner() },
            confirm: {
                try! FileManager.default.createSymbolicLink(
                    at: late.support.appendingPathComponent("Snippets"), withDestinationURL: late.caches)
                return true
            }, report: { expect(!$0.failures.isEmpty, "fresh validation after confirmation") })
        await lateCoordinator.cleanUp()
        expect(late.trashed.isEmpty, "confirmation-time replacement not followed")
        try late.finish()

        do {
            _ = try LegacyFeatureCleanupRunner(
                bundleID: "../other", supportRoot: URL(fileURLWithPath: "/unused"),
                cachesRoot: URL(fileURLWithPath: "/unused"), defaults: .standard,
                channelIsIdle: { true }, trash: { _ in fatalError("must never run") })
            preconditionFailure("path traversal bundle ID accepted")
        } catch { checks += 1 }
        print("\(checks) legacy cleanup checks passed; no real Trash or app data accessed")
    }
}
