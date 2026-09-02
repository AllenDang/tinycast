import AppKit
import Carbon.HIToolbox

struct KeyShortcut: Hashable, Sendable {
    let carbonKeyCode: Int
    let carbonModifiers: Int

    init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers & Self.allModifiers
    }

    init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .control, .shift])
        let hasCommandingModifier = !flags.isDisjoint(with: [.command, .option, .control])
        guard hasCommandingModifier || Self.isFunctionKey(keyCode) else { return nil }
        self.init(carbonKeyCode: keyCode, carbonModifiers: Self.carbonModifiers(from: flags))
    }

    @MainActor
    func keycaps(
        hyperKey: HyperKeyPhysicalKey, includesShift: Bool, replacesGlyph: Bool
    ) -> [String] {
        Self.collapsedModifierSymbols(
            from: modifierFlags, hyperKey: hyperKey, includesShift: includesShift,
            replacesGlyph: replacesGlyph) + [keyGlyph]
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return carbon
    }

    static func collapsedModifierSymbols(
        from flags: NSEvent.ModifierFlags, hyperKey: HyperKeyPhysicalKey,
        includesShift: Bool, replacesGlyph: Bool
    ) -> [String] {
        guard hyperKey != .none, replacesGlyph else {
            return modifierSymbols(from: flags)
        }
        let hyperSet: NSEvent.ModifierFlags =
            includesShift
            ? [.control, .option, .shift, .command]
            : [.control, .option, .command]
        guard flags.isSuperset(of: hyperSet) else { return modifierSymbols(from: flags) }
        return [HyperKeyPhysicalKey.hyperGlyph] + modifierSymbols(from: flags.subtracting(hyperSet))
    }

    /// Modifier symbols in the fixed ⌃⌥⇧⌘ order every macOS surface uses.
    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    private static let allModifiers = cmdKey | optionKey | controlKey | shiftKey

    // MARK: - Key glyph

    @MainActor private var keyGlyph: String {
        if let special = Self.specialKeyGlyphs[carbonKeyCode] { return special }
        if let name = Self.functionKeyNames[carbonKeyCode] { return name }
        return Self.layoutCharacter(for: carbonKeyCode)?.uppercased() ?? "?"
    }

    private static let specialKeyGlyphs: [Int: String] = [
        kVK_Return: "↵", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "?⃝"
    ]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    // `TISGetInputSourceProperty` is only safe on the main thread.
    @MainActor private static func layoutCharacter(for keyCode: Int) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(
            CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,  // no modifiers: the glyph is the key's base character
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

extension KeyShortcut: Codable {
    private enum CodingKeys: String, CodingKey {
        case carbonKeyCode, carbonModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            carbonKeyCode: try container.decode(Int.self, forKey: .carbonKeyCode),
            carbonModifiers: try container.decode(Int.self, forKey: .carbonModifiers)
        )
    }
}

/// Everything in Tinycast a global shortcut can be bound to.
enum HotKeyAction: Hashable, Sendable {
    case togglePalette
    case toggleClipboard
    case toggleEmoji
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case customCommand(id: UUID)
    case systemAction(id: SystemAction.ID)
    case windowCommand(id: WindowCommand.ID)
    case quicklink(id: UUID)

    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .toggleClipboard: "hotkey.toggleClipboard"
        case .toggleEmoji: "hotkey.toggleEmoji"
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.settingsPane." + bundleID
        case .customCommand(let id):
            "hotkey.customCommand." + id.uuidString.lowercased()
        case .systemAction(let id): "hotkey.systemAction." + id.rawValue
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .quicklink(let id):
            "hotkey.quicklink." + id.uuidString.lowercased()
        }
    }
}
