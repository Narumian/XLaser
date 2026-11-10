import XCTest
import XLaser

final class Laser3DBufferTests: XCTestCase {
    func testShapesAndVerticesUseContiguousBuffers() throws {
        var buffer = Laser3DBuffer()
        try buffer.reserveCapacity(shapes: 3, vertices: 2)
        try buffer.beginShape(id: 42)
        try buffer.appendVertex(LaserVertex(x: 0.5, y: -1, z: 2, w: 0.5, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank))
        try buffer.beginShape(id: 99)
        try buffer.beginShape(id: 7)
        try buffer.appendVertex(LaserVertex(x: -2, y: 3, mode: .dwell))
        XCTAssertEqual(buffer.shapeCount, 3)
        XCTAssertEqual(buffer.vertexCount, 2)
        buffer.withUnsafeBuffers { shapes, vertices, modes in
            XCTAssertEqual(shapes.map(\.id.rawValue), [42, 99, 7])
            XCTAssertEqual(shapes.map(\.start), [0, 1, 1])
            XCTAssertEqual(shapes.map(\.count), [1, 0, 1])
            XCTAssertEqual(Array(vertices), [0.5, -1, 2, 0.5, 0.1, 0.2, 0.3, 0.4, -2, 3, 0, 1, 1, 1, 1, 1])
            XCTAssertEqual(Array(modes), [LaserPointMode.blank.rawValue, LaserPointMode.dwell.rawValue])
        }
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.vertexCount, 0)
        try buffer.beginShape(id: 8)
        try buffer.appendVertex(LaserVertex(x: 3, y: 4))
        buffer.withUnsafeBuffers { shapes, vertices, _ in
            XCTAssertEqual(shapes[0].start, 0)
            XCTAssertEqual(vertices[0], 3)
        }
    }

    func testInvalidOperationsDoNotChangeBuffer() throws {
        var buffer = Laser3DBuffer()
        XCTAssertThrowsError(try buffer.appendVertex(LaserVertex(x: 0, y: 0))) { error in
            XCTAssertEqual(error as? Laser3DBufferError, .missingShape)
        }
        XCTAssertThrowsError(try buffer.reserveCapacity(shapes: 0, vertices: -1)) { error in
            XCTAssertEqual(error as? Laser3DBufferError, .invalidCapacity)
        }
        XCTAssertEqual(buffer.shapeCount, 0)
        XCTAssertEqual(buffer.vertexCount, 0)
    }

    func testStreamReplacesOutput() throws {
        struct Source: Laser3DStream {
            func read(into output: inout Laser3DBuffer) {
                output.removeAll()
                try? output.beginShape(id: 5)
                try? output.appendVertex(LaserVertex(x: 1, y: 2))
            }
        }
        var buffer = Laser3DBuffer()
        var stream: any Laser3DStream = Source()
        stream.read(into: &buffer)
        stream.read(into: &buffer)
        XCTAssertEqual(buffer.shapeCount, 1)
        XCTAssertEqual(buffer.vertexCount, 1)
    }

    func testCopiesAreIndependent() throws {
        var first = Laser3DBuffer()
        try first.beginShape(id: 1)
        try first.appendVertex(LaserVertex(x: 0, y: 0))
        var second = first
        try second.appendVertex(LaserVertex(x: 1, y: 1))
        XCTAssertEqual(first.vertexCount, 1)
        XCTAssertEqual(second.vertexCount, 2)
    }
}
