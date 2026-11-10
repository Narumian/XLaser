import XCTest
import XLaser

final class Laser3DBufferTests: XCTestCase {
    func testMappingAndAppendingPreserveShapeRanges() throws {
        var input = Laser3DBuffer()
        try input.beginShape(id: 4)
        try input.appendVertex(LaserVertex(x: 1, y: 2))
        try input.appendVertex(LaserVertex(x: 3, y: 4))
        try input.beginShape(id: 8)
        let mapped = input.mapVertices { vertex, index, count in
            var vertex = vertex
            vertex.position.x += Double(index + count)
            return vertex
        }.mapShapeIDs { LaserShapeID($0.rawValue + 10) }
        var output = input
        try output.append(contentsOf: mapped)
        XCTAssertEqual(output.shapes.map(\.id.rawValue), [4, 8, 14, 18])
        XCTAssertEqual(output.shapes.map(\.start), [0, 2, 2, 4])
        XCTAssertEqual(output.shapes.map(\.count), [2, 0, 2, 0])
        XCTAssertEqual(output.vertex(at: 2).position.x, 3)
        XCTAssertEqual(output.vertex(at: 3).position.x, 6)
        XCTAssertEqual(input.vertex(at: 0).position.x, 1)
    }

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

    func testInvalidReplacementLeavesExistingBufferUnchanged() throws {
        var buffer = Laser3DBuffer()
        try buffer.beginShape(id: 7)
        try buffer.appendVertex(LaserVertex(x: 1, y: 2))
        let expected = buffer
        let shapes: [UInt32] = [1, 0, 2]
        let values: [Double] = [0, 0, 0, 1, 1, 1, 1, 1]
        let modes: [UInt16] = [0]
        XCTAssertThrowsError(try shapes.withUnsafeBufferPointer { shapes in
            try values.withUnsafeBufferPointer { values in
                try modes.withUnsafeBufferPointer { modes in
                    try buffer.replaceContents(shapes: shapes, values: values, modes: modes)
                }
            }
        }) { error in XCTAssertEqual(error as? Laser3DBufferError, .invalidShape) }
        XCTAssertEqual(buffer, expected)
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
