import Foundation

enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature, time, area, volume, digitalStorage

    var displayName: String {
        switch self {
        case .length: return "Length"
        case .weight: return "Weight"
        case .temperature: return "Temperature"
        case .time: return "Time"
        case .area: return "Area"
        case .volume: return "Volume"
        case .digitalStorage: return "Digital Storage"
        }
    }
}

/// One unit as an affine map onto its category's base unit: `base = value * factor + offset`.
/// `offset` is zero everywhere except temperature (base Kelvin), which is why conversion below is
/// affine rather than a plain ratio — °C/°F/K come out right with no special-casing.
struct UnitDef: Equatable, Sendable {
    let symbol: String  // canonical display form: "mi", "°F", "GiB"
    let category: UnitCategory
    let factor: Double
    let offset: Double

    init(_ symbol: String, _ category: UnitCategory, _ factor: Double, offset: Double = 0) {
        self.symbol = symbol
        self.category = category
        self.factor = factor
        self.offset = offset
    }
}

enum CalcUnits {
    enum ConversionParse: Equatable {
        case value(input: Double, from: UnitDef, to: UnitDef, output: Double)
        case mismatch(from: UnitDef, to: UnitDef)
    }

    /// Detects `expr unit (to|in|->) unit` in the token stream. Returns nil when the query is not
    /// a unit conversion at all; `.mismatch` only when both units are known but incompatible — the
    /// one case that deserves a friendly error instead of silence.
    ///
    /// The connector must be the second-to-last token and the last token a known unit. Taking the
    /// *last* qualifying position resolves "in" doubling as inches: in "10 in in cm" the first
    /// "in" is the unit and the second the connector.
    static func parseConversion(_ tokens: [CalcToken]) -> ConversionParse? {
        guard tokens.count >= 4, isConnector(tokens[tokens.count - 2]),
            case .ident(let toName) = tokens[tokens.count - 1],
            let to = byName[toName],
            case .ident(let fromName) = tokens[tokens.count - 3],
            let from = byName[fromName]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 3)])
        guard let input = CalcParser.evaluate(valueTokens) else { return nil }

        guard from.category == to.category else { return .mismatch(from: from, to: to) }
        let output = (input * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return .value(input: input, from: from, to: to, output: output)
    }

    static func isConnector(_ token: CalcToken) -> Bool {
        switch token {
        case .arrow, .ident("to"), .ident("in"): return true
        default: return false
        }
    }

    /// Lookup by lowercased, `²`-folded name (the tokenizer's ident form).
    static let byName: [String: UnitDef] = {
        var table: [String: UnitDef] = [:]
        func add(_ def: UnitDef, _ names: [String]) {
            for name in names { table[name] = def }
        }

        // Length (base: meter)
        add(UnitDef("mm", .length, 0.001), ["mm", "millimeter", "millimeters", "millimetre", "millimetres"])
        add(UnitDef("cm", .length, 0.01), ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
        add(UnitDef("m", .length, 1), ["m", "meter", "meters", "metre", "metres"])
        add(UnitDef("km", .length, 1000), ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add(UnitDef("in", .length, 0.0254), ["in", "inch", "inches"])
        add(UnitDef("ft", .length, 0.3048), ["ft", "foot", "feet"])
        add(UnitDef("yd", .length, 0.9144), ["yd", "yard", "yards"])
        add(UnitDef("mi", .length, 1609.344), ["mi", "mile", "miles"])

        // Weight (base: kilogram)
        add(UnitDef("mg", .weight, 1e-6), ["mg", "milligram", "milligrams"])
        add(UnitDef("g", .weight, 0.001), ["g", "gram", "grams"])
        add(UnitDef("kg", .weight, 1), ["kg", "kilogram", "kilograms", "kilo", "kilos"])
        add(UnitDef("oz", .weight, 0.028349523125), ["oz", "ounce", "ounces"])
        add(UnitDef("lb", .weight, 0.45359237), ["lb", "lbs", "pound", "pounds"])

        // Temperature (base: Kelvin) — the only affine category.
        add(UnitDef("°C", .temperature, 1, offset: 273.15), ["c", "°c", "celsius", "centigrade"])
        add(
            UnitDef("°F", .temperature, 5.0 / 9.0, offset: 273.15 - 32 * 5.0 / 9.0),
            ["f", "°f", "fahrenheit"])
        add(UnitDef("K", .temperature, 1), ["k", "kelvin", "kelvins"])

        // Time (base: second)
        add(UnitDef("ms", .time, 0.001), ["ms", "millisecond", "milliseconds"])
        add(UnitDef("s", .time, 1), ["s", "sec", "secs", "second", "seconds"])
        add(UnitDef("min", .time, 60), ["min", "mins", "minute", "minutes"])
        add(UnitDef("hr", .time, 3600), ["h", "hr", "hrs", "hour", "hours"])
        add(UnitDef("day", .time, 86400), ["d", "day", "days"])
        add(UnitDef("week", .time, 604800), ["wk", "week", "weeks"])

        // Area (base: square meter). The tokenizer folds "²" to "2", so mm²/mm2 are one name.
        add(UnitDef("mm²", .area, 1e-6), ["mm2", "sqmm"])
        add(UnitDef("cm²", .area, 1e-4), ["cm2", "sqcm"])
        add(UnitDef("m²", .area, 1), ["m2", "sqm"])
        add(UnitDef("km²", .area, 1e6), ["km2", "sqkm"])
        add(UnitDef("in²", .area, 0.00064516), ["in2", "sqin"])
        add(UnitDef("ft²", .area, 0.09290304), ["ft2", "sqft"])
        add(UnitDef("yd²", .area, 0.83612736), ["yd2", "sqyd"])
        add(UnitDef("mi²", .area, 2_589_988.110336), ["mi2", "sqmi"])
        add(UnitDef("acre", .area, 4046.8564224), ["acre", "acres"])
        add(UnitDef("ha", .area, 10000), ["ha", "hectare", "hectares"])

        // Volume (base: liter; US customary)
        add(UnitDef("mL", .volume, 0.001), ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
        add(UnitDef("L", .volume, 1), ["l", "liter", "liters", "litre", "litres"])
        add(UnitDef("cup", .volume, 0.2365882365), ["cup", "cups"])
        add(UnitDef("tbsp", .volume, 0.01478676478125), ["tbsp", "tablespoon", "tablespoons"])
        add(UnitDef("tsp", .volume, 0.00492892159375), ["tsp", "teaspoon", "teaspoons"])
        add(UnitDef("gal", .volume, 3.785411784), ["gal", "gallon", "gallons"])
        add(UnitDef("qt", .volume, 0.946352946), ["qt", "quart", "quarts"])
        add(UnitDef("pt", .volume, 0.473176473), ["pt", "pint", "pints"])
        add(UnitDef("fl oz", .volume, 0.0295735295625), ["floz"])

        // Digital storage (base: byte) — kB/MB/… are SI (1000ⁿ), KiB/MiB/… are IEC (1024ⁿ).
        add(UnitDef("bit", .digitalStorage, 0.125), ["bit", "bits"])
        add(UnitDef("B", .digitalStorage, 1), ["b", "byte", "bytes"])
        add(UnitDef("kB", .digitalStorage, 1e3), ["kb", "kilobyte", "kilobytes"])
        add(UnitDef("MB", .digitalStorage, 1e6), ["mb", "megabyte", "megabytes"])
        add(UnitDef("GB", .digitalStorage, 1e9), ["gb", "gigabyte", "gigabytes"])
        add(UnitDef("TB", .digitalStorage, 1e12), ["tb", "terabyte", "terabytes"])
        add(UnitDef("PB", .digitalStorage, 1e15), ["pb", "petabyte", "petabytes"])
        add(UnitDef("KiB", .digitalStorage, 1024), ["kib", "kibibyte", "kibibytes"])
        add(UnitDef("MiB", .digitalStorage, 1_048_576), ["mib", "mebibyte", "mebibytes"])
        add(UnitDef("GiB", .digitalStorage, 1_073_741_824), ["gib", "gibibyte", "gibibytes"])
        add(UnitDef("TiB", .digitalStorage, 1_099_511_627_776), ["tib", "tebibyte", "tebibytes"])

        return table
    }()
}
