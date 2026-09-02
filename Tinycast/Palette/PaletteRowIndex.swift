import Foundation

// periphery:ignore
enum PaletteRow: Equatable {
    case calculator
    case element(section: Int, offset: Int)
}

struct PaletteRowIndex: Equatable {
    let hasCalculator: Bool
    let sectionCounts: [Int]

    init(hasCalculator: Bool = false, sectionCounts: [Int]) {
        self.hasCalculator = hasCalculator
        self.sectionCounts = sectionCounts
    }

    var count: Int { (hasCalculator ? 1 : 0) + sectionCounts.reduce(0, +) }

    /// The selection the screen actually highlights: out-of-range values clamp into the results.
    func clamped(_ selection: Int) -> Int {
        count == 0 ? 0 : min(max(selection, 0), count - 1)
    }

    func moved(from selection: Int, by delta: Int) -> Int {
        clamped(selection + delta)
    }

    // periphery:ignore - only called by Tools/palette-selection-test.swift, which Periphery doesn't index.
    func row(at index: Int) -> PaletteRow? {
        guard index >= 0, index < count else { return nil }
        if hasCalculator, index == 0 { return .calculator }
        var offset = hasCalculator ? index - 1 : index
        for (section, sectionCount) in sectionCounts.enumerated() {
            if offset < sectionCount { return .element(section: section, offset: offset) }
            offset -= sectionCount
        }
        return nil
    }

    // periphery:ignore - harness-only inverse of row(at:); Periphery doesn't index Tools.
    func index(section: Int, offset: Int) -> Int? {
        guard sectionCounts.indices.contains(section), offset >= 0,
            offset < sectionCounts[section]
        else { return nil }
        let preceding = sectionCounts[..<section].reduce(0, +)
        return (hasCalculator ? 1 : 0) + preceding + offset
    }
}

enum LauncherLeadingSlot: Equatable {
    case calculator
    case aiReady
    case aiPending
}

enum LauncherSelectableSlot: Equatable {
    case leading(LauncherLeadingSlot)
    case function(Int)
    case app(Int)
}

/// Selectable launcher slots without UI or feature model values.
struct LauncherSelectableLayout: Equatable {
    let slots: [LauncherSelectableSlot]

    init(leading: LauncherLeadingSlot?, functionCount: Int, appCount: Int) {
        var slots: [LauncherSelectableSlot] = []
        if let leading { slots.append(.leading(leading)) }
        slots.append(contentsOf: (0..<functionCount).map(LauncherSelectableSlot.function))
        slots.append(contentsOf: (0..<appCount).map(LauncherSelectableSlot.app))
        self.slots = slots
    }
}
