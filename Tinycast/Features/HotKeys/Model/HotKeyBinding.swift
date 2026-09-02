import Foundation

enum HotKeyBinding: Codable, Hashable, Sendable {
    case combo(KeyShortcut)
    case doubleTap(DoubleTapModifier)

    /// One string per keycap, so every display site renders both kinds through the same path.
    @MainActor
    func keycaps(
        hyperKey: HyperKeyPhysicalKey, includesShift: Bool, replacesGlyph: Bool
    ) -> [String] {
        switch self {
        case .combo(let shortcut):
            shortcut.keycaps(
                hyperKey: hyperKey, includesShift: includesShift, replacesGlyph: replacesGlyph)
        case .doubleTap(let modifier): modifier.keycaps
        }
    }

    var shortcut: KeyShortcut? {
        if case .combo(let shortcut) = self { return shortcut }
        return nil
    }

    var doubleTapModifier: DoubleTapModifier? {
        if case .doubleTap(let modifier) = self { return modifier }
        return nil
    }
}
