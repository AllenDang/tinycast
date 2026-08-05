import SwiftUI

/// One palette mode. `rows` is its single source of visible order, so selection indexes it.
@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }

    func actions(for row: Row) -> PopoverMenuContent?
    func activate(_ row: Row)
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}
