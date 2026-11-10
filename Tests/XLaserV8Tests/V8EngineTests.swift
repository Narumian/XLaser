import XCTest
import Foundation
import XLaser
import XLaserV8

final class V8EngineTests: XCTestCase {
    private let context = LaserReadContext(time: 0, sampleRate: 30000, frameLength: 1)

    override func setUpWithError() throws { try XCTSkipUnless(V8Engine.isAvailable, "V8 library is not configured") }

    private func buffer(_ shapes: [(UInt32, [LaserVertex])]) throws -> Laser3DBuffer {
        var result = Laser3DBuffer()
        for (id, vertices) in shapes {
            try result.beginShape(id: LaserShapeID(id))
            for vertex in vertices { try result.appendVertex(vertex) }
        }
        return result
    }

    func testDebugAsset() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/RotatingLine.js"), encoding: .utf8)
        let engine: any LaserScriptable = try V8Engine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: .init(time: .pi / 2, sampleRate: 30000, frameLength: 1), inputs: [:], output: &output)
        output.withUnsafeBuffers { shapes, values, _ in XCTAssertEqual(shapes.count, 1); XCTAssertEqual(values[9], 1, accuracy: 1e-12) }
    }

    func testMultipleInputsAndState() throws {
        let engine = try V8Engine(source: "let count = 0; function read(c, inputs, o) { count++; for (const input of Object.values(inputs)) o.addStream(input); o.beginShape(count); }")
        let a = LaserVertex(x: -0.25, y: 0.5, z: 2, w: 0.75, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank)
        let b = LaserVertex(x: 2, y: -1, mode: .dwell)
        let first = try buffer([(91, [a]), (77, [])]), second = try buffer([(42, [b])])
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: ["first": .laser(first), "second": .laser(second)], output: &output)
        XCTAssertEqual(output, try buffer([(91, [a]), (77, []), (42, [b]), (1, [])]))
        try engine.read(context: context, inputs: ["first": .laser(Laser3DBuffer())], output: &output)
        XCTAssertEqual(output, try buffer([(2, [])]))
    }

    func testHostOutputGrowthAndOldViews() throws {
        let source = """
        let oldView;
        function read(c, inputs, output) {
            if (oldView) oldView[0] = 77;
            output.beginShape(17);
            output.addVertex(1, 2, 3, 1, 1, 1, 1, 1, 0);
            const firstView = output.values;
            for (let i = 0; i < 32; i++) output.addVertex(i, 0, 0, 1, 1, 1, 1, 1, 0);
            if (firstView !== output.values) { oldView = firstView; oldView[0] = 99; }
        }
        """
        let engine = try V8Engine(source: source)
        var output = Laser3DBuffer()
        for _ in 0..<2 {
            try engine.read(context: context, inputs: [:], output: &output)
            XCTAssertEqual(output.shapeCount, 1); XCTAssertEqual(output.vertexCount, 33)
            output.withUnsafeBuffers { _, values, _ in XCTAssertEqual(values[0], 1); XCTAssertEqual(values[32 * 8], 31) }
        }
    }

    func testTypedArrayOffset() throws {
        let source = """
        function read(c, inputs, output) {
            output.beginShape(9); output.addVertex(3, 4, 0, 1, 1, 1, 1, 1, 0);
            const values = new Float64Array(16); values.set(output.values.subarray(0, 8), 8);
            output.values = values.subarray(8);
        }
        """
        let engine = try V8Engine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { _, values, _ in XCTAssertEqual(values[0], 3); XCTAssertEqual(values[1], 4) }
    }

    func testNamedLaserAndFloatInputs() throws {
        let asset: any LaserScriptable = try V8Engine(source: "function read(c, inputs, o) { o.addStream(inputs.beam); o.beginShape(2); o.addVertex(inputs.speed, 0, 0, 1, 1, 1, 1, 1, 0); }")
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
        let asset: any LaserScriptable = try V8Engine(source: source)
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
        let engine = try V8Engine(source: "function read(c, inputs, output) { output.addStream(inputs.first); }")
        var output = try buffer([(42, [LaserVertex(x: 0.5, y: -1, mode: .blank)])])
        let expected = output
        try engine.read(context: context, inputs: ["first": .laser(output)], output: &output)
        XCTAssertEqual(output, expected)
    }

    func testErrorsDiscardOutputAndStop() throws {
        let cases: [(String, V8EngineError?)] = [
            ("function read() { throw new Error('broken'); }", nil),
            ("function read(c, i, o) { o.allocate('float64', -1); }", nil),
            ("function read(c, i, o) { o.beginShape(1); o.shapes[1] = 99; }", .invalidOutput),
            ("function read(c, i, o) { o.vertexCount = -1; }", .invalidOutput),
            ("function read(c, i, o) { o.beginShape(1); o.addVertex(0,0,0,1,1,1,1,1,0); o.values[0] = NaN; }", .invalidOutput),
        ]
        for (source, expected) in cases {
            let engine = try V8Engine(source: source)
            var output = try buffer([(1, [LaserVertex(x: 1, y: 1)])])
            XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
                if let expected { XCTAssertEqual(error as? V8EngineError, expected) }
                else if case V8EngineError.javaScript = error {} else { XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertTrue(output.isEmpty)
            XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
                XCTAssertEqual(error as? V8EngineError, .stopped)
            }
        }
    }
}

final class V8AvailabilityTests: XCTestCase {
    func testUnavailableIsReported() throws {
        if !V8Engine.isAvailable {
            XCTAssertThrowsError(try V8Engine(source: "")) { error in XCTAssertEqual(error as? V8EngineError, .unavailable) }
        }
    }
}
