#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import LaserScriptKit

public enum JavaScriptCoreEngineError: Error, Equatable {
    case contextUnavailable
    case javaScript(String)
    case invalidOutput
    case stopped
}

public final class JavaScriptCoreEngine {
    private let context: JSContext
    private let invoke: JSValue
    private var stopped = false

    public init(source: String) throws {
        guard let context = JSContext() else { throw JavaScriptCoreEngineError.contextUnavailable }
        self.context = context
        context.evaluateScript(source)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        let invoke = context.evaluateScript("""
        (function(context) {
            const output = { shapes: [], addShape(id, vertices) { this.shapes.push({ id, vertices }); } };
            read(context, [], output);
            return JSON.stringify(output.shapes);
        })
        """)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        guard let invoke, !invoke.isUndefined else { throw JavaScriptCoreEngineError.contextUnavailable }
        self.invoke = invoke
    }

    public func read(time: Double, sampleRate: Double, frameLength: Int) throws -> [Laser3DShape] {
        guard !stopped else { throw JavaScriptCoreEngineError.stopped }
        context.exception = nil
        let value = invoke.call(withArguments: [["time": time, "sampleRate": sampleRate, "frameLength": frameLength]])
        if let exception = context.exception {
            stopped = true
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        guard let json = value?.toString(), let data = json.data(using: .utf8),
              let shapes = try? JSONDecoder().decode([Shape].self, from: data) else {
            stopped = true
            throw JavaScriptCoreEngineError.invalidOutput
        }
        do { return try shapes.map { try $0.converted() } }
        catch { stopped = true; throw JavaScriptCoreEngineError.invalidOutput }
    }
}

private struct Shape: Decodable {
    let id: UInt32
    let vertices: [Vertex]

    func converted() throws -> Laser3DShape {
        Laser3DShape(id: LaserShapeID(id), vertices: try vertices.map { try $0.converted() })
    }
}

private struct Vertex: Decodable {
    let position: [Double]
    let rgba: [Double]
    let mode: UInt16

    func converted() throws -> LaserVertex {
        guard position.count == 4, rgba.count == 4,
              position.allSatisfy(\.isFinite), rgba.allSatisfy(\.isFinite),
              let mode = LaserPointMode(rawValue: mode) else { throw JavaScriptCoreEngineError.invalidOutput }
        return LaserVertex(position: SIMD4(position[0], position[1], position[2], position[3]),
                           rgba: SIMD4(rgba[0], rgba[1], rgba[2], rgba[3]), mode: mode)
    }
}
#endif
