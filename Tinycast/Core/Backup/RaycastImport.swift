import AppKit
import CryptoKit
import Foundation

enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notRaycastFile: return "This doesn't look like a Raycast export (.rayconfig)."
        case .incorrectPassphrase: return "Incorrect passphrase, or the file is corrupted."
        case .corrupt: return "The Raycast export could not be read."
        }
    }
}

/// Decrypts a Raycast `.rayconfig` export and maps the subset Tinycast supports. Format: gzip → JSON envelope → hex ciphertext decrypted with AES-256-GCM under a scrypt(N=16384,r=8,p=1) key → gunzip → settings JSON. Decrypt is CPU-heavy (scrypt) and pure Foundation/CryptoKit, so run it off the main actor.
enum RaycastImport {
    struct Result {
        var backup: SettingsBackup
        var clipboard: [ClipboardItem]
        /// Image clips whose referenced file no longer exists on disk (reported so the UI can note them).
        var missingImages: Int
    }

    // MARK: - Decrypt

    static func decrypt(file: URL, passphrase: String) throws -> Data {
        let raw = try Data(contentsOf: file)
        guard let envelopeData = try? Gunzip.decompress(raw),
            let env = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
            let dataHex = env["data"] as? String,
            let enc = env["encryption"] as? [String: String],
            let iv = enc["iv"].flatMap(Data.init(hex:)),
            let salt = enc["salt"].flatMap(Data.init(hex:)),
            let tag = enc["authTag"].flatMap(Data.init(hex:)),
            let ciphertext = Data(hex: dataHex)
        else { throw RaycastImportError.notRaycastFile }

        let key = Scrypt.derive(
            passphrase: Array(passphrase.utf8), salt: [UInt8](salt), n: 16384, r: 8, p: 1, dkLen: 32)

        let plaintextGz: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
            plaintextGz = try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw RaycastImportError.incorrectPassphrase
        }
        guard let plaintext = try? Gunzip.decompress(plaintextGz) else {
            throw RaycastImportError.corrupt
        }
        return plaintext
    }

    // MARK: - Map

    static func parse(_ decrypted: Data) throws -> Result {
        guard let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
            throw RaycastImportError.corrupt
        }
        var backup = SettingsBackup()
        backup.settings = mapSettings(json)
        backup.hotkeys = mapHotkeys(json)
        let (clipboard, missing) = mapClipboard(json)
        return Result(backup: backup, clipboard: clipboard, missingImages: missing)
    }

    private static func mapSettings(_ json: [String: Any]) -> SettingsBackup.SettingsData? {
        let general = (json["settings"] as? [String: Any])?["general"] as? [String: Any]
        var data = SettingsBackup.SettingsData()
        var mapped = false
        if let openAtLogin = general?["openAtLogin"] as? Bool {
            data.launchAtLogin = openAtLogin
            mapped = true
        }
        if let includeShift = general?["hyperKeyIncludeShift"] as? Bool {
            data.hyperKeyIncludesShift = includeShift
            mapped = true
        }
        if let tone = mapSkinTone(json) {
            data.emojiSkinTone = tone
            mapped = true
        }
        return mapped ? data : nil
    }

    /// Raycast's palette hotkey uses the same Carbon virtual keycodes and modifier names Tinycast does, so a `LayoutIndependent` shortcut maps directly; character-based (`LayoutDependent`) ones are skipped since Tinycast keys on keycodes.
    private static func mapHotkeys(_ json: [String: Any]) -> SettingsBackup.HotkeyBackup? {
        guard let general = (json["settings"] as? [String: Any])?["general"] as? [String: Any],
            let shortcut = (general["globalHotkey"] as? [String: Any])?["kind"]
                .flatMap({ ($0 as? [String: Any])?["shortcut"] as? [String: Any] }),
            let key = shortcut["key"] as? [String: Any],
            (key["type"] as? String) == "LayoutIndependent",
            let code = key["code"] as? Int
        else { return nil }

        var flags: NSEvent.ModifierFlags = []
        for entry in (shortcut["modifiers"] as? [[String: Any]]) ?? [] {
            switch entry["modifier"] as? String {
            case "Meta": flags.insert(.command)
            case "Ctrl": flags.insert(.control)
            case "Alt": flags.insert(.option)
            case "Shift": flags.insert(.shift)
            default: break
            }
        }
        var hotkeys = SettingsBackup.HotkeyBackup()
        hotkeys.togglePalette = KeyShortcut(
            carbonKeyCode: code, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
        return hotkeys
    }

    /// Raycast stores the tone under an emoji command's preferences; a recursive search avoids hard-coding a brittle path. Enum raw values line up (`light`…`dark`); Raycast's `default` maps to none.
    private static func mapSkinTone(_ json: [String: Any]) -> String? {
        guard let raw = firstValue(forKey: "skinTone", in: json) as? String else { return nil }
        if raw == "default" { return EmojiSkinTone.none.rawValue }
        return EmojiSkinTone(rawValue: raw)?.rawValue
    }

    // MARK: - Clipboard

    private static func mapClipboard(_ json: [String: Any]) -> (items: [ClipboardItem], missing: Int)
    {
        guard
            let entries = (json["clipboardHistory"] as? [String: Any])?["clipboardEntries"]
                as? [[String: Any]]
        else { return ([], 0) }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [ClipboardItem] = []
        var missing = 0
        for entry in entries {
            let createdAt = parseDate(entry["createdAt"] as? String, using: dateParser) ?? Date()
            let reps = (entry["items"] as? [[String: Any]] ?? [])
                .flatMap { ($0["representations"] as? [[String: Any]]) ?? [] }

            if let text = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("text/plain") == true
            })?["content"] as? String, !text.isEmpty {
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: nil))
                continue
            }

            if let path = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("image/") == true
                    && ($0["contentType"] as? String) == "url"
            })?["content"] as? String {
                guard FileManager.default.fileExists(atPath: path) else {
                    missing += 1
                    continue
                }
                items.append(
                    ClipboardItem(imagePath: path, createdAt: createdAt, sourceBundleID: nil))
            }
        }
        return (items, missing)
    }

    // MARK: - Helpers

    private static func parseDate(_ string: String?, using parser: ISO8601DateFormatter) -> Date? {
        guard let string else { return nil }
        // Fractional-seconds parser first; fall back to a whole-second timestamp.
        return parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// First value stored under `key` anywhere in a nested JSON object/array tree.
    private static func firstValue(forKey key: String, in object: Any) -> Any? {
        if let dict = object as? [String: Any] {
            if let hit = dict[key] { return hit }
            for value in dict.values {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        }
        return nil
    }
}

extension Data {
    /// Parses an even-length hex string; returns nil on any non-hex character.
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x61...0x66: return c - 0x61 + 10
            case 0x41...0x46: return c - 0x41 + 10
            default: return nil
            }
        }
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            bytes.append(hi << 4 | lo)
            i += 2
        }
        self = Data(bytes)
    }
}
