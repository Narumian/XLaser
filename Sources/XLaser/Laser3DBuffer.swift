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
}

public struct Laser3DBuffer: Sendable, Equatable {
    private var shapeStorage: [Laser3DShapeRange] = []
    private var vertexStorage: [Double] = []
    private var modeStorage: [UInt16] = []

    public init() {}

    public var shapeCount: Int { shapeStorage.count }
    public var vertexCount: Int { modeStorage.count }
    public var isEmpty: Bool { shapeStorage.isEmpty }
    public var shapes: [Laser3DShapeRange] { shapeStorage }

    public func vertex(at index: Int) -> LaserVertex {
        let offset = index * 8
        return LaserVertex(position: SIMD4(vertexStorage[offset], vertexStorage[offset + 1], vertexStorage[offset + 2], vertexStorage[offset + 3]),
                           rgba: SIMD4(vertexStorage[offset + 4], vertexStorage[offset + 5], vertexStorage[offset + 6], vertexStorage[offset + 7]),
                           mode: LaserPointMode(rawValue: modeStorage[index])!)
    }

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
        vertexStorage.append(contentsOf: other.vertexStorage)
        modeStorage.append(contentsOf: other.modeStorage)
    }

    public mutating func reserveCapacity(shapes: Int, vertices: Int) throws {
        guard shapes >= 0, vertices >= 0, UInt64(vertices) <= UInt64(UInt32.max), vertices <= Int.max / 8 else {
            throw Laser3DBufferError.invalidCapacity
        }
        shapeStorage.reserveCapacity(shapes)
        vertexStorage.reserveCapacity(vertices * 8)
        modeStorage.reserveCapacity(vertices)
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        shapeStorage.removeAll(keepingCapacity: keepingCapacity)
        vertexStorage.removeAll(keepingCapacity: keepingCapacity)
        modeStorage.removeAll(keepingCapacity: keepingCapacity)
    }

    public mutating func beginShape(id: LaserShapeID) throws {
        guard let offset = UInt32(exactly: vertexCount) else { throw Laser3DBufferError.vertexLimitExceeded }
        shapeStorage.append(Laser3DShapeRange(id: id, start: offset, count: 0))
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
        shapes: UnsafeBufferPointer<UInt32>, values: UnsafeBufferPointer<Double>, modes: UnsafeBufferPointer<UInt16>
    ) throws {
        guard shapes.count % 3 == 0, modes.count <= Int.max / 8, values.count == modes.count * 8,
              UInt64(modes.count) <= UInt64(UInt32.max) else { throw Laser3DBufferError.invalidShape }
        for mode in modes where LaserPointMode(rawValue: mode) == nil { throw Laser3DBufferError.invalidVertex }
        guard values.allSatisfy(\.isFinite) else { throw Laser3DBufferError.invalidVertex }
        for i in stride(from: 0, to: shapes.count, by: 3) {
            guard let start = Int(exactly: shapes[i + 1]), let count = Int(exactly: shapes[i + 2]),
                  start <= modes.count, count <= modes.count - start else { throw Laser3DBufferError.invalidShape }
        }
        removeAll()
        shapeStorage.reserveCapacity(shapes.count / 3)
        for i in stride(from: 0, to: shapes.count, by: 3) {
            shapeStorage.append(Laser3DShapeRange(id: LaserShapeID(shapes[i]), start: shapes[i + 1], count: shapes[i + 2]))
        }
        vertexStorage.append(contentsOf: values)
        modeStorage.append(contentsOf: modes)
    }

    public func withUnsafeBuffers<Result>(
        _ body: (UnsafeBufferPointer<Laser3DShapeRange>, UnsafeBufferPointer<Double>, UnsafeBufferPointer<UInt16>) throws -> Result
    ) rethrows -> Result {
        try shapeStorage.withUnsafeBufferPointer { shapes in
            try vertexStorage.withUnsafeBufferPointer { vertices in
                try modeStorage.withUnsafeBufferPointer { modes in
                    try body(shapes, vertices, modes)
                }
            }
        }
    }
}
