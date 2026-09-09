import CommonCrypto
import CryptoKit
import Foundation

@main
@MainActor
enum BackupCompatibilityTests {
    static var checks = 0
    static func expect(_ value: Bool, _ message: String) {
        checks += 1
        precondition(value, message)
    }

    static func gzip(_ data: Data) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-n", "-c"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(data)
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        return result
    }

    static func v1File(_ json: Data) throws -> Data {
        let plaintext = try gzip(json)
        let key = Data(SHA256.hash(data: Data("fixture".utf8)))
        let iv = Data(repeating: 0x23, count: 16)
        var output = Data(count: plaintext.count + 16)
        let capacity = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            plaintext.withUnsafeBytes { input in
                iv.withUnsafeBytes { iv in
                    key.withUnsafeBytes { key in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count,
                                iv.baseAddress, input.baseAddress, input.count,
                                out.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        precondition(status == kCCSuccess)
        return iv + output.prefix(moved)
    }

    static func v2File(_ json: Data) throws -> Data {
        let salt = Data(repeating: 0x42, count: 16)
        let key = Scrypt.derive(passphrase: Array("fixture".utf8), salt: Array(salt),
                                n: 16384, r: 8, p: 1, dkLen: 32)
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0x34, count: 12))
        let box = try AES.GCM.seal(gzip(json), using: SymmetricKey(data: key), nonce: nonce)
        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        let envelope: [String: Any] = [
            "data": hex(box.ciphertext),
            "encryption": ["iv": hex(Data(nonce)), "salt": hex(salt), "authTag": hex(box.tag)]
        ]
        return try gzip(JSONSerialization.data(withJSONObject: envelope))
    }

    static func main() throws {
        let legacy = Data("""
            {"version":4,"settings":{"compactMode":true,"popToRootSeconds":30,
              "emojiSkinTone":{"invalid":true},"snippetsEnabled":true,
              "snippetsShowInLauncher":[],"quicklinksEnabled":"bad",
              "quicklinkSelectionFallback":{"obsolete":true}},
             "quicklinks":{"malformed":"ignored"},
             "hotkeys":{"togglePalette":{"doubleTap":{"_0":"command"}},
                        "toggleEmoji":{"obsolete":true},"quicklinks":"malformed"}}
            """.utf8)
        let backup = try SettingsBackup(json: legacy)
        expect(backup.settings?.compactMode == true, "retired fields do not poison native settings")
        expect(backup.settings?.popToRootSeconds == 30, "surviving enum value retained")
        expect(backup.hotkeys?.togglePalette == .doubleTap(.command), "surviving hotkey retained")
        let encoded = String(decoding: try backup.encoded(), as: UTF8.self)
        expect(!encoded.contains("quicklink") && !encoded.contains("Emoji") && !encoded.contains("snippet"),
               "new envelope never emits removed keys")
        let items = ["snippet:/old", "quicklink:old", "command:search-emoji",
                     "command:search-quicklinks", "command:clipboard-history", "com.example.app"]
        expect(items.filter(RetiredFeatureCompatibility.keepsItem)
               == ["command:clipboard-history", "com.example.app"], "bounded retired launcher IDs ignored")
        expect(["snippet", "quicklink", "application", "windowCommand"].filter(RetiredFeatureCompatibility.keepsKind)
               == ["application", "windowCommand"], "retired categories cannot shift surviving categories")
        expect(!RaycastImportOptions.all.contains(.init(rawValue: 1 << 2))
               && !RaycastImportOptions.all.contains(.init(rawValue: 1 << 8)), "retired option bits unused")
        expect(RaycastImportOptions.clipboardHistory.rawValue == 1 << 5, "surviving option bits stable")

        let v1 = Data("""
            {"raycast_version":"1.104.0",
             "builtin_package_raycastPreferences":{
               "preferencesAdvanced":{"popToRootTimeout":30,"emojiSkinTone":{"retired":true}},
               "preferencesAppearance":{"statusBarIsVisible":false,"raycastPreferredWindowMode":"compact"}},
             "builtin_package_snippets":{"snippets":42},
             "builtin_package_rootSearch":{"rootSearch":[
               {"key":"builtin_command_clipboardHistory","type":"command","hotkey":"Command-49"},
               {"key":"builtin_command_emojiSymbols","type":"command","hotkey":"Command-49"}]}}
            """.utf8)
        let v2 = Data("""
            {"settings":{"general":{"openAtLogin":true,"showInMenuBar":false,
                "popToRootTimeout":30,"windowMode":"compact"},
                "commands":[{"extensionId":"e:r:emoji-picker","macosHotkey":{"retired":true}}]},
             "skinTone":{"retired":true},"builtin_package_snippets":{"snippets":42},
             "clipboardHistory":{"clipboardEntries":[{"createdAt":"2025-01-01T00:00:00Z",
               "items":[{"representations":[{"mimeType":"text/plain","content":"surviving clipboard"}]}]}]}}
            """.utf8)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tinycast-backup-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, file) in [("v1", try v1File(v1)), ("v2", try v2File(v2))] {
            let url = root.appendingPathComponent(name)
            try file.write(to: url)
            let result = try RaycastImport.read(file: url, passphrase: "fixture")
            expect(result.backup.settings?.compactMode == true, "\(name) compact mode survives")
            expect(result.backup.settings?.popToRootSeconds == 30, "\(name) pop-to-root survives")
            expect(result.backup.settings?.showInMenuBar == false, "\(name) menu preference survives")
            let selected = result.selecting([.compactMode, .popToRoot])
            expect(selected.backup.settings?.showInMenuBar == nil, "\(name) option selection still trims")
            expect(selected.clipboard.isEmpty, "\(name) unselected clipboard excluded")
            if name == "v1" {
                expect(result.backup.hotkeys?.toggleClipboard?.shortcut?.carbonKeyCode == 49,
                       "retired emoji hotkey cannot replace surviving clipboard binding")
            } else {
                expect(result.clipboard.first?.text == "surviving clipboard", "v2 clipboard survives")
                expect(result.backup.settings?.launchAtLogin == true, "v2 launch at login survives")
            }
        }
        print("\(checks) native/v1/v2 legacy compatibility checks passed")
    }
}
