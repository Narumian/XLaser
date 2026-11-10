#if canImport(JavaScriptCore)
import XCTest
import Foundation
import XLaserApple
import XLaser

final class JavaScriptCoreEngineTests: XCTestCase {
    func testDebugAssetChangesWithTime() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/RotatingLine.js"), encoding: .utf8)
        let engine = try JavaScriptCoreEngine(source: source)
        let first = try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])
        let second = try engine.read(context: .init(time: .pi / 2, sampleRate: 30000, frameLength: 1000), inputs: [])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].vertices.count, 2)
        XCTAssertEqual(first[0].vertices[1].position.x, 1, accuracy: 1e-12)
        XCTAssertEqual(second[0].vertices[1].position.y, 1, accuracy: 1e-12)
    }

    func testExceptionStopsAsset() throws {
        let engine = try JavaScriptCoreEngine(source: "function read() { throw new Error('broken'); }")
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])) { error in
            guard case JavaScriptCoreEngineError.javaScript(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("broken"))
        }
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }

    func testInputThroughEngineProtocol() throws {
        let engine: any LaserScriptEngine = try JavaScriptCoreEngine(source: "function read(c, inputs, o) { for (const shape of inputs[0]) o.addShape(shape.id, shape.vertices); }")
        let input = Laser3DShape(id: 42, vertices: [LaserVertex(x: 0.25, y: 0.5, z: 0.75)])
        let result = try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [[input]])
        XCTAssertEqual(result, [input])
    }

    func testMalformedOutputStopsAsset() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, i, o) { o.addShape(1, [{position: [0], rgba: [1,1,1,1], mode: 0}]); }")
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .invalidOutput)
        }
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }
}
#endif
