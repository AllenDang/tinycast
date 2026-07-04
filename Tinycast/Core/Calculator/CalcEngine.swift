import Foundation

/// A single evaluated calculator answer for the launcher's inline card.
struct CalcResult: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        /// `display` is the grouped, human-facing string ("1,234,567" / "6.213711922 mi");
        /// `copyText` is the same answer without grouping, suitable for pasting onwards.
        case value(display: String, copyText: String)
        /// A friendly, intentional error ("Cannot convert Weight to Time.") — only produced when
        /// the input clearly *is* a conversion attempt, never for half-typed expressions.
        case error(message: String)
    }

    /// Normalized echo of what was evaluated, shown on the card's left side ("3×3", "10 km").
    let expression: String
    let payload: Payload
}

/// Entry point: turns a raw launcher query into a calculator answer, or nil when the query is not
/// calculator input at all (app names, bare numbers, half-typed expressions). The pipeline is
/// pre-filter → number-base conversion → unit conversion → arithmetic expression; every stage is
/// pure and allocation-light so live per-keystroke evaluation stays well under a millisecond.
///
/// These files (Core/Calculator/*) are Foundation-only on purpose: `Tools/calc-test.swift`
/// compiles them directly into a standalone test binary.
enum CalcEngine {
    static func evaluate(_ raw: String) -> CalcResult? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 256 else { return nil }
        // Cheap reject before tokenizing: calculator input always carries a digit or a constant
        // ("pi", "e"). App searches that slip through ("preview") still cost only a failed
        // tokenize/parse — this filter just keeps the common case near-free.
        guard query.contains(where: { $0.isASCII && $0.isNumber })
                || query.lowercased().contains("e") || query.contains("π")
        else { return nil }

        guard let tokens = CalcTokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        // A lone literal or constant ("45", "3.14", "pi") is far more likely an app search than a
        // calculation — no card. The exception is a radix literal ("0xff"), where echoing the
        // decimal value is genuinely useful.
        if tokens.count == 1 {
            if case .intLiteral(let value, let radix) = tokens[0], radix != 10 {
                let display = CalcFormatter.grouped(String(value))
                return CalcResult(
                    expression: query,
                    payload: .value(display: display, copyText: String(value)))
            }
            return nil
        }

        if let base = baseConversion(tokens, query: query) { return base }

        if let conversion = CalcUnits.parseConversion(tokens) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.symbol)",
                    payload: .value(
                        display: "\(CalcFormatter.display(output)) \(to.symbol)",
                        copyText: "\(CalcFormatter.copyText(output)) \(to.symbol)"))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message:
                            "Cannot convert \(from.category.displayName) to \(to.category.displayName)."
                    ))
            }
        }

        guard let value = CalcParser.evaluate(tokens) else { return nil }
        return CalcResult(
            expression: prettyExpression(query),
            payload: .value(
                display: CalcFormatter.display(value),
                copyText: CalcFormatter.copyText(value)))
    }

    // MARK: - Number bases

    /// `255 to hex`, `0xff to decimal`, `0b1010 to binary` — exactly source → connector → target.
    private static func baseConversion(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count == 3, CalcUnits.isConnector(tokens[1]),
            case .ident(let target) = tokens[2]
        else { return nil }

        let source: UInt64
        switch tokens[0] {
        case .intLiteral(let value, _):
            source = value
        case .number(let value)
        where value >= 0 && value.rounded() == value && value <= 9_007_199_254_740_992:
            source = UInt64(value)
        default:
            return nil
        }

        let output: String
        switch target {
        case "hex", "hexadecimal":
            output = "0x" + String(source, radix: 16, uppercase: true)
        case "binary", "bin":
            output = "0b" + String(source, radix: 2)
        case "octal", "oct":
            output = "0o" + String(source, radix: 8)
        case "decimal", "dec":
            output = CalcFormatter.grouped(String(source))
        default:
            return nil
        }
        let sourceText = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        return CalcResult(
            expression: sourceText,
            payload: .value(display: output, copyText: output.replacingOccurrences(of: ",", with: "")))
    }

    /// Light cleanup of the typed expression for the card: collapse whitespace and use the pretty
    /// operator glyphs, but otherwise keep what the user wrote.
    private static func prettyExpression(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }
}
