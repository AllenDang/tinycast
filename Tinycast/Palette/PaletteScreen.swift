import SwiftUI

/// Which arrow pair a move came from: ↑/↓ or ←/→.
enum PaletteAxis {
    case vertical
    case horizontal
}

enum PaletteCommand: Equatable {
    case alternateActivate
    case delete
    case pin
    case quit
}

/// One palette mode. `rows` is its single source of visible order, so selection indexes it.
@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }

    /// False when the selection cannot be activated, which hides the primary footer action.
    func hasPrimaryAction(at selection: Int) -> Bool
    func actions(at selection: Int) -> PopoverMenuContent?
    func activate(at selection: Int)
    /// ⌘↵. False when the selection has no secondary action, leaving the key unhandled.
    func secondary(at selection: Int) -> Bool
    func perform(_ command: PaletteCommand, at selection: Int) -> Bool
    func isRunning(at selection: Int) -> Bool
    /// The selection an arrow key lands on, or nil to leave the key to the palette's own default.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int?
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}

extension PaletteScreen {
    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func perform(_ command: PaletteCommand, at selection: Int) -> Bool { false }
    func isRunning(at selection: Int) -> Bool { false }
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? { nil }
}
