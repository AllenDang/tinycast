import Foundation

struct DialogField: Equatable, Sendable {
    let name: String
    let options: [String]
}

@MainActor
@Observable
final class DialogFieldState {
    let fields: [DialogField]
    var entries: [String: String]

    init(fields: [DialogField]) {
        self.fields = fields
        entries = fields.reduce(into: [:]) { values, field in
            values[field.name] = field.options.first ?? ""
        }
    }

    var collected: [String: String] { entries }
}

struct DialogAction {
    enum Role {
        case standard
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .standard
}

enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}

struct DialogRequest {
    let title: String
    var message: String?
    /// The subject's own glyph, resolved through `SymbolImage` so a bundled asset name works too.
    let symbol: String
    var tone: DialogTone = .neutral
    var actions: [DialogAction]
    /// The button ↵ fires, normally the primary action.
    var defaultIndex: Int
    var cancelIndex: Int
    /// Set only by the Set Volume prompt; the slider binds to it and the caller reads the result.
    var volume: VolumeState?
    var fields: DialogFieldState?
}
