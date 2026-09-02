import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    case compactNumber(Double)
    /// Radix-prefixed integer literal (0xff / 0b1010 / 0o777), kept exact for base conversion.
    case intLiteral(UInt64, radix: Int)
    case ident(String)
    case op(Character)  // + - * / ^ ! % ( )
    case comma  // , for vector elements and multi-arg function arguments
    case arrow  // -> or →
}

enum CalcTokenizer {
    static func tokenize(_ input: String) -> [CalcToken]? {
        let chars = Array(input)
        var tokens: [CalcToken] = []
        var i = 0

        func isDigit(_ ch: Character) -> Bool { ch.isASCII && ch.isNumber }

        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace {
                i += 1
                continue
            }

            if ch == "0", i + 2 < chars.count,
                let radix = ["x": 16, "b": 2, "o": 8][String(chars[i + 1]).lowercased()] {
                let start = i + 2
                var end = start
                while end < chars.count, chars[end].isHexDigit { end += 1 }
                if end > start, let value = UInt64(String(chars[start..<end]), radix: radix) {
                    tokens.append(.intLiteral(value, radix: radix))
                    i = end
                    continue
                }
            }

            if isDigit(ch) || (ch == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var text = ""
                var seenDot = false
                while i < chars.count {
                    let c = chars[i]
                    if isDigit(c) {
                        text.append(c)
                    } else if c == "," && i + 1 < chars.count && isDigit(chars[i + 1]) {
                        if isThousandsGroup(chars, i) {
                            // skip
                        } else {
                            break  // end the number, let the comma be tokenized separately
                        }
                    } else if c == "." && !seenDot {
                        seenDot = true
                        text.append(c)
                    } else {
                        break
                    }
                    i += 1
                }
                var isShorthand = false
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var digits = i + 1
                    if digits < chars.count, chars[digits] == "+" || chars[digits] == "-" {
                        digits += 1
                    }
                    var end = digits
                    while end < chars.count, isDigit(chars[end]) { end += 1 }
                    if end > digits {
                        text += String(chars[i..<end])
                        i = end
                        isShorthand = true
                    }
                }
                guard let value = Double(text), value.isFinite else { return nil }
                if i < chars.count, chars[i] == "k" || chars[i] == "K", isCompactSuffix(chars, i) {
                    tokens.append(.compactNumber(value * 1_000))
                    i += 1
                } else if isShorthand {
                    tokens.append(.compactNumber(value))
                } else {
                    tokens.append(.number(value))
                }
                continue
            }

            if ch.isLetter || ch == "°" {
                if ch.isLetter {
                    var letterEnd = i
                    while letterEnd < chars.count, chars[letterEnd].isLetter { letterEnd += 1 }
                    if letterEnd < chars.count, isDigit(chars[letterEnd]) {
                        let prefix = String(chars[i..<letterEnd]).lowercased()
                        if CalcUnits.byName[prefix] == nil, CalcCurrency.byName[prefix] != nil {
                            tokens.append(.ident(prefix))
                            i = letterEnd
                            continue
                        }
                    }
                }
                var text = ""
                while i < chars.count {
                    let c = chars[i]
                    if c.isLetter || c == "°" || isDigit(c) {
                        text.append(c)
                    } else if c == "²" {
                        text.append("2")
                    } else if c == "³" {
                        text.append("3")
                    } else {
                        break
                    }
                    i += 1
                }
                tokens.append(.ident(text.lowercased()))
                continue
            }

            if let code = CurrencyData.signs[ch] {
                tokens.append(.ident(code))
                i += 1
                continue
            }

            // "**" is the Python/JS/shell spelling of power, same operator as "^".
            if ch == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.op("^"))
                i += 2
                continue
            }

            switch ch {
            case "+", "(", ")", "!", "%", "^":
                tokens.append(.op(ch))
            case "*", "×":
                tokens.append(.op("*"))
            case "/", "÷":
                tokens.append(.op("/"))
            case "−":
                tokens.append(.op("-"))
            case "-":
                if i + 1 < chars.count, chars[i + 1] == ">" {
                    tokens.append(.arrow)
                    i += 1
                } else {
                    tokens.append(.op("-"))
                }
            case "→":
                tokens.append(.arrow)
            case ",":
                tokens.append(.comma)
            case "=":
                // Tolerate a trailing "=" ("2+2="); anywhere else it's not calculator input.
                guard i == chars.count - 1 else { return nil }
            default:
                return nil
            }
            i += 1
        }
        return tokens
    }

    private static func isCompactSuffix(_ chars: [Character], _ index: Int) -> Bool {
        let next = index + 1
        guard next < chars.count else { return true }
        if isTemperatureConversion(chars, from: next) { return false }
        guard chars[next].isLetter else { return true }

        var end = next
        while end < chars.count, chars[end].isLetter { end += 1 }
        return CalcCurrency.byName[String(chars[next..<end]).lowercased()] != nil
    }

    private static func isTemperatureConversion(_ chars: [Character], from index: Int) -> Bool {
        let remainder = String(chars[index...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        for connector in ["to", "in", "->", "→"] where remainder.hasPrefix(connector) {
            let target = remainder.dropFirst(connector.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if CalcUnits.byName[target]?.category == .temperature { return true }
        }
        return false
    }

    private static func isThousandsGroup(_ chars: [Character], _ index: Int) -> Bool {
        var j = index + 1
        var digitCount = 0
        while j < chars.count, chars[j].isASCII, chars[j].isNumber {
            digitCount += 1
            j += 1
        }
        // Must have exactly 3 digits, and the next char (if any) must not be a digit.
        guard digitCount == 3 else { return false }
        if j < chars.count, chars[j].isASCII, chars[j].isNumber { return false }
        return true
    }
}

enum CalcParser {
    static func evaluate(_ tokens: [CalcToken]) -> Double? {
        evaluateValue(tokens)?.asScalar
    }

    /// Evaluate to a CalcValue (scalar or vector).
    static func evaluateValue(_ tokens: [CalcToken]) -> CalcValue? {
        var parser = Parser(tokens: tokens)
        guard let result = parser.parseExpression(minBP: 0), parser.isAtEnd else { return nil }
        // Scalar: check finiteness; vectors: check all components are finite.
        switch result.effectiveCalcValue {
        case .scalar(let v):
            guard v.isFinite else { return nil }
        case .vec2(let x, let y):
            guard x.isFinite, y.isFinite else { return nil }
        case .vec3(let x, let y, let z):
            guard x.isFinite, y.isFinite, z.isFinite else { return nil }
        case .vec4(let x, let y, let z, let w):
            guard x.isFinite, y.isFinite, z.isFinite, w.isFinite else { return nil }
        }
        return result.effectiveCalcValue
    }

    // MARK: - Scalar functions (unary)
    fileprivate static let scalarUnary: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "log": { log10($0) }, "ln": { log($0) }, "log2": { log2($0) },
        "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "sinh": { sinh($0) }, "cosh": { cosh($0) }, "tanh": { tanh($0) },
        "abs": { abs($0) }, "floor": { floor($0) }, "ceil": { ceil($0) },
        "round": { $0.rounded() }, "trunc": { trunc($0) },
        "sign": { $0 == 0 ? 0 : ($0 > 0 ? 1 : -1) },
        "fract": { $0 - floor($0) },
        "exp": { exp($0) }, "exp2": { exp2($0) },
        "deg": { $0 * 180 / .pi },   // rad → deg conversion function
        "rad": { $0 * .pi / 180 },   // deg → rad conversion function
        "saturate": { min(max($0, 0), 1) }
    ]

    // MARK: - Scalar functions (binary)
    fileprivate static let scalarBinary: [String: @Sendable (Double, Double) -> Double] = [
        "atan2": { atan2($0, $1) },
        "step": { $0 < $1 ? 0 : 1 },
        "hypot": { hypot($0, $1) }
    ]

    // MARK: - Scalar functions (ternary)
    fileprivate static let scalarTernary: [String: @Sendable (Double, Double, Double) -> Double] = [
        "clamp": { min(max($0, $1), $2) },
        "lerp": { $0 + ($1 - $0) * $2 },
        "smoothstep": {
            let t = min(max(($2 - $0) / ($1 - $0), 0), 1)
            return t * t * (3 - 2 * t)
        },
        "inverselerp": { ($2 - $0) / ($1 - $0) }
    ]

    // MARK: - Vector functions (vector → scalar)
    fileprivate static let vectorToScalar: [String: @Sendable (CalcValue) -> Double?] = [
        "length": { $0.length },
        "len": { $0.length }
    ]

    // MARK: - Vector functions (vector → vector)
    fileprivate static let vectorToVector: [String: @Sendable (CalcValue) -> CalcValue?] = [
        "normalize": { $0.normalized() },
        "norm": { $0.normalized() }
    ]

    // MARK: - Vector functions (vector, vector → scalar)
    fileprivate static let vectorBinaryToScalar: [String: @Sendable (CalcValue, CalcValue) -> Double?] = [
        "dot": { $0.dot($1) }
    ]

    // MARK: - Vector functions (vector, vector → vector)
    fileprivate static let vectorBinaryToVector: [String: @Sendable (CalcValue, CalcValue) -> CalcValue?] = [
        "cross": { $0.cross($1) }
    ]

    // MARK: - Vector constructors (variadic scalars → vector)
    fileprivate static let vectorConstructors: Set<String> = ["vec2", "vec3", "vec4"]

    static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E,
        "tau": 2 * .pi, "φ": 1.618033988749895, "phi": 1.618033988749895
    ]

    /// All function names the parser recognises.
    static var allFunctionNames: Set<String> {
        var names = Set(scalarUnary.keys)
        names.formUnion(scalarBinary.keys)
        names.formUnion(scalarTernary.keys)
        names.formUnion(vectorToScalar.keys)
        names.formUnion(vectorToVector.keys)
        names.formUnion(vectorBinaryToScalar.keys)
        names.formUnion(vectorBinaryToVector.keys)
        names.formUnion(vectorConstructors)
        return names
    }

    /// Metadata for autocomplete suggestions.
    struct FunctionSuggestion: Equatable, Sendable {
        let name: String
        let signature: String  // e.g. "(x)", "(x, y)", "(a, b, t)"
        let category: String   // e.g. "Scalar", "Vector", "Constructor"

        static func suggestions(matching prefix: String) -> [FunctionSuggestion] {
            let lower = prefix.lowercased()
            var result: [FunctionSuggestion] = []
            for name in scalarUnary.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(x)", category: "Scalar"))
            }
            for name in scalarBinary.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(x, y)", category: "Scalar"))
            }
            for name in scalarTernary.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(a, b, c)", category: "Scalar"))
            }
            for name in vectorToScalar.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(v)", category: "Vector→Scalar"))
            }
            for name in vectorToVector.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(v)", category: "Vector→Vector"))
            }
            for name in vectorBinaryToScalar.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(a, b)", category: "Vector→Scalar"))
            }
            for name in vectorBinaryToVector.keys where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(a, b)", category: "Vector→Vector"))
            }
            for name in vectorConstructors where name.hasPrefix(lower) {
                result.append(FunctionSuggestion(name: name, signature: "(...)", category: "Constructor"))
            }
            return result.sorted { $0.name < $1.name }
        }
    }

    /// Factorial for non-negative integers; 170! is the last value representable as a Double.
    static func factorial(_ value: Double) -> Double? {
        guard value >= 0, value.rounded() == value, value <= 170 else { return nil }
        var result = 1.0
        var next = 2.0
        while next <= value {
            result *= next
            next += 1
        }
        return result
    }
}

private struct Parser {
    struct Value {
        var calcValue: CalcValue
        var isPercent = false

        var effective: Double {
            guard case .scalar(let v) = calcValue else { return 0 }
            return isPercent ? v / 100 : v
        }

        /// The raw scalar value (before percent division), for percent arithmetic.
        var rawScalar: Double {
            guard case .scalar(let v) = calcValue else { return 0 }
            return v
        }

        var asScalar: Double? { calcValue.asScalar }

        /// The effective CalcValue accounting for the percent flag.
        var effectiveCalcValue: CalcValue {
            if isPercent, case .scalar(let v) = calcValue {
                return .scalar(v / 100)
            }
            return calcValue
        }

        init(scalar: Double) {
            self.calcValue = .scalar(scalar)
        }

        init(calcValue: CalcValue) {
            self.calcValue = calcValue
        }
    }

    let tokens: [CalcToken]
    var pos = 0

    init(tokens: [CalcToken]) { self.tokens = tokens }

    var isAtEnd: Bool { pos == tokens.count }
    private var current: CalcToken? { pos < tokens.count ? tokens[pos] : nil }

    private static let unaryBP = 25
    private static let mulBP = 20

    mutating func parseExpression(minBP: Int) -> Value? {
        guard var lhs = parseOperand() else { return nil }
        while true {
            if let binary = peekBinary(), binary.bindingPower >= minBP {
                pos += 1
                guard let rhs = parseExpression(minBP: binary.rightBindingPower) else { return nil }
                guard let combined = apply(binary.op, lhs, rhs) else { return nil }
                lhs = combined
                continue
            }
            // Juxtaposition is the operator here, so there's no token to consume before the rhs.
            if impliesMultiplication(), Self.mulBP >= minBP {
                guard let rhs = parseExpression(minBP: Self.mulBP + 1) else { return nil }
                guard let combined = apply("*", lhs, rhs) else { return nil }
                lhs = combined
                continue
            }
            break
        }
        return lhs
    }

    private func impliesMultiplication() -> Bool {
        switch current {
        case .op("("): return true
        case .ident(let name): return CalcParser.constants[name] != nil || CalcParser.allFunctionNames.contains(name)
        default: return false
        }
    }

    /// An operator, its binding power, and the minimum bp for its right operand.
    struct BinaryOp {
        let op: Character
        let bindingPower: Int
        let rightBindingPower: Int
    }

    private func peekBinary() -> BinaryOp? {
        switch current {
        case .op(let op) where op == "+" || op == "-":
            return BinaryOp(op: op, bindingPower: 10, rightBindingPower: 11)
        case .op(let op) where op == "*" || op == "/":
            return BinaryOp(op: op, bindingPower: Self.mulBP, rightBindingPower: Self.mulBP + 1)
        case .ident("of"):
            return BinaryOp(op: "*", bindingPower: Self.mulBP, rightBindingPower: Self.mulBP + 1)
        case .ident("mod"):
            return BinaryOp(op: "%", bindingPower: Self.mulBP, rightBindingPower: Self.mulBP + 1)
        case .op("^"):
            // Exponentiation is right-associative.
            return BinaryOp(op: "^", bindingPower: 30, rightBindingPower: 30)
        default: return nil
        }
    }

    private func apply(_ op: Character, _ lhs: Value, _ rhs: Value) -> Value? {
        // Vector arithmetic
        if lhs.calcValue.dimension > 1 || rhs.calcValue.dimension > 1 {
            return applyVector(op, lhs.calcValue, rhs.calcValue).map(Value.init)
        }

        let result: Double
        switch op {
        // `450 + 20%` reads as a relative change: 450 * 1.2. With a plain rhs it's ordinary math.
        case "+":
            result =
                rhs.isPercent
                ? lhs.effective * (1 + rhs.rawScalar / 100) : lhs.effective + rhs.effective
        case "-":
            result =
                rhs.isPercent
                ? lhs.effective * (1 - rhs.rawScalar / 100) : lhs.effective - rhs.effective
        case "*": result = lhs.effective * rhs.effective
        case "/": result = lhs.effective / rhs.effective
        case "%": result = lhs.effective.truncatingRemainder(dividingBy: rhs.effective)
        case "^": result = pow(lhs.effective, rhs.effective)
        default: return nil
        }
        return Value(scalar: result)
    }

    private func applyVector(_ op: Character, _ lhs: CalcValue, _ rhs: CalcValue) -> CalcValue? {
        switch op {
        case "+": return lhs + rhs
        case "-": return lhs - rhs
        case "*": return lhs * rhs
        case "/": return lhs / rhs
        case "^":
            // Only scalar^scalar, not vector^anything
            guard case .scalar = lhs, case .scalar = rhs else { return nil }
            return .scalar(pow(lhs.asScalar!, rhs.asScalar!))
        default: return nil
        }
    }

    /// One prefix item plus all its postfixes (`!`, `%`, `deg`) — postfixes bind tightest.
    private mutating func parseOperand() -> Value? {
        guard var value = parsePrefix() else { return nil }
        loop: while true {
            switch current {
            case .op("!"):
                guard !value.isPercent, let s = value.asScalar, let fact = CalcParser.factorial(s) else {
                    return nil
                }
                value = Value(scalar: fact)
            case .op("%"):
                guard !value.isPercent, value.calcValue.dimension == 1 else { return nil }
                value.isPercent = true
            case .ident("deg"):
                guard !value.isPercent, let s = value.asScalar else { return nil }
                value = Value(scalar: s * .pi / 180)
            default:
                break loop
            }
            pos += 1
        }
        return value
    }

    private mutating func parsePrefix() -> Value? {
        switch current {
        case .number(let n):
            pos += 1
            return Value(scalar: n)
        case .compactNumber(let n):
            pos += 1
            return Value(scalar: n)
        case .intLiteral(let n, _):
            pos += 1
            return Value(scalar: Double(n))
        case .op("-"):
            pos += 1
            guard let operand = parseExpression(minBP: Self.unaryBP) else { return nil }
            return Value(calcValue: -operand.calcValue)
        case .op("+"):
            pos += 1
            return parseExpression(minBP: Self.unaryBP)
        case .op("("):
            return parseParenGroup()
        case .ident(let name):
            if let constant = CalcParser.constants[name] {
                pos += 1
                return Value(scalar: constant)
            }
            return parseFunctionCall(name)
        default:
            return nil
        }
    }

    private mutating func parseParenGroup() -> Value? {
        pos += 1 // consume '('
        guard let first = parseExpression(minBP: 0) else { return nil }

        // If followed by comma, this is a vector literal.
        if case .comma = current {
            var elements = [first.asScalar].compactMap { $0 }
            while case .comma = current {
                pos += 1 // consume ','
                guard let elem = parseExpression(minBP: 0), let scalar = elem.asScalar else { return nil }
                elements.append(scalar)
            }
            guard case .op(")") = current else { return nil }
            pos += 1 // consume ')'
            let v: CalcValue
            switch elements.count {
            case 2: v = .vec2(elements[0], elements[1])
            case 3: v = .vec3(elements[0], elements[1], elements[2])
            case 4: v = .vec4(elements[0], elements[1], elements[2], elements[3])
            default: return nil
            }
            return Value(calcValue: v)
        }

        // Scalar grouping.
        guard case .op(")") = current else { return nil }
        pos += 1 // consume ')'
        return first
    }

    /// Parse a function call (name already consumed from the token stream).
    private mutating func parseFunctionCall(_ name: String) -> Value? {
        pos += 1 // consume the ident

        // Parse argument list: either bare (single operand) or parenthesized with comma separation.
        let args: [Value]
        if case .op("(") = current {
            pos += 1 // consume '('
            var parsed: [Value] = []
            if case .op(")") = current {
                // Empty arg list — no arguments.
            } else {
                guard let first = parseExpression(minBP: 0) else { return nil }
                parsed.append(first)
                while case .comma = current {
                    pos += 1 // consume ','
                    guard let next = parseExpression(minBP: 0) else { return nil }
                    parsed.append(next)
                }
            }
            guard case .op(")") = current else { return nil }
            pos += 1 // consume ')'
            args = parsed
        } else {
            // Bare application: `sqrt 64`, `sin 30deg` — one operand.
            guard let arg = parseOperand() else { return nil }
            args = [arg]
        }

        return dispatchFunction(name, args)
    }

    /// Route a function call to the right handler based on name and argument count.
    private func dispatchFunction(_ name: String, _ args: [Value]) -> Value? {
        // Vector constructors: vec2(x,y), vec3(x,y,z), vec4(x,y,z,w)
        if CalcParser.vectorConstructors.contains(name) {
            let scalars = args.compactMap(\.asScalar)
            guard scalars.count == args.count else { return nil }
            let v: CalcValue
            switch name {
            case "vec2":
                guard scalars.count == 2 else { return nil }
                v = .vec2(scalars[0], scalars[1])
            case "vec3":
                guard scalars.count == 3 else { return nil }
                v = .vec3(scalars[0], scalars[1], scalars[2])
            case "vec4":
                guard scalars.count == 4 else { return nil }
                v = .vec4(scalars[0], scalars[1], scalars[2], scalars[3])
            default: return nil
            }
            return Value(calcValue: v)
        }

        // Scalar unary
        if let fn = CalcParser.scalarUnary[name] {
            guard args.count == 1, let s = args[0].asScalar else { return nil }
            return Value(scalar: fn(s))
        }

        // Scalar binary
        if let fn = CalcParser.scalarBinary[name] {
            guard args.count == 2, let a = args[0].asScalar, let b = args[1].asScalar else { return nil }
            return Value(scalar: fn(a, b))
        }

        // Scalar ternary
        if let fn = CalcParser.scalarTernary[name] {
            guard args.count == 3, let a = args[0].asScalar, let b = args[1].asScalar, let c = args[2].asScalar
            else { return nil }
            return Value(scalar: fn(a, b, c))
        }

        // Vector → scalar
        if let fn = CalcParser.vectorToScalar[name] {
            let vec = packVectorArgs(args)
            guard let result = fn(vec) else { return nil }
            return Value(scalar: result)
        }

        // Vector → vector
        if let fn = CalcParser.vectorToVector[name] {
            let vec = packVectorArgs(args)
            guard let result = fn(vec) else { return nil }
            return Value(calcValue: result)
        }

        // Vector, vector → scalar
        if let fn = CalcParser.vectorBinaryToScalar[name] {
            guard args.count == 2, let result = fn(args[0].calcValue, args[1].calcValue) else { return nil }
            return Value(scalar: result)
        }

        // Vector, vector → vector
        if let fn = CalcParser.vectorBinaryToVector[name] {
            guard args.count == 2, let result = fn(args[0].calcValue, args[1].calcValue) else { return nil }
            return Value(calcValue: result)
        }

        return nil
    }

    /// Auto-pack multiple scalar args into a vector for vector functions (e.g. `length(1, 2, 3)`).
    private func packVectorArgs(_ args: [Value]) -> CalcValue {
        if args.count == 1 { return args[0].calcValue }
        let scalars = args.compactMap(\.asScalar)
        if scalars.count == args.count {
            switch scalars.count {
            case 2: return .vec2(scalars[0], scalars[1])
            case 3: return .vec3(scalars[0], scalars[1], scalars[2])
            case 4: return .vec4(scalars[0], scalars[1], scalars[2], scalars[3])
            default: break
            }
        }
        return args[0].calcValue
    }
}
