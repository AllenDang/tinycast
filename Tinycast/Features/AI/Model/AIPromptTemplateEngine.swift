import Foundation

enum AIPromptTemplateEngine {
    struct ExpansionContext: Sendable {
        let clipboardHistory: [String]
        let selection: String
        let now: Date
        let calendar: Calendar
        let locale: Locale
        let timeZone: TimeZone
        let input: String
        /// Injected so `{uuid}` is reproducible under test.
        let makeUUID: @Sendable () -> String

        init(
            clipboardHistory: [String],
            selection: String,
            now: Date,
            calendar: Calendar,
            locale: Locale,
            timeZone: TimeZone,
            input: String = "",
            makeUUID: @escaping @Sendable () -> String = { UUID().uuidString }
        ) {
            var calendar = calendar
            calendar.timeZone = timeZone
            self.clipboardHistory = clipboardHistory
            self.selection = selection
            self.now = now
            self.calendar = calendar
            self.locale = locale
            self.timeZone = timeZone
            self.input = input
            self.makeUUID = makeUUID
        }

    }

    static func expand(text: String, context: ExpansionContext) -> String {
        expandText(text, context: context)
    }

    // MARK: - Tokens

    private enum Segment {
        case literal(String)
        case clipboard(offset: Int, modifiers: [Modifier])
        case selection(modifiers: [Modifier])
        case input(modifiers: [Modifier])
        case dateTime(DateTimeToken, modifiers: [Modifier])
        case uuid(modifiers: [Modifier])
        case argument(ArgumentToken, source: String, modifiers: [Modifier])
        case cursor
    }

    private struct DateTimeToken {
        enum Kind {
            case date
            case time
            case dateTime
            case weekday
        }

        let kind: Kind
        /// Signed calendar offsets, applied in written order.
        let offsets: [Offset]
        let format: String?
        let localeIdentifier: String?

        struct Offset {
            let component: Calendar.Component
            let value: Int
        }
    }

    private struct ArgumentToken {
        let defaultValue: String?
    }

    /// Post-processing applied to a placeholder's value, left to right.
    private enum Modifier: String {
        case uppercase
        case lowercase
        case trim
        case percentEncode = "percent-encode"
        case jsonStringify = "json-stringify"
        case raw
    }

    // MARK: - Expansion

    private static func expandText(
        _ text: String,
        context: ExpansionContext
    ) -> String {
        var result = ""
        for segment in parseSegments(text) {
            switch segment {
            case .literal(let value):
                result.append(value)
            case .clipboard(let offset, let modifiers):
                let value = offset < context.clipboardHistory.count
                    ? context.clipboardHistory[offset] : ""
                result.append(apply(modifiers, to: value))
            case .selection(let modifiers):
                result.append(apply(modifiers, to: context.selection))
            case .input(let modifiers):
                result.append(apply(modifiers, to: context.input))
            case .dateTime(let token, let modifiers):
                result.append(
                    apply(modifiers, to: format(token, context: context)))
            case .uuid(let modifiers):
                result.append(apply(modifiers, to: context.makeUUID()))
            case .argument(let token, let source, let modifiers):
                if let value = token.defaultValue {
                    result.append(apply(modifiers, to: value))
                } else {
                    result.append(source)
                }
            case .cursor:
                break
            }
        }
        return result
    }

    private static func apply(
        _ modifiers: [Modifier], to value: String
    ) -> String {
        let modified = modifiers.reduce(value) { partial, modifier in
            switch modifier {
            case .uppercase: return partial.uppercased()
            case .lowercase: return partial.lowercased()
            case .trim: return partial.trimmingCharacters(in: .whitespacesAndNewlines)
            case .percentEncode: return percentEncoded(partial)
            case .jsonStringify: return jsonEscaped(partial)
            case .raw: return partial
            }
        }
        return modified
    }

    private static func percentEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func jsonEscaped(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += String(format: "\\u%04x", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return escaped
    }

    // MARK: - Parsing

    private static func parseSegments(_ source: String) -> [Segment] {
        var segments: [Segment] = []
        var position = source.startIndex

        while position < source.endIndex,
            let opening = source[position...].firstIndex(of: "{") {
            if position < opening {
                segments.append(.literal(String(source[position..<opening])))
            }
            guard let closing = source[source.index(after: opening)...].firstIndex(of: "}") else {
                segments.append(.literal(String(source[opening...])))
                return segments
            }

            let end = source.index(after: closing)
            let rawToken = String(source[opening..<end])
            let tokenBody = String(source[source.index(after: opening)..<closing])
            if let segment = segment(for: tokenBody, source: rawToken) {
                segments.append(segment)
                position = end
            } else {
                segments.append(.literal("{"))
                position = source.index(after: opening)
            }
        }

        if position < source.endIndex {
            segments.append(.literal(String(source[position...])))
        }
        return segments
    }

    private static func segment(for body: String, source: String) -> Segment? {
        guard let parts = splitOnPipes(body), let head = parts.first else { return nil }
        var modifiers: [Modifier] = []
        for raw in parts.dropFirst() {
            guard let modifier = Modifier(rawValue: raw) else { return nil }
            modifiers.append(modifier)
        }

        if head == "cursor" {
            return modifiers.isEmpty ? .cursor : nil
        }
        if head.hasPrefix("snippet:") {
            let key = head.dropFirst("snippet:".count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, modifiers.isEmpty else { return nil }
            return .literal(source)
        }

        guard let token = parseToken(head) else { return nil }
        switch token.command {
        case "clipboard":
            guard let offset = intParameter(token, "offset", default: 0), offset >= 0,
                token.hasOnly(["offset"])
            else { return nil }
            return .clipboard(offset: offset, modifiers: modifiers)
        case "selection", "selectedtext":
            guard token.parameters.isEmpty else { return nil }
            return .selection(modifiers: modifiers)
        // The text typed after an AI command's keyword; see `ExpansionContext.input`.
        case "input":
            guard token.parameters.isEmpty else { return nil }
            return .input(modifiers: modifiers)
        case "uuid":
            guard token.parameters.isEmpty else { return nil }
            return .uuid(modifiers: modifiers)
        case "date", "time", "datetime", "day":
            guard let dateTime = parseDateTime(token) else { return nil }
            return .dateTime(dateTime, modifiers: modifiers)
        case "argument":
            guard let argument = parseArgument(token) else { return nil }
            return .argument(argument, source: source, modifiers: modifiers)
        case "snippet":
            guard let name = token.parameters["name"]?.trimmingCharacters(in: .whitespaces),
                !name.isEmpty, token.hasOnly(["name"]), modifiers.isEmpty
            else { return nil }
            return .literal(source)
        default:
            return nil
        }
    }

    private static func parseDateTime(_ token: ParsedToken) -> DateTimeToken? {
        guard token.hasOnly(["offset", "format", "locale"]) else { return nil }
        let format = token.parameters["format"]
        let localeIdentifier = token.parameters["locale"]
        // Raycast documents these as mutually exclusive; a template asking for both is ambiguous.
        if format != nil, localeIdentifier != nil { return nil }
        if let format, format.isEmpty { return nil }
        if let localeIdentifier, localeIdentifier.isEmpty { return nil }

        var offsets: [DateTimeToken.Offset] = []
        if let raw = token.parameters["offset"] {
            guard let parsed = parseOffsets(raw) else { return nil }
            offsets = parsed
        }

        let kind: DateTimeToken.Kind
        switch token.command {
        case "date": kind = .date
        case "time": kind = .time
        case "datetime": kind = .dateTime
        default: kind = .weekday
        }
        return DateTimeToken(
            kind: kind, offsets: offsets, format: format, localeIdentifier: localeIdentifier)
    }

    /// `"+2y +5M"` / `"-3d"` — signed amounts with a unit suffix, applied in order.
    private static func parseOffsets(_ raw: String) -> [DateTimeToken.Offset]? {
        let pieces = raw.split(whereSeparator: \Character.isWhitespace)
        guard !pieces.isEmpty else { return nil }

        var offsets: [DateTimeToken.Offset] = []
        for piece in pieces {
            guard let unit = piece.last, let component = component(for: unit) else { return nil }
            let amount = piece.dropLast()
            guard let value = Int(amount), !amount.isEmpty else { return nil }
            offsets.append(DateTimeToken.Offset(component: component, value: value))
        }
        return offsets
    }

    private static func component(for unit: Character) -> Calendar.Component? {
        switch unit {
        case "m": return .minute
        case "h": return .hour
        case "d": return .day
        case "M": return .month
        case "y": return .year
        default: return nil
        }
    }

    private static func parseArgument(_ token: ParsedToken) -> ArgumentToken? {
        guard token.hasOnly(["name", "default", "options"]) else { return nil }
        let name = token.parameters["name"]?.trimmingCharacters(in: .whitespaces) ?? "Argument"
        guard !name.isEmpty else { return nil }
        let options = (token.parameters["options"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if token.parameters["options"] != nil, options.isEmpty { return nil }
        return ArgumentToken(defaultValue: token.parameters["default"])
    }

    private static func format(_ token: DateTimeToken, context: ExpansionContext) -> String {
        var date = context.now
        for offset in token.offsets {
            date =
                context.calendar.date(byAdding: offset.component, value: offset.value, to: date)
                ?? date
        }

        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.timeZone = context.timeZone
        formatter.locale = token.localeIdentifier.map(Locale.init(identifier:)) ?? context.locale
        if let format = token.format {
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        switch token.kind {
        case .date:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .time:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .dateTime:
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        case .weekday:
            formatter.dateFormat = "EEEE"
        }
        return formatter.string(from: date)
    }

    // MARK: - Token body parsing

    private struct ParsedToken {
        let command: String
        let parameters: [String: String]

        func hasOnly(_ allowed: Set<String>) -> Bool {
            parameters.keys.allSatisfy(allowed.contains)
        }
    }

    private static func intParameter(
        _ token: ParsedToken, _ key: String, default fallback: Int
    ) -> Int? {
        guard let raw = token.parameters[key] else { return fallback }
        return Int(raw)
    }

    private static func splitOnPipes(_ body: String) -> [String]? {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false

        for character in body {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\" where inQuotes:
                current.append(character)
                escaped = true
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "|" where !inQuotes:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }
        guard !inQuotes, !escaped else { return nil }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts
    }

    private static func parseToken(_ head: String) -> ParsedToken? {
        var remainder = Substring(head)
        remainder = remainder.drop(while: \Character.isWhitespace)
        let command = remainder.prefix { !$0.isWhitespace && $0 != "=" }
        guard !command.isEmpty else { return nil }
        remainder = remainder.dropFirst(command.count)

        var parameters: [String: String] = [:]
        while true {
            remainder = remainder.drop(while: \Character.isWhitespace)
            if remainder.isEmpty { break }

            let key = remainder.prefix { !$0.isWhitespace && $0 != "=" }
            guard !key.isEmpty else { return nil }
            remainder = remainder.dropFirst(key.count)
            remainder = remainder.drop(while: \Character.isWhitespace)
            guard remainder.first == "=" else { return nil }
            remainder = remainder.dropFirst()
            remainder = remainder.drop(while: \Character.isWhitespace)

            let value: String
            if remainder.first == "\"" {
                remainder = remainder.dropFirst()
                guard let decoded = decodeQuoted(&remainder) else { return nil }
                value = decoded
            } else {
                let bare = remainder.prefix { !$0.isWhitespace }
                guard !bare.isEmpty else { return nil }
                remainder = remainder.dropFirst(bare.count)
                value = String(bare)
            }
            guard parameters.updateValue(value, forKey: String(key)) == nil else { return nil }
        }
        return ParsedToken(command: String(command).lowercased(), parameters: parameters)
    }

    /// Consumes a quoted value from `remainder`, leaving it positioned after the closing quote.
    private static func decodeQuoted(_ remainder: inout Substring) -> String? {
        var decoded = ""
        var escaped = false
        while let character = remainder.first {
            remainder = remainder.dropFirst()
            if escaped {
                switch character {
                case "\\": decoded.append("\\")
                case "\"": decoded.append("\"")
                case "n": decoded.append("\n")
                case "r": decoded.append("\r")
                case "t": decoded.append("\t")
                default: return nil
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return decoded
            } else {
                decoded.append(character)
            }
        }
        return nil
    }

}
