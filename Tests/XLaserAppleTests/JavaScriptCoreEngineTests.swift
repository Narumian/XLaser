#if canImport(JavaScriptCore)
import XCTest
import Foundation
import XLaserApple
import XLaser
import XLaserStandardLibrary

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
        let many = try buffer((0..<20).map { index in (UInt32(index), (0..<5).map { LaserVertex(x: Float(index), y: Float($0)) }) })
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
            const values = new Float32Array(output.values.length + 8);
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
        let asset: any LaserScriptable = try JavaScriptCoreEngine(source: source)
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
            let engine = try JavaScriptCoreEngine(source: "function read() {}")
            var output = Laser3DBuffer()
            XCTAssertThrowsError(try engine.read(context: context, inputs: ["value": input], output: &output)) { error in
                XCTAssertEqual(error as? JavaScriptCoreEngineError, .invalidInput)
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
        let engine: any LaserScriptable = try JavaScriptCoreEngine(source: source)
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
        let engine: any LaserScriptable = try JavaScriptCoreEngine(source: source)
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
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }

    func testInvalidDescriptorDefaultIsRejectedAtLoad() {
        let source = #"/*{"INPUTS":[{"NAME":"v","TYPE":"vec3","DEFAULT":[1,2]}]}*/ function read() {}"#
        XCTAssertThrowsError(try JavaScriptCoreEngine(source: source)) { error in
            XCTAssertEqual(error as? LaserInputResolutionError, .invalidDefault(name: "v", type: "vec3"))
        }
    }

    func testConvenienceFunctionsAndSafeReservations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Debug/Helpers.js"), encoding: .utf8)
        let engine: any LaserScriptable = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        for _ in 0..<2 {
            try engine.read(context: context, inputs: [:], output: &output)
            XCTAssertEqual(output.shapeCount, 7)
            XCTAssertEqual(output.vertexCount, 23)
            output.withUnsafeBuffers { shapes, values, modes in
                XCTAssertEqual(shapes.map(\.id.rawValue), [1, 2, 3, 4, 5, 6, 7])
                XCTAssertEqual(shapes.map(\.count), [2, 2, 4, 5, 5, 3, 2])
                for shape in shapes[2...4] {
                    let first = Int(shape.start) * 8
                    let last = (Int(shape.start) + Int(shape.count) - 1) * 8
                    XCTAssertEqual(Array(values[first..<(first + 8)]), Array(values[last..<(last + 8)]))
                }
                let polyline = Int(shapes[1].start) * 8
                XCTAssertEqual(Array(values[(polyline + 4)..<(polyline + 8)]), [0, 0, 0, 1])
                let moved = Int(shapes[5].start) * 8
                XCTAssertEqual(Array(values[moved..<(moved + 8)]), [12, 23, 34, 1, 1, 0, 0, 1])
                XCTAssertEqual(modes[Int(shapes[5].start)], LaserPointMode.dwell.rawValue)
                let unwritten = Int(shapes[6].start) + 1
                XCTAssertEqual(Array(values[(unwritten * 8)..<(unwritten * 8 + 8)]), Array(repeating: 0, count: 8))
                XCTAssertEqual(modes[unwritten], LaserPointMode.blank.rawValue)
            }
        }
    }

    func testReservedVerticesDoNotReusePreviousFrameData() throws {
        let source = """
        let reads = 0;
        function read(c, i, o) {
          o.beginShape(1);
          const start = o.reserveVertices(2);
          if (reads++ === 0) {
            o.values.set([0.7,0,0,1,1,1,1,1], (start+1)*8);
            o.modes[start+1] = Mode.normal;
          }
          o.commitVertices(2);
        }
        """
        let engine = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { _, values, modes in
            XCTAssertEqual(values[8], 0.7)
            XCTAssertEqual(modes[1], LaserPointMode.normal.rawValue)
        }
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { _, values, modes in
            XCTAssertEqual(Array(values[8..<16]), Array(repeating: 0, count: 8))
            XCTAssertEqual(modes[1], LaserPointMode.blank.rawValue)
        }
    }

    func testConvenienceDefaultsToNormalWhileReservationsStartBlank() throws {
        let source = """
        let reads = 0;
        function read(c, i, o) {
          o.beginShape(1);
          o.addVertex(0,0,0,1,1,1,1,1);
          o.addVertex({ position: [0,0,0,1], rgba: [1,1,1,1] });
          const values = new Float32Array([0,0,0,1,1,1,1,1, 0,0,0,1,1,1,1,1]);
          if (reads++ === 0) o.addVertices(values, new Uint16Array([Mode.blank, Mode.dwell]));
          else o.addVertices(values);
          o.reserveVertices(2);
          o.commitVertices(2);
        }
        """
        let engine = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { _, _, modes in
            XCTAssertEqual(Array(modes), [0, 0, 2, 1, 2, 2])
        }
        try engine.read(context: context, inputs: [:], output: &output)
        output.withUnsafeBuffers { _, _, modes in
            XCTAssertEqual(Array(modes), [0, 0, 0, 0, 2, 2])
        }
    }

    func testIncompleteReservationFailsAndStops() throws {
        let engine = try JavaScriptCoreEngine(source: "function read(c, i, o) { o.beginShape(1); o.reserveVertices(1); }")
        var output = Laser3DBuffer()
        XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output))
        XCTAssertTrue(output.isEmpty)
        XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .stopped)
        }
    }

    func testBulkValidationAndGrowth() throws {
        let source = #"""
        function read(c, i, o) {
          o.beginShape(5); o.addVertex(Vertex(0.25, 0.5));
          const old = o.values; o.reserve(20, 100);
          if (old === o.values || old[0] !== 0.25 || o.values[0] !== 0.25) throw new Error("Growth");
          old[0] = 9;
          const v = new Float32Array(80 * 8), modes = new Uint16Array(80);
          for (let n=0;n<80;n++) { v[n*8]=n; v[n*8+3]=1; v[n*8+4]=1; v[n*8+5]=1; v[n*8+6]=1; v[n*8+7]=1; }
          o.addVertices(v, modes);
        }
        """#
        let engine = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        try engine.read(context: context, inputs: [:], output: &output)
        XCTAssertEqual(output.vertexCount, 81)
        output.withUnsafeBuffers { _, values, _ in
            XCTAssertEqual(values[0], 0.25)
            XCTAssertEqual(values[80 * 8], 79)
        }
    }

    func testBulkInvalidVertexIsRejectedAtReadBoundary() throws {
        let source = "function read(c,i,o) { o.beginShape(1); o.addVertices(new Float32Array([NaN,0,0,1,1,1,1,1]), new Uint16Array([0])); }"
        let engine = try JavaScriptCoreEngine(source: source)
        var output = Laser3DBuffer()
        XCTAssertThrowsError(try engine.read(context: context, inputs: [:], output: &output)) { error in
            XCTAssertEqual(error as? JavaScriptCoreEngineError, .invalidOutput)
        }
        XCTAssertTrue(output.isEmpty)
    }

    private func standardSource(_ category: LaserStandardLibrary.Category, _ filename: String) throws -> String {
        let url = try XCTUnwrap(LaserStandardLibrary.urls(in: category).first { $0.lastPathComponent == filename })
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testStandardAnimationsAndContinuousSpeed() throws {
        XCTAssertEqual(try LaserStandardLibrary.urls(in: .animations).map(\.lastPathComponent), ["PulsingCircle.js", "RotatingLine.js"])
        let line: any LaserScriptable = try JavaScriptCoreEngine(source: standardSource(.animations, "RotatingLine.js"))
        var output = Laser3DBuffer()
        try line.read(context: context, inputs: [:], output: &output)
        XCTAssertEqual(output.vertexCount, 2)
        XCTAssertEqual(output.vertex(at: 1).position.x, 0.5, accuracy: 1e-12)
        let oneSecond = LaserReadContext(time: 1, sampleRate: 30000, frameLength: 100)
        try line.read(context: oneSecond, inputs: [:], output: &output)
        XCTAssertEqual(output.vertex(at: 1).position.x, 0.5 * Float(cos(Double(1))), accuracy: 1e-6)
        let before = output
        try line.read(context: oneSecond, inputs: ["speed": .float(2)], output: &output)
        XCTAssertEqual(output, before)
        try line.read(context: .init(time: 2, sampleRate: 30000, frameLength: 100), inputs: ["speed": .float(2)], output: &output)
        XCTAssertEqual(output.vertex(at: 1).position.x, 0.5 * Float(cos(Double(3))), accuracy: 1e-6)

        let circle: any LaserScriptable = try JavaScriptCoreEngine(source: standardSource(.animations, "PulsingCircle.js"))
        try circle.read(context: context, inputs: [:], output: &output)
        XCTAssertEqual(output.vertexCount, 65)
        XCTAssertEqual(output.vertex(at: 0).position.x, 0.375, accuracy: 1e-12)
        XCTAssertEqual(output.vertex(at: 0), output.vertex(at: 64))
        try circle.read(context: .init(time: 0.5, sampleRate: 30000, frameLength: 10), inputs: [:], output: &output)
        XCTAssertEqual(output.vertex(at: 0).position.x, 0.5, accuracy: 1e-12)
        let atHalfSecond = output
        try circle.read(context: .init(time: 0.5, sampleRate: 30000, frameLength: 10), inputs: ["speed": .float(2)], output: &output)
        XCTAssertEqual(output, atHalfSecond)
    }

    func testStandardEffectsPreserveShapesAndModes() throws {
        XCTAssertEqual(try LaserStandardLibrary.urls(in: .effects).map(\.lastPathComponent), ["Colorize.js", "Rotate.js"])
        let normal = LaserVertex(x: 1, y: 0, z: 2, w: 0.5, rgba: SIMD4(0.2, 0.4, 0.6, 0.8), mode: .dwell)
        let blank = LaserVertex(x: 0, y: 1, rgba: SIMD4(0.3, 0.6, 0.9, 0.7), mode: .blank)
        let input = try buffer([(42, [normal, blank]), (7, [])])
        let rotate: any LaserScriptable = try JavaScriptCoreEngine(source: standardSource(.effects, "Rotate.js"))
        var output = Laser3DBuffer()
        try rotate.read(context: context, inputs: [:], output: &output)
        XCTAssertTrue(output.isEmpty)
        try rotate.read(context: context, inputs: ["source": .laser(input), "angle": .float(90)], output: &output)
        XCTAssertEqual(output.shapes.map(\.id.rawValue), [42, 7])
        XCTAssertEqual(output.shapes.map(\.count), [2, 0])
        let turned = output.vertex(at: 0)
        XCTAssertEqual(turned.position.x, 0, accuracy: 1e-12)
        XCTAssertEqual(turned.position.y, 1, accuracy: 1e-12)
        XCTAssertEqual(turned.position.z, 2)
        XCTAssertEqual(turned.position.w, 0.5)
        XCTAssertEqual(turned.rgba, normal.rgba)
        XCTAssertEqual(turned.mode, .dwell)
        XCTAssertEqual(output.vertex(at: 1).mode, .blank)

        let colorize: any LaserScriptable = try JavaScriptCoreEngine(source: standardSource(.effects, "Colorize.js"))
        try colorize.read(context: context, inputs: ["source": .laser(input), "color": .color(SIMD4(1, 0, 0, 0.5)), "mix": .float(0.5)], output: &output)
        XCTAssertEqual(output.shapes.map(\.id.rawValue), [42, 7])
        XCTAssertEqual(output.vertex(at: 0).rgba.x, 0.6, accuracy: 1e-12)
        XCTAssertEqual(output.vertex(at: 0).rgba.y, 0.2, accuracy: 1e-12)
        XCTAssertEqual(output.vertex(at: 0).rgba.z, 0.3, accuracy: 1e-12)
        XCTAssertEqual(output.vertex(at: 0).rgba.w, 0.65, accuracy: 1e-12)
        XCTAssertEqual(output.vertex(at: 0).mode, .dwell)
        XCTAssertEqual(output.vertex(at: 1), blank)
        XCTAssertEqual(input.vertex(at: 0), normal)
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
                XCTAssertEqual(values[8], Float(cos(Double(angle))), accuracy: 1e-6)
                XCTAssertEqual(values[9], Float(sin(Double(angle))), accuracy: 1e-6)
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
