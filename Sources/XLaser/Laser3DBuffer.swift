public struct Laser3DShapeRange: Equatable, Sendable {
    public let id: LaserShapeID
    public let start: UInt32
    public internal(set) var count: UInt32
}

public enum Laser3DBufferError: Error, Equatable, Sendable {
    case invalidCapacity
    case missingShape
    case vertexLimitExceeded
}

public struct Laser3DBuffer: Sendable {
    private var shapeStorage: [Laser3DShapeRange] = []
    private var vertexStorage: [Double] = []
    private var modeStorage: [UInt16] = []

    public init() {}

    public var shapeCount: Int { shapeStorage.count }
    public var vertexCount: Int { modeStorage.count }
    public var isEmpty: Bool { shapeStorage.isEmpty }

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
