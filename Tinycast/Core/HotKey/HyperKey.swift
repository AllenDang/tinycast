import Carbon.HIToolbox
import CoreGraphics

/// The physical key remapped to the Hyper chord (⌃⌥⇧⌘ pressed at once). String raw values are
/// the persistence format in `AppSettings`, so renaming a case is a defaults migration.
enum HyperKeyPhysicalKey: String, CaseIterable, Identifiable, Sendable {
    case none
    case capsLock
    case leftControl, leftShift, leftOption, leftCommand
    case rightControl, rightShift, rightOption, rightCommand
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19

    var id: String { rawValue }

    /// The single glyph Hyper shortcuts collapse to, Raycast-style.
    static let hyperGlyph = "✦"

    /// Picker sections: the eight side-specific modifiers, then the function keys.
    static let modifierChoices: [HyperKeyPhysicalKey] = [
        .leftControl, .leftShift, .leftOption, .leftCommand,
        .rightControl, .rightShift, .rightOption, .rightCommand,
    ]
    static let functionChoices: [HyperKeyPhysicalKey] = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19,
    ]

    var title: String {
        switch self {
        case .none: return "None"
        case .capsLock: return "Caps Lock (⇪)"
        case .leftControl: return "Left Control (⌃)"
        case .leftShift: return "Left Shift (⇧)"
        case .leftOption: return "Left Option (⌥)"
        case .leftCommand: return "Left Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .rightShift: return "Right Shift (⇧)"
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        default: return "F\(functionNumber ?? 0)"
        }
    }

    /// Virtual key code of the physical key, `nil` only for `.none`.
    var keyCode: Int? {
        switch self {
        case .none: return nil
        case .capsLock: return kVK_CapsLock
        case .leftControl: return kVK_Control
        case .leftShift: return kVK_Shift
        case .leftOption: return kVK_Option
        case .leftCommand: return kVK_Command
        case .rightControl: return kVK_RightControl
        case .rightShift: return kVK_RightShift
        case .rightOption: return kVK_RightOption
        case .rightCommand: return kVK_RightCommand
        case .f1: return kVK_F1
        case .f2: return kVK_F2
        case .f3: return kVK_F3
        case .f4: return kVK_F4
        case .f5: return kVK_F5
        case .f6: return kVK_F6
        case .f7: return kVK_F7
        case .f8: return kVK_F8
        case .f9: return kVK_F9
        case .f10: return kVK_F10
        case .f11: return kVK_F11
        case .f12: return kVK_F12
        case .f13: return kVK_F13
        case .f14: return kVK_F14
        case .f15: return kVK_F15
        case .f16: return kVK_F16
        case .f17: return kVK_F17
        case .f18: return kVK_F18
        case .f19: return kVK_F19
        }
    }

    var isFunctionKey: Bool { Self.functionChoices.contains(self) }

    /// Caps Lock and the modifiers report presses as `flagsChanged`; F-keys as keyDown/keyUp.
    var isModifierLike: Bool { self != .none && !isFunctionKey }

    /// Keys that do something on their own when not remapped — these get the Quick Press row.
    var hasOriginalFunction: Bool { self == .capsLock || isFunctionKey }

    /// The generic `CGEventFlags` bit this key itself contributes, so the tap can strip it when
    /// the key sits outside the synthetic Hyper set (Left Shift as Hyper with Include Shift off).
    var ownFlag: CGEventFlags? {
        switch self {
        case .capsLock: return .maskAlphaShift
        case .leftControl, .rightControl: return .maskControl
        case .leftShift, .rightShift: return .maskShift
        case .leftOption, .rightOption: return .maskAlternate
        case .leftCommand, .rightCommand: return .maskCommand
        default: return nil
        }
    }

    /// Quick Press label for triggering the key's original function ("Trigger Caps Lock (⇪)").
    var quickPressOriginalTitle: String? {
        switch self {
        case .capsLock: return "Trigger Caps Lock (⇪)"
        default: return isFunctionKey ? "Trigger F\(functionNumber ?? 0)" : nil
        }
    }

    private var functionNumber: Int? {
        guard let index = Self.functionChoices.firstIndex(of: self) else { return nil }
        return index + 1
    }
}

/// What a quick lone press of the Hyper key does (only offered for keys with an original function).
enum HyperKeyQuickPress: String, CaseIterable, Sendable {
    case none
    case originalKey
    case escape
}
