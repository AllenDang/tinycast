import Foundation

@main
@MainActor
struct PaletteRowIndexTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: PaletteRow?, _ expected: PaletteRow?, _ message: String) {
        expect(actual == expected, "\(message) — got \(String(describing: actual)), want \(String(describing: expected))")
    }

    static func expect(_ actual: Int?, _ expected: Int?, _ message: String) {
        expect(actual == expected, "\(message) — got \(String(describing: actual)), want \(String(describing: expected))")
    }

    /// Every index resolves, and resolving then inverting returns the index it started from.
    static func expectRoundTrip(_ index: PaletteRowIndex, _ label: String) {
        for flat in 0..<index.count {
            guard let row = index.row(at: flat) else {
                expect(false, "\(label): index \(flat) resolves to a row")
                continue
            }
            switch row {
            case .calculator:
                expect(flat == 0, "\(label): the calculator card only ever sits at index 0")
            case .element(let section, let offset):
                expect(
                    index.index(section: section, offset: offset), flat,
                    "\(label): section \(section) offset \(offset) inverts to \(flat)")
            }
        }
    }

    static func main() {
        // Empty list: nothing resolves and the clamp still yields a usable selection.
        let empty = PaletteRowIndex(sectionCounts: [])
        expect(empty.count == 0, "an empty screen has no rows")
        expect(empty.row(at: 0), nil, "an empty screen resolves no index")
        expect(empty.clamped(0) == 0, "the clamp holds at zero with no rows")
        expect(empty.clamped(7) == 0, "an out-of-range selection clamps to zero with no rows")
        expect(empty.index(section: 0, offset: 0), nil, "an empty screen has no section 0")

        // A screen whose sections are all empty is still an empty screen.
        let allEmptySections = PaletteRowIndex(sectionCounts: [0, 0, 0])
        expect(allEmptySections.count == 0, "empty sections contribute no rows")
        expect(allEmptySections.row(at: 0), nil, "empty sections resolve no index")

        // Single section, no calculator card: the flat index is the section offset.
        let single = PaletteRowIndex(sectionCounts: [3])
        expect(single.count == 3, "one section of 3 is 3 rows")
        expect(single.row(at: 0), .element(section: 0, offset: 0), "index 0 is the first result")
        expect(single.row(at: 1), .element(section: 0, offset: 1), "index 1 is the second result")
        expect(single.row(at: 2), .element(section: 0, offset: 2), "index 2 is the last result")
        expect(single.row(at: 3), nil, "one past the end resolves to nothing")
        expect(single.row(at: -1), nil, "a negative index resolves to nothing")
        expectRoundTrip(single, "single section")

        // The calculator card takes index 0 and shifts every result down by one.
        let withCalc = PaletteRowIndex(hasCalculator: true, sectionCounts: [3])
        expect(withCalc.count == 4, "the calculator card adds one row")
        expect(withCalc.row(at: 0), .calculator, "the calculator card occupies index 0")
        expect(
            withCalc.row(at: 1), .element(section: 0, offset: 0),
            "the first result follows the calculator card")
        expect(
            withCalc.row(at: 3), .element(section: 0, offset: 2),
            "the last result sits at count - 1")
        expect(withCalc.row(at: 4), nil, "one past the end resolves to nothing")
        expect(
            withCalc.index(section: 0, offset: 0), 1,
            "a card present shifts the first result's index to 1")
        expectRoundTrip(withCalc, "single section with calculator")

        // A calculator card with no results is selectable on its own.
        let calcOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [])
        expect(calcOnly.count == 1, "a lone calculator card is one row")
        expect(calcOnly.row(at: 0), .calculator, "a lone calculator card is the whole list")
        expect(calcOnly.clamped(9) == 0, "the clamp lands on the card")

        // Multiple sections: headers are not selectable, so no index is spent on them.
        let sections = PaletteRowIndex(sectionCounts: [2, 1, 3])
        expect(sections.count == 6, "three sections of 2, 1 and 3 are 6 selectable rows")
        expect(sections.row(at: 1), .element(section: 0, offset: 1), "the first section's last row")
        expect(
            sections.row(at: 2), .element(section: 1, offset: 0),
            "the next index crosses into the second section, skipping its header")
        expect(
            sections.row(at: 3), .element(section: 2, offset: 0),
            "a one-row section is crossed in a single step")
        expect(sections.row(at: 5), .element(section: 2, offset: 2), "the final row of the last section")
        expect(sections.row(at: 6), nil, "one past the last section resolves to nothing")
        expectRoundTrip(sections, "three sections")

        // An empty section in the middle is skipped entirely rather than consuming an index.
        let gapped = PaletteRowIndex(sectionCounts: [2, 0, 2])
        expect(gapped.count == 4, "an empty section contributes no rows")
        expect(
            gapped.row(at: 2), .element(section: 2, offset: 0),
            "an empty section is stepped over, not landed in")
        expect(gapped.index(section: 1, offset: 0), nil, "an empty section has no valid offset")
        expectRoundTrip(gapped, "empty middle section")

        // Sections plus the calculator card — the launcher's real shape.
        let launcher = PaletteRowIndex(hasCalculator: true, sectionCounts: [2, 1, 3])
        expect(launcher.count == 7, "the card plus six results")
        expect(launcher.row(at: 0), .calculator, "the card still leads")
        expect(
            launcher.row(at: 3), .element(section: 1, offset: 0),
            "a section crossing accounts for the card")
        expect(
            launcher.index(section: 2, offset: 2), 6,
            "the last row of the last section is the last index")
        expectRoundTrip(launcher, "launcher shape")

        // Clamping at both ends, with and without a card.
        for index in [single, withCalc, sections, launcher, gapped] {
            expect(index.clamped(-1) == 0, "a selection below zero clamps to the first row")
            expect(index.clamped(-99) == 0, "a far-negative selection clamps to the first row")
            expect(
                index.clamped(index.count) == index.count - 1,
                "a selection one past the end clamps to the last row")
            expect(
                index.clamped(index.count + 50) == index.count - 1,
                "a far-past-the-end selection clamps to the last row")
            expect(
                index.row(at: index.clamped(Int.max)) != nil,
                "a clamped selection always resolves to a row")
            expect(
                index.row(at: index.clamped(Int.min)) != nil,
                "a clamped negative selection always resolves to a row")
        }

        // Out-of-bounds inversion never invents an index.
        expect(sections.index(section: 3, offset: 0), nil, "there is no fourth section")
        expect(sections.index(section: -1, offset: 0), nil, "there is no section before the first")
        expect(sections.index(section: 0, offset: 2), nil, "an offset past a section's rows is nothing")
        expect(sections.index(section: 0, offset: -1), nil, "a negative offset is nothing")

        // Exhaustive: over a spread of shapes, every flat index maps 1:1 onto visible row order.
        for hasCalculator in [false, true] {
            for a in 0...3 {
                for b in 0...3 {
                    for c in 0...3 {
                        let index = PaletteRowIndex(
                            hasCalculator: hasCalculator, sectionCounts: [a, b, c])
                        let label = "shape calc=\(hasCalculator) [\(a),\(b),\(c)]"
                        expect(
                            index.count == (hasCalculator ? 1 : 0) + a + b + c,
                            "\(label): the row count is the card plus every section")
                        expectRoundTrip(index, label)
                        let rows = (0..<index.count).compactMap(index.row(at:))
                        expect(
                            Set(rows.map(String.init(describing:))).count == rows.count,
                            "\(label): no two indices resolve to the same row")
                    }
                }
            }
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
