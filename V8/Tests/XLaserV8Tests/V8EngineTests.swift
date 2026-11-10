import XCTest
import Foundation
import XLaser
import XLaserV8

final class V8EngineTests: XCTestCase {
    func testDebugAsset() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
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
