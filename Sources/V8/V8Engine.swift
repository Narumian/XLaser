import Foundation
import CV8Bridge
import XLaser

public enum V8EngineError: Error, Equatable {
    case unavailable
    case javaScript(String)
    case invalidInput
    case invalidOutput
    case stopped
}

public final class V8Engine: LaserScriptEngine {
    public static var isAvailable: Bool { xlv8_available() != 0 }

    private let runtime: OpaquePointer
    private var stopped = false

    public init(source: String) throws {
        guard Self.isAvailable else { throw V8EngineError.unavailable }
        let host = try LaserScriptJavaScriptRuntime.source()
        guard !source.utf8.contains(0), !host.utf8.contains(0) else { throw V8EngineError.invalidInput }
        guard let runtime = host.withCString({ runtime in
            source.withCString { script in xlv8_create(runtime, script) }
        }) else { throw V8EngineError.javaScript(String(cString: xlv8_error())) }
        self.runtime = runtime
    }

    deinit { xlv8_destroy(runtime) }

    public func read(context: LaserScriptReadContext, inputs: [Laser3DBuffer], output: inout Laser3DBuffer) throws {
        output.removeAll()
        guard !stopped else { throw V8EngineError.stopped }
        do {
            let packed = try PackedInputs(inputs)
            var nativeOutput = XLaserV8Output()
            let status = packed.withInputs { descriptors in
                xlv8_read(runtime, context.time, context.sampleRate, Double(context.frameLength),
                          descriptors.baseAddress, descriptors.count, &nativeOutput)
            }
            if status == 2 { throw V8EngineError.invalidOutput }
            guard status == 0 else { throw V8EngineError.javaScript(String(cString: xlv8_error())) }
            try decode(nativeOutput, into: &output)
        } catch {
            output.removeAll()
            stopped = true
            throw error
        }
    }

    private func decode(_ output: XLaserV8Output, into buffer: inout Laser3DBuffer) throws {
        let count = output.vertex_count, shapeCount = output.shape_count
        guard count >= 0, shapeCount >= 0, count <= Int.max / 8, shapeCount <= Int.max / 3,
              count == 0 || (output.values != nil && output.modes != nil),
              shapeCount == 0 || output.shapes != nil else { throw V8EngineError.invalidOutput }
        do {
            try buffer.replaceContents(
                shapes: UnsafeBufferPointer(start: output.shapes, count: shapeCount * 3),
                values: UnsafeBufferPointer(start: output.values, count: count * 8),
                modes: UnsafeBufferPointer(start: output.modes, count: count))
        } catch { throw V8EngineError.invalidOutput }
    }
}

private struct PackedInputs {
    struct Range {
        let vertexOffset: Int
        let shapeOffset: Int
        let vertexCount: Int
        let shapeCount: Int
    }

    var values: [Double] = []
    var modes: [UInt16] = []
    var shapes: [UInt32] = []
    var ranges: [Range] = []

    init(_ inputs: [Laser3DBuffer]) throws {
        for stream in inputs {
            let vertexOffset = modes.count, shapeOffset = shapes.count
            guard UInt32(exactly: stream.shapeCount) != nil, UInt32(exactly: stream.vertexCount) != nil,
                  stream.shapeCount <= (Int.max - shapeOffset) / 3,
                  stream.vertexCount <= (Int.max - values.count) / 8 else { throw V8EngineError.invalidInput }
            stream.withUnsafeBuffers { streamShapes, streamValues, streamModes in
                for shape in streamShapes { shapes.append(contentsOf: [shape.id.rawValue, shape.start, shape.count]) }
                values.append(contentsOf: streamValues)
                modes.append(contentsOf: streamModes)
            }
            ranges.append(Range(vertexOffset: vertexOffset, shapeOffset: shapeOffset,
                                vertexCount: stream.vertexCount, shapeCount: stream.shapeCount))
        }
    }

    func withInputs<Result>(_ body: (UnsafeBufferPointer<XLaserV8Input>) -> Result) -> Result {
        values.withUnsafeBufferPointer { values in
            modes.withUnsafeBufferPointer { modes in
                shapes.withUnsafeBufferPointer { shapes in
                    let descriptors = ranges.map { range in
                        XLaserV8Input(values: values.baseAddress?.advanced(by: range.vertexOffset * 8),
                                      modes: modes.baseAddress?.advanced(by: range.vertexOffset),
                                      shapes: shapes.baseAddress?.advanced(by: range.shapeOffset),
                                      vertex_count: range.vertexCount, shape_count: range.shapeCount)
                    }
                    return descriptors.withUnsafeBufferPointer(body)
                }
            }
        }
    }
}
