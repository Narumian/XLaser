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

    func testBasicParameterTypesAndAliases() throws {
        let source = #"""
        function read(c, i, o) {
            if (i.count !== 9007199254740991 || i.enabled !== true || i.label !== "A\u0000光" ||
                JSON.stringify(i.p2) !== "[1,2]" || JSON.stringify(i.v3) !== "[3,4,5]" ||
                JSON.stringify(i.v4) !== "[6,7,8,9]" || JSON.stringify(i.color) !== "[0.1,0.2,0.3,0.4]")
                throw new Error("Incorrect parameters");
            o.beginShape(1); o.addVertex(i.p2[0], i.p2[1], i.v3[2], 1, ...i.color, 0);
        }
        """#
        let asset: any LaserScriptable = try V8Engine(source: source)
        var output = Laser3DBuffer()
        try asset.read(context: context, inputs: [
            "count": .long(9_007_199_254_740_991), "enabled": .bool(true), "label": .string("A\0光"),
            "p2": .point2D(SIMD2(1, 2)), "v3": .vec3(SIMD3(3, 4, 5)),
            "v4": .vec4(SIMD4(6, 7, 8, 9)), "color": .color(SIMD4(0.1, 0.2, 0.3, 0.4))
        ], output: &output)
        XCTAssertEqual(output.vertexCount, 1)
        output.withUnsafeBuffers { _, values, _ in
            XCTAssertEqual(Array(values), [1, 2, 5, 1, 0.1, 0.2, 0.3, 0.4])
        }
        XCTAssertEqual(LaserInput.int(4), LaserInput.long(4))
        XCTAssertEqual(LaserInput.point2D(SIMD2(1, 2)), LaserInput.vec2(SIMD2(1, 2)))
    }

    func testRejectsInvalidNumericParameters() throws {
        for input: LaserInput in [.integer(9_007_199_254_740_992), .vec2(SIMD2(.nan, 0))] {
            let engine = try V8Engine(source: "function read() {}")
            var output = Laser3DBuffer()
            XCTAssertThrowsError(try engine.read(context: context, inputs: ["value": input], output: &output)) { error in
                XCTAssertEqual(error as? V8EngineError, .invalidInput)
            }
            XCTAssertTrue(output.isEmpty)
        }
    }

    func testStructuredAndMediaInputs() throws {
        let source = #"""
        function read(c, i, o) {
            if (i.choice !== 3 || i.trigger !== true ||
                JSON.stringify(i.items) !== '[1,"x",[true,null]]' ||
                i.matrix.rows !== 2 || i.matrix.columns !== 2 || JSON.stringify(i.matrix.values) !== '[1,2,3,4]' ||
                i.image.width !== 2 || i.image.height !== 1 || !(i.image.rgba instanceof Uint8Array) ||
                Array.from(i.image.rgba).join(',') !== '255,0,5,255,0,7,8,255' ||
                i.audio.sampleRate !== 48000 || i.audio.channels !== 2 || !(i.audio.samples instanceof Float32Array) ||
                Array.from(i.audio.samples).join(',') !== '0.25,-0.5' ||
                i.spectrum.sampleRate !== 48000 || i.spectrum.fftSize !== 8 || !(i.spectrum.bins instanceof Float32Array) ||
                Array.from(i.spectrum.bins).join(',') !== '1,0.5') throw new Error("Incorrect media or structured input");
            i.image.rgba[0] = 0; i.audio.samples[0] = 0; i.spectrum.bins[0] = 0;
            o.beginShape(1); o.addVertex(1, 0, 0, 1, 1, 1, 1, 1, 0);
        }
        """#
        let image = try LaserInputImage(width: 2, height: 1, rgba: [255, 0, 5, 255, 0, 7, 8, 255])
        let audio = try LaserInputAudio(sampleRate: 48000, channels: 2, samples: [0.25, -0.5])
        let spectrum = try LaserInputSpectrum(sampleRate: 48000, fftSize: 8, bins: [1, 0.5])
        let matrix = try LaserInputMatrix(rows: 2, columns: 2, values: [1, 2, 3, 4])
        let inputs: [String: LaserInput] = [
            "choice": .enumeration(3), "trigger": .event(true),
            "items": .array([.number(1), .string("x"), .array([.bool(true), .null])]),
            "matrix": .matrix(matrix), "image": .image(image), "audio": .audio(audio), "spectrum": .audioFFT(spectrum)
        ]
        let engine: any LaserScriptable = try V8Engine(source: source)
        var output = Laser3DBuffer()
        for _ in 0..<2 {
            try engine.read(context: context, inputs: inputs, output: &output)
            XCTAssertEqual(output.vertexCount, 1)
        }
        XCTAssertEqual(image.rgba[0], 255)
        XCTAssertEqual(audio.samples[0], 0.25)
        XCTAssertEqual(spectrum.bins[0], 1)
    }

    func testDescriptorDefaultsAndExplicitValues() throws {
        let source = #"""
        /*{"INPUTS":[{"NAME":"speed","TYPE":"float","DEFAULT":1.5},
          {"NAME":"count","TYPE":"long","DEFAULT":3},
          {"NAME":"center","TYPE":"point2D","DEFAULT":[0.25,0.5]},
          {"NAME":"optional","TYPE":"bool"}]}*/
        function read(c, i, o) {
          if (i.optional !== undefined) throw new Error("Unexpected optional input");
          o.beginShape(1); o.addVertex(i.speed, i.count, i.center[0], 1, i.center[1], 1, 1, 1, 0);
        }
        """#
        let engine: any LaserScriptable = try V8Engine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { _, values, _ in XCTAssertEqual(Array(values), [1.5, 3, 0.25, 1, 0.5, 1, 1, 1]) }
        try engine.read(context: context, inputs: ["speed": .float(2), "count": .int(5), "center": .vec2(SIMD2(0.75, 0.25))], output: &output)
        output.withUnsafeBuffers { _, values, _ in XCTAssertEqual(Array(values), [2, 5, 0.75, 1, 0.25, 1, 1, 1]) }
        XCTAssertThrowsError(try engine.read(context: context, inputs: ["count": .float(3)], output: &output)) { error in
            XCTAssertEqual(error as? LaserInputResolutionError, .typeMismatch(name: "count", expected: "int"))
        }
        XCTAssertTrue(output.isEmpty)
        XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
            XCTAssertEqual(error as? V8EngineError, .stopped)
        }
    }

    func testInvalidDescriptorDefaultIsRejectedAtLoad() {
        let source = #"/*{"INPUTS":[{"NAME":"v","TYPE":"vec3","DEFAULT":[1,2]}]}*/ function read() {}"#
        XCTAssertThrowsError(try V8Engine(source: source)) { error in
            XCTAssertEqual(error as? LaserInputResolutionError, .invalidDefault(name: "v", type: "vec3"))
        }
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
