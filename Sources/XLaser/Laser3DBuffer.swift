#if canImport(simd)
import simd
#endif

public struct Laser3DShapeRange: Equatable, Sendable {
    public let id: LaserShapeID
    public let start: UInt32
    public internal(set) var count: UInt32
}

public enum Laser3DBufferError: Error, Equatable, Sendable {
    case invalidCapacity
    case missingShape
    case vertexLimitExceeded
    case invalidShape
    case invalidVertex
    case invalidAttributes
}

#if canImport(simd)
/// A shape's model matrix and tint. The vertices of a shape are in its local space;
/// the host applies the matrix to their positions and multiplies their colors by the
/// tint when it converts the shapes to the output space.
public struct Laser3DShapeAttributes: Equatable, Sendable {
    public var matrix: simd_float4x4
    public var tint: SIMD4<Float>

    public init(matrix: simd_float4x4 = matrix_identity_float4x4, tint: SIMD4<Float> = .one) {
        self.matrix = matrix; self.tint = tint
    }

    public static let identity = Laser3DShapeAttributes()
    public var isIdentity: Bool { self == .identity }
}
#endif

public struct Laser3DBuffer: Sendable, Equatable {
    private var shapeStorage: [Laser3DShapeRange] = []
    private var vertexStorage: [Float] = []
    private var modeStorage: [UInt16] = []
    /// 16 row-major values per shape, parallel to `shapeStorage`.
    private var matrixStorage: [Float] = []
    /// 4 RGBA values per shape, parallel to `shapeStorage`.
    private var tintStorage: [Float] = []

    private static let identityMatrix: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    private static let whiteTint: [Float] = [1, 1, 1, 1]

    public init() {}

    public var shapeCount: Int { shapeStorage.count }
    public var vertexCount: Int { modeStorage.count }
    public var isEmpty: Bool { shapeStorage.isEmpty }
    public var shapes: [Laser3DShapeRange] { shapeStorage }
    /// Interleaved `position4 + rgba4` Float32 values. Returning the Swift
    /// array uses copy-on-write, so readers can retain a snapshot without
    /// eagerly duplicating the vertex payload.
    public var vertexValues: [Float] { vertexStorage }
    /// Per-vertex laser modes, parallel to `vertexValues` in groups of eight.
    public var vertexModes: [UInt16] { modeStorage }

    /// Row-major model matrices, 16 values per shape, parallel to `shapes`.
    public var shapeMatrixValues: [Float] { matrixStorage }
    /// Tints, 4 RGBA values per shape, parallel to `shapes`.
    public var shapeTintValues: [Float] { tintStorage }

    /// Whether any shape has a model matrix other than identity or a tint other than white.
    public var hasShapeAttributes: Bool {
        let identity = Self.identityMatrix
        let matrixDiffers = matrixStorage.withUnsafeBufferPointer { matrices in
            identity.withUnsafeBufferPointer { identity in
                var offset = 0
                while offset < matrices.count {
                    for i in 0..<16 where matrices[offset + i] != identity[i] { return true }
                    offset += 16
                }
                return false
            }
        }
        return matrixDiffers || tintStorage.contains { $0 != 1 }
    }

    public func vertex(at index: Int) -> LaserVertex {
        let offset = index * 8
        return LaserVertex(position: SIMD4(vertexStorage[offset], vertexStorage[offset + 1], vertexStorage[offset + 2], vertexStorage[offset + 3]),
                           rgba: SIMD4(vertexStorage[offset + 4], vertexStorage[offset + 5], vertexStorage[offset + 6], vertexStorage[offset + 7]),
                           mode: LaserPointMode(rawValue: modeStorage[index])!)
    }

    /// Maps every vertex in the shape's own (local) space. A shape's model matrix and tint are not
    /// applied and are kept as they are; call `baked()` first to edit the vertices as placed.
    public func mapVertices(_ transform: (LaserVertex, Int, Int) -> LaserVertex) -> Laser3DBuffer {
        var result = self
        for shape in shapeStorage {
            for index in 0..<Int(shape.count) {
                let vertexIndex = Int(shape.start) + index
                let vertex = transform(vertex(at: vertexIndex), index, Int(shape.count))
                let offset = vertexIndex * 8
                result.vertexStorage[offset] = vertex.position.x; result.vertexStorage[offset + 1] = vertex.position.y
                result.vertexStorage[offset + 2] = vertex.position.z; result.vertexStorage[offset + 3] = vertex.position.w
                result.vertexStorage[offset + 4] = vertex.rgba.x; result.vertexStorage[offset + 5] = vertex.rgba.y
                result.vertexStorage[offset + 6] = vertex.rgba.z; result.vertexStorage[offset + 7] = vertex.rgba.w
                result.modeStorage[vertexIndex] = vertex.mode.rawValue
            }
        }
        return result
    }

    public func mapShapeIDs(_ transform: (LaserShapeID) -> LaserShapeID) -> Laser3DBuffer {
        var result = self
        result.shapeStorage = shapeStorage.map { Laser3DShapeRange(id: transform($0.id), start: $0.start, count: $0.count) }
        return result
    }

    public mutating func append(contentsOf other: Laser3DBuffer) throws {
        guard UInt64(vertexCount) + UInt64(other.vertexCount) <= UInt64(UInt32.max),
              other.vertexCount <= (Int.max / 8) - vertexCount else { throw Laser3DBufferError.vertexLimitExceeded }
        let offset = UInt32(vertexCount)
        shapeStorage.append(contentsOf: other.shapeStorage.map { Laser3DShapeRange(id: $0.id, start: $0.start + offset, count: $0.count) })
        matrixStorage.append(contentsOf: other.matrixStorage)
        tintStorage.append(contentsOf: other.tintStorage)
        vertexStorage.append(contentsOf: other.vertexStorage)
        modeStorage.append(contentsOf: other.modeStorage)
    }

    public mutating func reserveCapacity(shapes: Int, vertices: Int) throws {
        guard shapes >= 0, vertices >= 0, UInt64(vertices) <= UInt64(UInt32.max), vertices <= Int.max / 8 else {
            throw Laser3DBufferError.invalidCapacity
        }
        shapeStorage.reserveCapacity(shapes)
        matrixStorage.reserveCapacity(shapes * 16)
        tintStorage.reserveCapacity(shapes * 4)
        vertexStorage.reserveCapacity(vertices * 8)
        modeStorage.reserveCapacity(vertices)
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        shapeStorage.removeAll(keepingCapacity: keepingCapacity)
        matrixStorage.removeAll(keepingCapacity: keepingCapacity)
        tintStorage.removeAll(keepingCapacity: keepingCapacity)
        vertexStorage.removeAll(keepingCapacity: keepingCapacity)
        modeStorage.removeAll(keepingCapacity: keepingCapacity)
    }

    public mutating func beginShape(id: LaserShapeID) throws {
        guard let offset = UInt32(exactly: vertexCount) else { throw Laser3DBufferError.vertexLimitExceeded }
        shapeStorage.append(Laser3DShapeRange(id: id, start: offset, count: 0))
        matrixStorage.append(contentsOf: Self.identityMatrix)
        tintStorage.append(contentsOf: Self.whiteTint)
    }

    public mutating func appendVertex(_ vertex: LaserVertex) throws {
        guard !shapeStorage.isEmpty else { throw Laser3DBufferError.missingShape }
        guard UInt64(vertexCount) < UInt64(UInt32.max), vertexCount < Int.max / 8 else { throw Laser3DBufferError.vertexLimitExceeded }
        vertexStorage.append(vertex.position.x); vertexStorage.append(vertex.position.y)
        vertexStorage.append(vertex.position.z); vertexStorage.append(vertex.position.w)
        vertexStorage.append(vertex.rgba.x); vertexStorage.append(vertex.rgba.y)
        vertexStorage.append(vertex.rgba.z); vertexStorage.append(vertex.rgba.w)
        modeStorage.append(vertex.mode.rawValue)
        shapeStorage[shapeStorage.count - 1].count += 1
    }

    public mutating func replaceContents(
        shapes: UnsafeBufferPointer<UInt32>, values: UnsafeBufferPointer<Float>, modes: UnsafeBufferPointer<UInt16>
    ) throws {
        try replaceContents(shapes: shapes, values: values, modes: modes, matrices: nil, tints: nil)
    }

    /// Replaces the contents. `matrices` (16 row-major values per shape) and `tints`
    /// (4 per shape), when given, must cover every shape and be finite; omitted ones
    /// are identity and white.
    public mutating func replaceContents(
        shapes: UnsafeBufferPointer<UInt32>, values: UnsafeBufferPointer<Float>, modes: UnsafeBufferPointer<UInt16>,
        matrices: UnsafeBufferPointer<Float>?, tints: UnsafeBufferPointer<Float>?
    ) throws {
        guard shapes.count % 3 == 0, modes.count <= Int.max / 8, values.count == modes.count * 8,
              UInt64(modes.count) <= UInt64(UInt32.max) else { throw Laser3DBufferError.invalidShape }
        let shapeCount = shapes.count / 3
        if let matrices {
            guard matrices.count == shapeCount * 16, matrices.allSatisfy(\.isFinite) else { throw Laser3DBufferError.invalidAttributes }
        }
        if let tints {
            guard tints.count == shapeCount * 4, tints.allSatisfy(\.isFinite) else { throw Laser3DBufferError.invalidAttributes }
        }
        for mode in modes where LaserPointMode(rawValue: mode) == nil { throw Laser3DBufferError.invalidVertex }
        guard values.allSatisfy(\.isFinite) else { throw Laser3DBufferError.invalidVertex }
        for i in stride(from: 0, to: shapes.count, by: 3) {
            guard let start = Int(exactly: shapes[i + 1]), let count = Int(exactly: shapes[i + 2]),
                  start <= modes.count, count <= modes.count - start else { throw Laser3DBufferError.invalidShape }
        }
        removeAll()
        shapeStorage.reserveCapacity(shapeCount)
        for i in stride(from: 0, to: shapes.count, by: 3) {
            shapeStorage.append(Laser3DShapeRange(id: LaserShapeID(shapes[i]), start: shapes[i + 1], count: shapes[i + 2]))
        }
        if let matrices { matrixStorage.append(contentsOf: matrices) }
        else { for _ in 0..<shapeCount { matrixStorage.append(contentsOf: Self.identityMatrix) } }
        if let tints { tintStorage.append(contentsOf: tints) }
        else { for _ in 0..<shapeCount { tintStorage.append(contentsOf: Self.whiteTint) } }
        vertexStorage.append(contentsOf: values)
        modeStorage.append(contentsOf: modes)
    }

    public func withUnsafeBuffers<Result>(
        _ body: (UnsafeBufferPointer<Laser3DShapeRange>, UnsafeBufferPointer<Float>, UnsafeBufferPointer<UInt16>) throws -> Result
    ) rethrows -> Result {
        try shapeStorage.withUnsafeBufferPointer { shapes in
            try vertexStorage.withUnsafeBufferPointer { vertices in
                try modeStorage.withUnsafeBufferPointer { modes in
                    try body(shapes, vertices, modes)
                }
            }
        }
    }

    public func withUnsafeShapeAttributes<Result>(
        _ body: (_ matrices: UnsafeBufferPointer<Float>, _ tints: UnsafeBufferPointer<Float>) throws -> Result
    ) rethrows -> Result {
        try matrixStorage.withUnsafeBufferPointer { matrices in
            try tintStorage.withUnsafeBufferPointer { tints in
                try body(matrices, tints)
            }
        }
    }

    // MARK: Shape attributes

    /// Multiplies every shape's tint by `tint`. Costs one pass over the shapes, not the vertices.
    public func tinted(by tint: SIMD4<Float>) -> Laser3DBuffer {
        var result = self
        for shape in 0..<shapeStorage.count {
            for i in 0..<4 { result.tintStorage[shape * 4 + i] *= tint[i] }
        }
        return result
    }

    /// A buffer with every shape's model matrix applied to its vertex positions and its tint
    /// to its vertex colors, and the matrices and tints reset to identity and white.
    /// Returns `self` when no shape has attributes.
    public func baked() -> Laser3DBuffer {
        guard hasShapeAttributes else { return self }
        var result = self
        for (shapeIndex, shape) in shapeStorage.enumerated() {
            let m = shapeIndex * 16, t = shapeIndex * 4
            for vertex in Int(shape.start)..<(Int(shape.start) + Int(shape.count)) {
                let o = vertex * 8
                let x = vertexStorage[o], y = vertexStorage[o + 1], z = vertexStorage[o + 2], w = vertexStorage[o + 3]
                for row in 0..<4 {
                    let r = m + row * 4
                    result.vertexStorage[o + row] = matrixStorage[r] * x + matrixStorage[r + 1] * y
                        + matrixStorage[r + 2] * z + matrixStorage[r + 3] * w
                }
                for channel in 0..<4 { result.vertexStorage[o + 4 + channel] = vertexStorage[o + 4 + channel] * tintStorage[t + channel] }
            }
        }
        for shape in 0..<shapeStorage.count {
            result.matrixStorage.replaceSubrange(shape * 16..<shape * 16 + 16, with: Self.identityMatrix)
            result.tintStorage.replaceSubrange(shape * 4..<shape * 4 + 4, with: Self.whiteTint)
        }
        return result
    }

#if canImport(simd)
    public func attributes(at shape: Int) -> Laser3DShapeAttributes {
        let m = shape * 16, t = shape * 4
        let rows = (0..<4).map { SIMD4<Float>(matrixStorage[m + $0 * 4], matrixStorage[m + $0 * 4 + 1], matrixStorage[m + $0 * 4 + 2], matrixStorage[m + $0 * 4 + 3]) }
        return Laser3DShapeAttributes(matrix: simd_float4x4(rows: rows),
                                      tint: SIMD4(tintStorage[t], tintStorage[t + 1], tintStorage[t + 2], tintStorage[t + 3]))
    }

    public mutating func setAttributes(_ attributes: Laser3DShapeAttributes, at shape: Int) throws {
        guard shapeStorage.indices.contains(shape) else { throw Laser3DBufferError.invalidShape }
        try Self.validate(attributes)
        write(attributes, at: shape)
    }

    public mutating func beginShape(id: LaserShapeID, attributes: Laser3DShapeAttributes) throws {
        try Self.validate(attributes)
        try beginShape(id: id)
        write(attributes, at: shapeStorage.count - 1)
    }

    /// Applies `matrix` after each shape's own model matrix. Costs one pass over the shapes, not the vertices.
    public func transformed(by matrix: simd_float4x4) -> Laser3DBuffer {
        guard !shapeStorage.isEmpty else { return self }
        var result = self
        let applied: [Float] = (0..<4).flatMap { row in (0..<4).map { column in matrix[column][row] } }   // row-major
        matrixStorage.withUnsafeBufferPointer { old in
            result.matrixStorage.withUnsafeMutableBufferPointer { new in
                applied.withUnsafeBufferPointer { m in
                    for offset in stride(from: 0, to: old.count, by: 16) {
                        for row in 0..<4 {
                            for column in 0..<4 {
                                new[offset + row * 4 + column] = m[row * 4] * old[offset + column]
                                    + m[row * 4 + 1] * old[offset + 4 + column]
                                    + m[row * 4 + 2] * old[offset + 8 + column]
                                    + m[row * 4 + 3] * old[offset + 12 + column]
                            }
                        }
                    }
                }
            }
        }
        return result
    }

    private static func validate(_ attributes: Laser3DShapeAttributes) throws {
        for column in 0..<4 {
            for row in 0..<4 where !attributes.matrix[column][row].isFinite { throw Laser3DBufferError.invalidAttributes }
        }
        for channel in 0..<4 where !attributes.tint[channel].isFinite { throw Laser3DBufferError.invalidAttributes }
    }

    private mutating func write(_ attributes: Laser3DShapeAttributes, at shape: Int) {
        for row in 0..<4 {
            for column in 0..<4 { matrixStorage[shape * 16 + row * 4 + column] = attributes.matrix[column][row] }
        }
        for channel in 0..<4 { tintStorage[shape * 4 + channel] = attributes.tint[channel] }
    }
#endif
}
