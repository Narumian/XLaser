#if canImport(JavaScriptCore)
import XCTest
import Foundation
import XLaserApple
import XLaser

final class JavaScriptCoreEngineTests: XCTestCase {
    private let context = LaserReadContext(time: 0, sampleRate: 30000, frameLength: 1)

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
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { shapes, values, _ in
            XCTAssertEqual(shapes.count, 1); XCTAssertEqual(shapes[0].count, 2)
            XCTAssertEqual(values[8], 1, accuracy: 1e-12)
        }
        try engine.read(context: .init(time: .pi / 2, sampleRate: 30000, frameLength: 1), inputs: [:], output: &output)
        output.withUnsafeBuffers { _, values, _ in XCTAssertEqual(values[9], 1, accuracy: 1e-12) }
    }

    func testInputThroughEngineProtocol() throws {
        let engine: any LaserScriptable = try JavaScriptCoreEngine(source: "function read(c, inputs, o) { for (const shape of inputs.first) o.addShape(shape.id, shape.vertices); }")
        let input = try buffer([(42, [LaserVertex(x: 0.25, y: 0.5, z: 0.75)])])
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: ["first": .laser(input)], output: &output)
        XCTAssertEqual(output, input)
    }

    func testTypedInputsCombineAndReuse() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, inputs, output) { for (const input of Object.values(inputs)) output.addStream(input); }")
        let a = LaserVertex(x: -0.25, y: 0.5, z: 2, w: 0.75, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank)
        let b = LaserVertex(x: 2, y: -1, mode: .dwell)
        let first = try buffer([(91, [a]), (77, [])]), second = try buffer([(42, [b])])
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: ["first": .laser(first), "second": .laser(second)], output: &output)
        XCTAssertEqual(output, try buffer([(91, [a]), (77, []), (42, [b])]))
        try engine.read(context: context, inputs: ["first": .laser(Laser3DBuffer()), "second": .laser(try buffer([(77, [])]))], output: &output)
        XCTAssertEqual(output, try buffer([(77, [])]))
        try engine.read(context: context, inputs: ["first": .laser(second), "second": .laser(first)], output: &output)
        XCTAssertEqual(output, try buffer([(42, [b]), (91, [a]), (77, [])]))
        let many = try buffer((0..<20).map { index in (UInt32(index), (0..<5).map { LaserVertex(x: Double(index), y: Double($0)) }) })
        try engine.read(context: context, inputs: ["first": .laser(many)], output: &output)
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
            try engine.read(context: context, inputs: [:], output: &output)
            XCTAssertEqual(output.shapeCount, 7); XCTAssertEqual(output.vertexCount, 35)
            output.withUnsafeBuffers { shapes, values, modes in
                XCTAssertEqual(shapes[6].count, 5); XCTAssertEqual(values[34 * 8], 4)
                XCTAssertEqual(values[34 * 8 + 1], 6); XCTAssertEqual(modes[34], LaserPointMode.blank.rawValue)
            }
        }
    }

    func testNamedLaserAndFloatInputs() throws {
        let asset: any LaserScriptable = try JavaScriptCoreEngine(source: "function read(c, inputs, o) { o.addStream(inputs.beam); o.beginShape(2); o.addVertex(inputs.speed, 0, 0, 1, 1, 1, 1, 1, 0); }")
        let input = try buffer([(1, [LaserVertex(x: 0.5, y: 0)])])
        var output = Laser3DBuffer()
        try asset.read(context: context, inputs: ["beam": .laser(input), "speed": .float(3)], output: &output)
        output.withUnsafeBuffers { shapes, values, _ in
            XCTAssertEqual(shapes.count, 2)
            XCTAssertEqual(values[0], 0.5)
            XCTAssertEqual(values[8], 3)
        }
    }

    func testDescriptorAndSpeedInput() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/RotatingLine.js"), encoding: .utf8)
        let asset: any LaserScriptable = try JavaScriptCoreEngine(source: source)
        XCTAssertEqual(asset.descriptor.name, "Debug Rotating Line")
        XCTAssertEqual(asset.descriptor.inputs, [.init(name: "speed", type: "float", defaultValue: .number(1))])
        var output = Laser3DBuffer()
        for (time, speed, angle) in [(0.0, 1.0, 0.0), (1.0, 1.0, 1.0), (1.0, 2.0, 1.0), (2.0, 2.0, 3.0)] {
            try asset.read(context: .init(time: time, sampleRate: 30000, frameLength: 2), inputs: ["speed": .float(speed)], output: &output)
            output.withUnsafeBuffers { _, values, _ in
                XCTAssertEqual(values[8], cos(angle), accuracy: 1e-12)
                XCTAssertEqual(values[9], sin(angle), accuracy: 1e-12)
            }
        }
    }

    func testOutputCanBeReusedAsNextInput() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, inputs, output) { output.addStream(inputs.first); }")
        var output = try buffer([(42, [LaserVertex(x: 0.5, y: -1, mode: .blank)])])
        let expected = output
        try engine.read(context: context, inputs: ["first": .laser(output)], output: &output)
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
            XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
                if let expected { XCTAssertEqual(error as? JavaScriptCoreEngineError, expected) }
                else if case JavaScriptCoreEngineError.javaScript = error {} else { XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertTrue(output.isEmpty)
            XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
                XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
            }
        }
    }
}
#endif
