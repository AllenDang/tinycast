import Foundation

/// A calculator value: either a scalar or a 2/3/4-component vector.
/// Arithmetic between mismatched dimensions is an error (returns nil).
enum CalcValue: Equatable, Sendable {
    case scalar(Double)
    case vec2(Double, Double)
    case vec3(Double, Double, Double)
    case vec4(Double, Double, Double, Double)

    var dimension: Int {
        switch self {
        case .scalar: return 1
        case .vec2: return 2
        case .vec3: return 3
        case .vec4: return 4
        }
    }

    /// The scalar value when this is a scalar; nil for vectors.
    var asScalar: Double? {
        if case .scalar(let v) = self { return v }
        return nil
    }

    /// Element-wise negate.
    static prefix func - (value: CalcValue) -> CalcValue {
        switch value {
        case .scalar(let v): return .scalar(-v)
        case .vec2(let x, let y): return .vec2(-x, -y)
        case .vec3(let x, let y, let z): return .vec3(-x, -y, -z)
        case .vec4(let x, let y, let z, let w): return .vec4(-x, -y, -z, -w)
        }
    }

    /// Element-wise add. Dimensions must match, or one side must be scalar (broadcast).
    static func + (lhs: CalcValue, rhs: CalcValue) -> CalcValue? {
        switch (lhs, rhs) {
        case (.scalar(let a), .scalar(let b)): return .scalar(a + b)
        case (.scalar(let a), let vec): return vec.scaled(by: 1).map { addScalar(a, to: $0) }
        case (let vec, .scalar(let b)): return addScalar(b, to: vec)
        case (.vec2(let ax, let ay), .vec2(let bx, let by)): return .vec2(ax + bx, ay + by)
        case (.vec3(let ax, let ay, let az), .vec3(let bx, let by, let bz)): return .vec3(ax + bx, ay + by, az + bz)
        case (.vec4(let ax, let ay, let az, let aw), .vec4(let bx, let by, let bz, let bw)):
            return .vec4(ax + bx, ay + by, az + bz, aw + bw)
        default: return nil
        }
    }

    /// Element-wise subtract. Dimensions must match, or one side must be scalar (broadcast).
    static func - (lhs: CalcValue, rhs: CalcValue) -> CalcValue? {
        switch (lhs, rhs) {
        case (.scalar(let a), .scalar(let b)): return .scalar(a - b)
        case (.scalar(let a), let vec): return addScalar(a, to: -vec)
        case (let vec, .scalar(let b)): return addScalar(-b, to: vec)
        case (.vec2(let ax, let ay), .vec2(let bx, let by)): return .vec2(ax - bx, ay - by)
        case (.vec3(let ax, let ay, let az), .vec3(let bx, let by, let bz)): return .vec3(ax - bx, ay - by, az - bz)
        case (.vec4(let ax, let ay, let az, let aw), .vec4(let bx, let by, let bz, let bw)):
            return .vec4(ax - bx, ay - by, az - bz, aw - bw)
        default: return nil
        }
    }

    /// Add a scalar to each element of a vector.
    private static func addScalar(_ s: Double, to vec: CalcValue) -> CalcValue {
        switch vec {
        case .scalar(let v): return .scalar(v + s)
        case .vec2(let x, let y): return .vec2(x + s, y + s)
        case .vec3(let x, let y, let z): return .vec3(x + s, y + s, z + s)
        case .vec4(let x, let y, let z, let w): return .vec4(x + s, y + s, z + s, w + s)
        }
    }

    /// Element-wise multiply (Hadamard product for vectors). Scalar × vector broadcasts.
    static func * (lhs: CalcValue, rhs: CalcValue) -> CalcValue? {
        switch (lhs, rhs) {
        case (.scalar(let a), .scalar(let b)): return .scalar(a * b)
        case (.scalar(let a), let vec): return vec.scaled(by: a)
        case (let vec, .scalar(let b)): return vec.scaled(by: b)
        case (.vec2(let ax, let ay), .vec2(let bx, let by)): return .vec2(ax * bx, ay * by)
        case (.vec3(let ax, let ay, let az), .vec3(let bx, let by, let bz)): return .vec3(ax * bx, ay * by, az * bz)
        case (.vec4(let ax, let ay, let az, let aw), .vec4(let bx, let by, let bz, let bw)):
            return .vec4(ax * bx, ay * by, az * bz, aw * bw)
        default: return nil
        }
    }

    /// Element-wise divide. Scalar / vector broadcasts; vector / scalar scales.
    static func / (lhs: CalcValue, rhs: CalcValue) -> CalcValue? {
        switch (lhs, rhs) {
        case (.scalar(let a), .scalar(let b)):
            guard !b.isZero else { return nil }
            return .scalar(a / b)
        case (.scalar(let a), let vec):
            // Scalar divided by each element
            switch vec {
            case .scalar: return nil // handled above
            case .vec2(let x, let y):
                guard !x.isZero, !y.isZero else { return nil }
                return .vec2(a / x, a / y)
            case .vec3(let x, let y, let z):
                guard !x.isZero, !y.isZero, !z.isZero else { return nil }
                return .vec3(a / x, a / y, a / z)
            case .vec4(let x, let y, let z, let w):
                guard !x.isZero, !y.isZero, !z.isZero, !w.isZero else { return nil }
                return .vec4(a / x, a / y, a / z, a / w)
            }
        case (let vec, .scalar(let b)):
            guard !b.isZero else { return nil }
            return vec.scaled(by: 1.0 / b)
        case (.vec2(let ax, let ay), .vec2(let bx, let by)):
            guard !bx.isZero, !by.isZero else { return nil }
            return .vec2(ax / bx, ay / by)
        case (.vec3(let ax, let ay, let az), .vec3(let bx, let by, let bz)):
            guard !bx.isZero, !by.isZero, !bz.isZero else { return nil }
            return .vec3(ax / bx, ay / by, az / bz)
        case (.vec4(let ax, let ay, let az, let aw), .vec4(let bx, let by, let bz, let bw)):
            guard !bx.isZero, !by.isZero, !bz.isZero, !bw.isZero else { return nil }
            return .vec4(ax / bx, ay / by, az / bz, aw / bw)
        default: return nil
        }
    }

    /// Scale by a scalar.
    func scaled(by factor: Double) -> CalcValue? {
        switch self {
        case .scalar(let v): return .scalar(v * factor)
        case .vec2(let x, let y): return .vec2(x * factor, y * factor)
        case .vec3(let x, let y, let z): return .vec3(x * factor, y * factor, z * factor)
        case .vec4(let x, let y, let z, let w): return .vec4(x * factor, y * factor, z * factor, w * factor)
        }
    }

    /// Dot product. Both must be vectors of the same dimension.
    func dot(_ other: CalcValue) -> Double? {
        switch (self, other) {
        case (.vec2(let ax, let ay), .vec2(let bx, let by)): return ax * bx + ay * by
        case (.vec3(let ax, let ay, let az), .vec3(let bx, let by, let bz)): return ax * bx + ay * by + az * bz
        case (.vec4(let ax, let ay, let az, let aw), .vec4(let bx, let by, let bz, let bw)):
            return ax * bx + ay * by + az * bz + aw * bw
        default: return nil
        }
    }

    /// Cross product. Both must be vec3.
    func cross(_ other: CalcValue) -> CalcValue? {
        guard case .vec3(let ax, let ay, let az) = self,
              case .vec3(let bx, let by, let bz) = other
        else { return nil }
        return .vec3(
            ay * bz - az * by,
            az * bx - ax * bz,
            ax * by - ay * bx
        )
    }

    /// Magnitude.
    var length: Double {
        switch self {
        case .scalar(let v): return abs(v)
        case .vec2(let x, let y): return sqrt(x * x + y * y)
        case .vec3(let x, let y, let z): return sqrt(x * x + y * y + z * z)
        case .vec4(let x, let y, let z, let w): return sqrt(x * x + y * y + z * z + w * w)
        }
    }

    /// Unit vector in the same direction, or nil for zero-length.
    func normalized() -> CalcValue? {
        let len = length
        guard len > 1e-30 else { return nil }
        return scaled(by: 1.0 / len)
    }
}
