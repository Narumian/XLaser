import Foundation
import CV8Bridge
import XLaser

public enum V8EngineError: Error, Equatable {
    case javaScript(String)
    case invalidInput
    case invalidOutput
    case stopped
}

public final class V8Engine: LaserScriptEngine {
    private let runtime: OpaquePointer
    private var stopped = false

    public init(source: String) throws {
        let host = try LaserScriptJavaScriptRuntime.source()
        guard !source.utf8.contains(0), !host.utf8.contains(0) else { throw V8EngineError.invalidInput }
        guard let runtime = host.withCString({ runtime in
            source.withCString { script in xlv8_create(runtime, script) }
        }) else { throw V8EngineError.javaScript(String(cString: xlv8_error())) }
        self.runtime = runtime
    }

    deinit { xlv8_destroy(runtime) }

    public func read(context: LaserScriptReadContext, inputs: [[Laser3DShape]]) throws -> [Laser3DShape] {
        guard !stopped else { throw V8EngineError.stopped }
        do {
            let packed = try PackedInputs(inputs)
            var output = XLaserV8Output()
            let status = packed.withInputs { descriptors in
                xlv8_read(runtime, context.time, context.sampleRate, Double(context.frameLength),
                          descriptors.baseAddress, descriptors.count, &output)
            }
            if status == 2 { throw V8EngineError.invalidOutput }
            guard status == 0 else { throw V8EngineError.javaScript(String(cString: xlv8_error())) }
            return try decode(output)
        } catch {
            stopped = true
            throw error
        }
    }

    private func decode(_ output: XLaserV8Output) throws -> [Laser3DShape] {
        let count = output.vertex_count, shapeCount = output.shape_count
        guard count >= 0, shapeCount >= 0, count <= Int.max / 8, shapeCount <= Int.max / 3,
              count == 0 || (output.values != nil && output.modes != nil),
              shapeCount == 0 || output.shapes != nil else { throw V8EngineError.invalidOutput }
        let shapes = UnsafeBufferPointer(start: output.shapes, count: shapeCount * 3)
        let values = UnsafeBufferPointer(start: output.values, count: count * 8)
        let modes = UnsafeBufferPointer(start: output.modes, count: count)
        var result: [Laser3DShape] = []; result.reserveCapacity(shapeCount)
        for index in 0..<shapeCount {
            guard let start = Int(exactly: shapes[index * 3 + 1]), let length = Int(exactly: shapes[index * 3 + 2]),
                  start <= count, length <= count - start else { throw V8EngineError.invalidOutput }
            var vertices: [LaserVertex] = []; vertices.reserveCapacity(length)
            for vertex in start..<(start + length) {
                let i = vertex * 8
                guard let mode = LaserPointMode(rawValue: modes[vertex]), values[i..<(i + 8)].allSatisfy(\.isFinite) else { throw V8EngineError.invalidOutput }
                vertices.append(LaserVertex(position: SIMD4(values[i], values[i+1], values[i+2], values[i+3]),
                                            rgba: SIMD4(values[i+4], values[i+5], values[i+6], values[i+7]), mode: mode))
            }
            result.append(Laser3DShape(id: LaserShapeID(shapes[index * 3]), vertices: vertices))
        }
        return result
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

    init(_ inputs: [[Laser3DShape]]) throws {
        for stream in inputs {
            let vertexOffset = modes.count, shapeOffset = shapes.count
            guard UInt32(exactly: stream.count) != nil, stream.count <= (Int.max - shapeOffset) / 3 else { throw V8EngineError.invalidInput }
            var localOffset: UInt32 = 0
            for shape in stream {
                guard let length = UInt32(exactly: shape.vertices.count),
                      length <= UInt32.max - localOffset,
                      shape.vertices.count <= (Int.max - values.count) / 8 else { throw V8EngineError.invalidInput }
                shapes.append(contentsOf: [shape.id.rawValue, localOffset, length])
                localOffset += length
                for vertex in shape.vertices {
                    values.append(contentsOf: [vertex.position.x, vertex.position.y, vertex.position.z, vertex.position.w,
                                               vertex.rgba.x, vertex.rgba.y, vertex.rgba.z, vertex.rgba.w])
                    modes.append(vertex.mode.rawValue)
                }
            }
            ranges.append(Range(vertexOffset: vertexOffset, shapeOffset: shapeOffset,
                                vertexCount: Int(localOffset), shapeCount: stream.count))
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
