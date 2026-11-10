import XCTest
import Foundation
import XLaser
import XLaserV8

final class V8EngineTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(V8Engine.isAvailable, "V8 library is not configured")
    }

    func testDebugAsset() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/RotatingLine.js"), encoding: .utf8)
        let engine: any LaserScriptEngine = try V8Engine(source: source)
        let result = try engine.read(context: .init(time: .pi / 2, sampleRate: 30000, frameLength: 1000), inputs: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].vertices[1].position.y, 1, accuracy: 1e-12)
    }

    func testTypedInputsAndState() throws {
        let engine = try V8Engine(source: "let count = 0; function read(c, inputs, o) { count++; o.addStream(inputs[0]); o.beginShape(count); }")
        let input = Laser3DShape(id: 42, vertices: [LaserVertex(x: 0.5, y: -1, mode: .blank)])
        let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: 1)
        let first = try engine.read(context: context, inputs: [[input]])
        let second = try engine.read(context: context, inputs: [[input]])
        XCTAssertEqual(first.first, input)
        XCTAssertEqual(first.last?.id.rawValue, 1)
        XCTAssertEqual(second.last?.id.rawValue, 2)
    }

    func testInvalidOutputStopsAsset() throws {
        let engine = try V8Engine(source: "function read(c, i, o) { o.beginShape(1); o.shapes[1] = 99; }")
        let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: 1)
        XCTAssertThrowsError(try engine.read(context: context, inputs: [])) { error in
            XCTAssertEqual(error as? V8EngineError, .invalidOutput)
        }
        XCTAssertThrowsError(try engine.read(context: context, inputs: [])) { error in
            XCTAssertEqual(error as? V8EngineError, .stopped)
        }
    }

    func testRejectsInvalidCounts() throws {
        let engine = try V8Engine(source: "function read(c, i, o) { o.vertexCount = -1; }")
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1), inputs: [])) { error in
            XCTAssertEqual(error as? V8EngineError, .invalidOutput)
        }
    }

    func testMultipleInputsAndEmptyShapes() throws {
        let engine = try V8Engine(source: "function read(c, inputs, output) { for (const input of inputs) output.addStream(input); }")
        let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: 1)
        let first = Laser3DShape(id: 91, vertices: [LaserVertex(x: -0.25, y: 0.5, z: 2, w: 0.75, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank)])
        let empty = Laser3DShape(id: 77, vertices: [])
        let last = Laser3DShape(id: 42, vertices: [LaserVertex(x: 2, y: -1, mode: .dwell)])
        XCTAssertEqual(try engine.read(context: context, inputs: [[first, empty], [last]]), [first, empty, last])
        XCTAssertEqual(try engine.read(context: context, inputs: [[], [empty]]), [empty])
        XCTAssertEqual(try engine.read(context: context, inputs: []), [])
    }

    func testTypedArrayOffset() throws {
        let source = """
        function read(c, inputs, output) {
            output.beginShape(9);
            output.addVertex(3, 4, 0, 1, 1, 1, 1, 1, 0);
            const values = new Float64Array(16);
            values.set(output.values.subarray(0, 8), 8);
            output.values = values.subarray(8);
        }
        """
        let engine = try V8Engine(source: source)
        let output = try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1), inputs: [])
        XCTAssertEqual(output[0].vertices[0].position.x, 3)
        XCTAssertEqual(output[0].vertices[0].position.y, 4)
    }

    func testRejectsNonFiniteValues() throws {
        let engine = try V8Engine(source: "function read(c, i, o) { o.beginShape(1); o.addVertex(0,0,0,1,1,1,1,1,0); o.values[0] = NaN; }")
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1), inputs: [])) { error in
            XCTAssertEqual(error as? V8EngineError, .invalidOutput)
        }
    }

    func testExceptionStopsAsset() throws {
        let engine = try V8Engine(source: "function read() { throw new Error('broken'); }")
        let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: 1)
        XCTAssertThrowsError(try engine.read(context: context, inputs: [])) { error in
            guard case V8EngineError.javaScript(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("broken"))
        }
        XCTAssertThrowsError(try engine.read(context: context, inputs: [])) { error in
            XCTAssertEqual(error as? V8EngineError, .stopped)
        }
    }
}

final class V8AvailabilityTests: XCTestCase {
    func testUnavailableIsReported() throws {
        if !V8Engine.isAvailable {
            XCTAssertThrowsError(try V8Engine(source: "")) { error in
                XCTAssertEqual(error as? V8EngineError, .unavailable)
            }
        }
    }
}
