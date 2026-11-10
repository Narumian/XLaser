import Foundation
#if canImport(simd)
import simd
#endif

public struct LaserShapeID: Hashable, Sendable, ExpressibleByIntegerLiteral {
    public var rawValue: UInt32
    public init(_ rawValue: UInt32) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt32) { rawValue = value }
}

public struct LaserVertex: Equatable, Sendable {
    public typealias Mode = LaserPointMode

    public var position: SIMD4<Double>
    public var rgba: SIMD4<Double>
    public var mode: Mode

    public init(position: SIMD4<Double>, rgba: SIMD4<Double>, mode: Mode = .normal) {
        self.position = position; self.rgba = rgba; self.mode = mode
    }
    public init(x: Double, y: Double, z: Double = 0, w: Double = 1, rgba: SIMD4<Double> = .one, mode: Mode = .normal) {
        self.init(position: SIMD4<Double>(x, y, z, w), rgba: rgba, mode: mode)
    }

    public var xy: SIMD2<Double> { SIMD2<Double>(position.x, position.y) }
    public var isBlanked: Bool { mode == .blank }

    public func blanked() -> LaserVertex { var v = self; v.rgba = .zero; v.mode = .blank; return v }
    public func dwelling() -> LaserVertex { var v = self; v.mode = .dwell; return v }
#if canImport(simd)
    public func transformed(by matrix: simd_double4x4) -> LaserVertex { var v = self; v.position = matrix * position; return v }
#endif
    public func scaledAlpha(_ alpha: Double) -> LaserVertex { var v = self; v.rgba.w *= alpha; return v }
}

public protocol Laser3DStream: Sendable {
    mutating func read(into output: inout Laser3DBuffer)
}
