import Foundation
#if canImport(simd)
import simd
#endif

public struct LaserVertex: Equatable, Sendable {
    public typealias Mode = LaserPointMode

    public var position: SIMD4<Float>
    public var rgba: SIMD4<Float>
    public var mode: Mode

    public init(position: SIMD4<Float>, rgba: SIMD4<Float>, mode: Mode = .normal) {
        self.position = position; self.rgba = rgba; self.mode = mode
    }
    public init(x: Float, y: Float, z: Float = 0, w: Float = 1, rgba: SIMD4<Float> = .one, mode: Mode = .normal) {
        self.init(position: SIMD4<Float>(x, y, z, w), rgba: rgba, mode: mode)
    }

    public var xy: SIMD2<Float> { SIMD2<Float>(position.x, position.y) }
    public var isBlanked: Bool { mode == .blank }

    public func blanked() -> LaserVertex { var v = self; v.rgba = .zero; v.mode = .blank; return v }
    public func dwelling() -> LaserVertex { var v = self; v.mode = .dwell; return v }
#if canImport(simd)
    public func transformed(by matrix: simd_float4x4) -> LaserVertex { var v = self; v.position = matrix * position; return v }
#endif
    public func scaledAlpha(_ alpha: Float) -> LaserVertex { var v = self; v.rgba.w *= alpha; return v }
}
