#if canImport(JavaScriptCore)
import XCTest
import Foundation
import LaserScriptKitApple

final class JavaScriptCoreEngineTests: XCTestCase {
    func testDebugAssetChangesWithTime() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/RotatingLine.js"), encoding: .utf8)
        let engine = try JavaScriptCoreEngine(source: source)
        let first = try engine.read(time: 0, sampleRate: 30000, frameLength: 1000)
        let second = try engine.read(time: .pi / 2, sampleRate: 30000, frameLength: 1000)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].vertices.count, 2)
        XCTAssertEqual(first[0].vertices[1].position.x, 1, accuracy: 1e-12)
        XCTAssertEqual(second[0].vertices[1].position.y, 1, accuracy: 1e-12)
    }

    func testExceptionStopsAsset() throws {
        let engine = try JavaScriptCoreEngine(source: "function read() { throw new Error('broken'); }")
        XCTAssertThrowsError(try engine.read(time: 0, sampleRate: 30000, frameLength: 1000)) { error in
            guard case JavaScriptCoreEngineError.javaScript(let message) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("broken"))
        }
        XCTAssertThrowsError(try engine.read(time: 0, sampleRate: 30000, frameLength: 1000)) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }

    func testReadPerformanceBaseline() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, i, o) { o.addShape(1, [{position:[c.time,0,0,1], rgba:[1,1,1,1], mode:0}]); }")
        for _ in 0..<100 { _ = try engine.read(time: 0, sampleRate: 30000, frameLength: 1000) }
        let start = ContinuousClock.now
        for _ in 0..<1000 { _ = try engine.read(time: 0, sampleRate: 30000, frameLength: 1000) }
        print("JavaScriptCore 1000 one-vertex reads: \(start.duration(to: .now))")
    }

    func testMalformedOutputStopsAsset() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, i, o) { o.addShape(1, [{position: [0], rgba: [1,1,1,1], mode: 0}]); }")
        XCTAssertThrowsError(try engine.read(time: 0, sampleRate: 30000, frameLength: 1000)) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .invalidOutput)
        }
        XCTAssertThrowsError(try engine.read(time: 0, sampleRate: 30000, frameLength: 1000)) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }
}
#endif
