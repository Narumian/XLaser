#if canImport(JavaScriptCore)
import XCTest
import Foundation
import XLaserApple
import XLaser

final class JavaScriptCoreEngineTests: XCTestCase {
    private let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: 1)

    private func buffer(_ shapes: [(UInt32, [LaserVertex])]) throws -> Laser3DBuffer {
        var result = Laser3DBuffer()
        for (id, vertices) in shapes {
            try result.beginShape(id: LaserShapeID(id))
            for vertex in vertices { try result.appendVertex(vertex) }
        }
        return result
    }

    func testDebugAssetChangesWithTime() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/RotatingLine.js"), encoding: .utf8)
        let engine = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [], output: &output)
        output.withUnsafeBuffers { shapes, values, _ in
            XCTAssertEqual(shapes.count, 1); XCTAssertEqual(shapes[0].count, 2)
            XCTAssertEqual(values[8], 1, accuracy: 1e-12)
        }
        try engine.read(context: .init(time: .pi / 2, sampleRate: 30000, frameLength: 1), inputs: [], output: &output)
        output.withUnsafeBuffers { _, values, _ in XCTAssertEqual(values[9], 1, accuracy: 1e-12) }
    }

    func testInputThroughEngineProtocol() throws {
        let engine: any LaserScriptEngine = try JavaScriptCoreEngine(source: "function read(c, inputs, o) { for (const shape of inputs[0]) o.addShape(shape.id, shape.vertices); }")
        let input = try buffer([(42, [LaserVertex(x: 0.25, y: 0.5, z: 0.75)])])
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [input], output: &output)
        XCTAssertEqual(output, input)
    }

    func testTypedInputsCombineAndReuse() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, inputs, output) { for (const input of inputs) output.addStream(input); }")
        let a = LaserVertex(x: -0.25, y: 0.5, z: 2, w: 0.75, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank)
        let b = LaserVertex(x: 2, y: -1, mode: .dwell)
        let first = try buffer([(91, [a]), (77, [])]), second = try buffer([(42, [b])])
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [first, second], output: &output)
        XCTAssertEqual(output, try buffer([(91, [a]), (77, []), (42, [b])]))
        try engine.read(context: context, inputs: [Laser3DBuffer(), try buffer([(77, [])])], output: &output)
        XCTAssertEqual(output, try buffer([(77, [])]))
        try engine.read(context: context, inputs: [second, first], output: &output)
        XCTAssertEqual(output, try buffer([(42, [b]), (91, [a]), (77, [])]))
        let many = try buffer((0..<20).map { index in (UInt32(index), (0..<5).map { LaserVertex(x: Double(index), y: Double($0)) }) })
        try engine.read(context: context, inputs: [many], output: &output)
        XCTAssertEqual(output, many)
    }

    func testGrowthAndOffset() throws {
        let source = """
        function read(c, inputs, output) {
            for (let shape = 0; shape < 7; shape++) {
                output.beginShape(shape + 1);
                for (let i = 0; i < 5; i++) output.addVertex(i, shape, 2, 1, 0.1, 0.2, 0.3, 0.4, 2);
            }
            const values = new Float64Array(output.values.length + 8);
            values.set(output.values, 8);
            output.values = values.subarray(8);
        }
        """
        let engine = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        for _ in 0..<2 {
            try engine.read(context: context, inputs: [], output: &output)
            XCTAssertEqual(output.shapeCount, 7); XCTAssertEqual(output.vertexCount, 35)
            output.withUnsafeBuffers { shapes, values, modes in
                XCTAssertEqual(shapes[6].count, 5); XCTAssertEqual(values[34 * 8], 4)
                XCTAssertEqual(values[34 * 8 + 1], 6); XCTAssertEqual(modes[34], LaserPointMode.blank.rawValue)
            }
        }
    }

    func testOutputCanBeReusedAsNextInput() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, inputs, output) { output.addStream(inputs[0]); }")
        var output = try buffer([(42, [LaserVertex(x: 0.5, y: -1, mode: .blank)])])
        let expected = output
        try engine.read(context: context, inputs: [output], output: &output)
        XCTAssertEqual(output, expected)
    }

    func testErrorsDiscardOutputAndStop() throws {
        let cases: [(String, JavaScriptCoreEngineError?)] = [
            ("function read() { throw new Error('broken'); }", nil),
            ("function read(c, i, o) { o.beginShape(1); o.shapes[1] = 99; }", .invalidOutput),
            ("function read(c, i, o) { o.beginShape(1); o.addVertex(0,0,0,1,1,1,1,1,0); o.values[0] = NaN; }", .invalidOutput),
        ]
        for (source, expected) in cases {
            let engine = try JavaScriptCoreEngine(source: source)
            var output = try buffer([(1, [LaserVertex(x: 1, y: 1)])])
            XCTAssertThrowsError(try engine.read(context: context, inputs: [], output: &output)) { error in
                if let expected { XCTAssertEqual(error as? JavaScriptCoreEngineError, expected) }
                else if case JavaScriptCoreEngineError.javaScript = error {} else { XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertTrue(output.isEmpty)
            XCTAssertThrowsError(try engine.read(context: context, inputs: [], output: &output)) { error in
                XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
            }
        }
    }
}
#endif
