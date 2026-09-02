import CryptoKit
import Darwin
import Foundation
import Security

struct AdministratorTrashRunner {
    private static let script = """
        on run argv
            set sourcePath to item 1 of argv
            set expectedDigest to item 2 of argv
            set commandText to "temporary=$(/usr/bin/mktemp -d /private/tmp/tinycast-trash.XXXXXX) && /bin/cp "
            set commandText to commandText & quoted form of sourcePath & " $temporary/helper"
            set commandText to commandText & " && actual=$(/usr/bin/shasum -a 256 $temporary/helper | /usr/bin/awk '{print $1}')"
            set commandText to commandText & " && test $actual = " & quoted form of expectedDigest
            set commandText to commandText & " && /bin/chmod 700 $temporary/helper && $temporary/helper"
            repeat with argumentIndex from 3 to count of argv
                set commandText to commandText & " " & quoted form of item argumentIndex of argv
            end repeat
            set commandText to commandText & "; status=$?; /bin/rm -rf $temporary; exit $status"
            return do shell script commandText with administrator privileges
        end run
        """

    static func moveToTrash(_ candidates: [UninstallCandidate]) async
        -> [AdministratorTrashOutcome]
    {
        guard !candidates.isEmpty else { return [] }
        guard let helper = Bundle.main.path(forAuxiliaryExecutable: "TinycastTrashHelper") else {
            return failures(candidates, reason: "The administrator trash helper is missing.")
        }
        guard let digest = helperDigest(at: helper), bundleSignatureIsValid() else {
            return failures(candidates, reason: "Tinycast’s code signature is invalid.")
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments =
            ["-e", script, helper, digest, "trash", String(getuid())] + candidates.map(\.path)
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return failures(candidates, reason: error.localizedDescription)
        }

        let outputTask = Task.detached {
            output.fileHandleForReading.readDataToEndOfFile()
        }
        let errorTask = Task.detached {
            errors.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        let data = await outputTask.value
        let errorData = await errorTask.value
        if process.terminationStatus == 0,
            let outcomes = try? JSONDecoder().decode([AdministratorTrashOutcome].self, from: data)
        {
            return outcomes
        }

        let detail = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = detail.isEmpty
            ? "Administrator authorization was canceled or denied." : detail
        return failures(candidates, reason: reason)
    }

    private static func helperDigest(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func bundleSignatureIsValid() -> Bool {
        var runningCode: SecCode?
        var runningStaticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &runningCode) == errSecSuccess, let runningCode,
            SecCodeCopyStaticCode(runningCode, [], &runningStaticCode) == errSecSuccess,
            let runningStaticCode,
            SecCodeCopyDesignatedRequirement(runningStaticCode, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }

        var code: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
            let code
        else { return false }
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func failures(
        _ candidates: [UninstallCandidate], reason: String
    ) -> [AdministratorTrashOutcome] {
        candidates.map { AdministratorTrashOutcome(path: $0.path, error: reason) }
    }
}
