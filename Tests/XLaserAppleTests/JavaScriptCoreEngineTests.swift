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

    func testTypedArrayOutputGrowsAndResets() throws {
        let source = """
        function read(c, inputs, output) {
            for (let shape = 0; shape < 7; shape++) {
                output.beginShape(shape + 1);
                for (let i = 0; i < 5; i++)
                    output.addVertex(i, shape, 2, 1, 0.1, 0.2, 0.3, 0.4, 2);
            }
        }
        """
        let engine = try JavaScriptCoreEngine(source: source)
        for _ in 0..<2 {
            let shapes = try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1), inputs: [])
            XCTAssertEqual(shapes.count, 7)
            XCTAssertEqual(shapes.map { $0.vertices.count }, Array(repeating: 5, count: 7))
            XCTAssertEqual(shapes[6].vertices[4], LaserVertex(x: 4, y: 6, z: 2, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank))
        }
    }

    func testTypedArrayWithOffset() throws {
        let source = """
        function read(c, inputs, output) {
            output.beginShape(9);
            output.addVertex(3, 4, 0, 1, 1, 1, 1, 1, 0);
            const values = new Float64Array(16);
            values.set(output.values.subarray(0, 8), 8);
            output.values = values.subarray(8);
        }
        """
        let engine = try JavaScriptCoreEngine(source: source)
        let shapes = try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1), inputs: [])
        XCTAssertEqual(shapes[0].vertices[0].position.x, 3)
        XCTAssertEqual(shapes[0].vertices[0].position.y, 4)
    }

    func testRejectsNonFiniteTypedArrayValues() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, i, o) { o.beginShape(1); o.addVertex(0,0,0,1,1,1,1,1,0); o.values[0] = NaN; }")
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1), inputs: [])) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .invalidOutput)
        }
    }

    func testMalformedOutputStopsAsset() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, i, o) { o.beginShape(1); o.shapes[1] = 99; }")
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .invalidOutput)
        }
        XCTAssertThrowsError(try engine.read(context: .init(time: 0, sampleRate: 30000, frameLength: 1000), inputs: [])) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }
}
#endif
