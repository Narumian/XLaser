import XCTest
import simd
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
            vertex.position.x += Float(index + count)
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
        let values: [Float] = [0, 0, 0, 1, 1, 1, 1, 1]
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

    // MARK: Shape attributes

    private func translation(_ x: Float, _ y: Float, _ z: Float = 0) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }

    func testShapesDefaultToIdentityAndWhite() throws {
        var buffer = Laser3DBuffer()
        try buffer.beginShape(id: 1)
        try buffer.appendVertex(LaserVertex(x: 1, y: 2))
        XCTAssertFalse(buffer.hasShapeAttributes)
        XCTAssertEqual(buffer.attributes(at: 0), .identity)
        XCTAssertEqual(buffer.shapeMatrixValues, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        XCTAssertEqual(buffer.shapeTintValues, [1, 1, 1, 1])
        XCTAssertEqual(buffer.baked(), buffer)
    }

    func testAttributesStayWithTheirShapeThroughAppendAndMapping() throws {
        var first = Laser3DBuffer()
        try first.beginShape(id: 1, attributes: Laser3DShapeAttributes(matrix: translation(1, 0), tint: SIMD4(1, 0.5, 1, 1)))
        try first.appendVertex(LaserVertex(x: 0, y: 0))
        var second = Laser3DBuffer()
        try second.beginShape(id: 2)
        try second.appendVertex(LaserVertex(x: 0, y: 0))
        try second.beginShape(id: 3, attributes: Laser3DShapeAttributes(matrix: translation(0, 5)))
        try second.appendVertex(LaserVertex(x: 0, y: 0))

        var joined = first
        try joined.append(contentsOf: second.mapShapeIDs { LaserShapeID($0.rawValue + 10) }.mapVertices { vertex, _, _ in vertex })
        XCTAssertEqual(joined.shapes.map(\.id.rawValue), [1, 12, 13])
        XCTAssertEqual(joined.attributes(at: 0).matrix, translation(1, 0))
        XCTAssertEqual(joined.attributes(at: 0).tint, SIMD4(1, 0.5, 1, 1))
        XCTAssertEqual(joined.attributes(at: 1), .identity)
        XCTAssertEqual(joined.attributes(at: 2).matrix, translation(0, 5))
        XCTAssertEqual(joined.vertex(at: 0).position, SIMD4(0, 0, 0, 1), "vertices stay in local space")
    }

    func testBakedAppliesMatrixAndTintAndResetsThem() throws {
        var buffer = Laser3DBuffer()
        try buffer.beginShape(id: 1, attributes: Laser3DShapeAttributes(matrix: translation(2, 3), tint: SIMD4(0.5, 1, 1, 0.5)))
        try buffer.appendVertex(LaserVertex(x: 1, y: 1, rgba: SIMD4(1, 1, 1, 1)))
        try buffer.beginShape(id: 2)
        try buffer.appendVertex(LaserVertex(x: 1, y: 1))
        let baked = buffer.baked()
        XCTAssertEqual(baked.vertex(at: 0).position, SIMD4(3, 4, 0, 1))
        XCTAssertEqual(baked.vertex(at: 0).rgba, SIMD4(0.5, 1, 1, 0.5))
        XCTAssertEqual(baked.vertex(at: 1).position, SIMD4(1, 1, 0, 1))
        XCTAssertFalse(baked.hasShapeAttributes)
        XCTAssertEqual(baked.shapes, buffer.shapes)
    }

    func testTransformedPremultipliesWithoutTouchingVertices() throws {
        var buffer = Laser3DBuffer()
        let scale = simd_float4x4(diagonal: SIMD4(2, 2, 2, 1))
        try buffer.beginShape(id: 1, attributes: Laser3DShapeAttributes(matrix: scale))
        try buffer.appendVertex(LaserVertex(x: 1, y: 0))
        let moved = buffer.transformed(by: translation(1, 0))
        XCTAssertEqual(moved.vertex(at: 0), buffer.vertex(at: 0))
        // translate after scale: (1 * 2) + 1
        XCTAssertEqual(moved.baked().vertex(at: 0).position, SIMD4(3, 0, 0, 1))
        XCTAssertEqual(buffer.tinted(by: SIMD4(0.5, 0.5, 0.5, 1)).attributes(at: 0).tint, SIMD4(0.5, 0.5, 0.5, 1))
    }

    func testSettingAttributesRejectsNonFiniteValuesAndBadIndices() throws {
        var buffer = Laser3DBuffer()
        try buffer.beginShape(id: 1)
        var bad = Laser3DShapeAttributes()
        bad.matrix.columns.0.x = .nan
        XCTAssertThrowsError(try buffer.setAttributes(bad, at: 0)) { XCTAssertEqual($0 as? Laser3DBufferError, .invalidAttributes) }
        XCTAssertThrowsError(try buffer.beginShape(id: 2, attributes: Laser3DShapeAttributes(tint: SIMD4(1, .infinity, 1, 1))))
        XCTAssertThrowsError(try buffer.setAttributes(.identity, at: 5)) { XCTAssertEqual($0 as? Laser3DBufferError, .invalidShape) }
        XCTAssertEqual(buffer.shapeCount, 1, "a rejected beginShape leaves the buffer unchanged")
    }

    func testReplaceContentsCarriesAttributesAndValidatesThem() throws {
        var buffer = Laser3DBuffer()
        let shapes: [UInt32] = [7, 0, 1, 8, 1, 1]
        let values: [Float] = [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1]
        let modes: [UInt16] = [0, 0]
        var matrices = [Float](repeating: 0, count: 32)
        for shape in 0..<2 { for i in 0..<4 { matrices[shape * 16 + i * 5] = 1 } }
        matrices[16 + 3] = 4
        let tints: [Float] = [1, 1, 1, 1, 0.25, 1, 1, 1]
        try shapes.withUnsafeBufferPointer { s in try values.withUnsafeBufferPointer { v in try modes.withUnsafeBufferPointer { m in
            try matrices.withUnsafeBufferPointer { mat in try tints.withUnsafeBufferPointer { t in
                try buffer.replaceContents(shapes: s, values: v, modes: m, matrices: mat, tints: t)
            } }
        } } }
        XCTAssertEqual(buffer.attributes(at: 1).matrix, translation(4, 0))
        XCTAssertEqual(buffer.attributes(at: 1).tint.x, 0.25)
        XCTAssertEqual(buffer.attributes(at: 0), .identity)

        var short = [Float](repeating: 1, count: 16)
        XCTAssertThrowsError(try shapes.withUnsafeBufferPointer { s in try values.withUnsafeBufferPointer { v in try modes.withUnsafeBufferPointer { m in
            try short.withUnsafeBufferPointer { mat in try buffer.replaceContents(shapes: s, values: v, modes: m, matrices: mat, tints: nil) }
        } } }) { XCTAssertEqual($0 as? Laser3DBufferError, .invalidAttributes) }
        short = []
        // the 3-argument form resets to identity and white
        try shapes.withUnsafeBufferPointer { s in try values.withUnsafeBufferPointer { v in try modes.withUnsafeBufferPointer { m in
            try buffer.replaceContents(shapes: s, values: v, modes: m)
        } } }
        XCTAssertFalse(buffer.hasShapeAttributes)
    }
}
