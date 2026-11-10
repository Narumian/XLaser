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
            let encoder = JSONEncoder()
            let contextData = try encoder.encode(Context(time: context.time, sampleRate: context.sampleRate, frameLength: context.frameLength))
            let inputData = try encoder.encode(inputs.map { $0.map(InputShape.init) })
            guard let contextJSON = String(data: contextData, encoding: .utf8),
                  let inputJSON = String(data: inputData, encoding: .utf8) else { throw V8EngineError.invalidInput }
            guard let result = contextJSON.withCString({ context in inputJSON.withCString { input in xlv8_read(runtime, context, input) } }) else {
                throw V8EngineError.javaScript(String(cString: xlv8_error()))
            }
            let data = Data(String(cString: result).utf8)
            guard let output = try? JSONDecoder().decode(Output.self, from: data) else { throw V8EngineError.invalidOutput }
            return try output.shapesValue()
        } catch let error as V8EngineError {
            stopped = true
            throw error
        } catch {
            stopped = true
            throw V8EngineError.invalidInput
        }
    }
}

private struct Context: Encodable {
    let time: Double
    let sampleRate: Double
    let frameLength: Int
}

private struct InputShape: Encodable {
    let id: UInt32
    let vertices: [InputVertex]
    init(_ shape: Laser3DShape) {
        id = shape.id.rawValue
        vertices = shape.vertices.map(InputVertex.init)
    }
}

private struct InputVertex: Encodable {
    let position: [Double]
    let rgba: [Double]
    let mode: UInt16
    init(_ vertex: LaserVertex) {
        position = [vertex.position.x, vertex.position.y, vertex.position.z, vertex.position.w]
        rgba = [vertex.rgba.x, vertex.rgba.y, vertex.rgba.z, vertex.rgba.w]
        mode = vertex.mode.rawValue
    }
}

private struct Output: Decodable {
    let shapes: [UInt32]
    let values: [Double]
    let modes: [UInt16]

    func shapesValue() throws -> [Laser3DShape] {
        guard shapes.count % 3 == 0, values.count % 8 == 0, values.count / 8 == modes.count else { throw V8EngineError.invalidOutput }
        var result: [Laser3DShape] = []
        result.reserveCapacity(shapes.count / 3)
        for index in 0..<(shapes.count / 3) {
            guard let start = Int(exactly: shapes[index * 3 + 1]), let count = Int(exactly: shapes[index * 3 + 2]),
                  start <= modes.count, count <= modes.count - start else { throw V8EngineError.invalidOutput }
            var vertices: [LaserVertex] = []
            vertices.reserveCapacity(count)
            for vertex in start..<(start + count) {
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
