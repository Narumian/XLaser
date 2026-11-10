#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import XLaser

public enum JavaScriptCoreEngineError: Error, Equatable {
    case contextUnavailable
    case runtimeUnavailable
    case javaScript(String)
    case invalidOutput
    case stopped
}

public final class JavaScriptCoreEngine: LaserScriptEngine {
    private let context: JSContext
    private let invoke: JSValue
    private var stopped = false

    public init(source: String) throws {
        guard let context = JSContext() else { throw JavaScriptCoreEngineError.contextUnavailable }
        self.context = context
        guard let runtimeURL = Bundle.module.url(forResource: "LaserScript", withExtension: "js"),
              let runtime = try? String(contentsOf: runtimeURL, encoding: .utf8) else {
            throw JavaScriptCoreEngineError.runtimeUnavailable
        }
        context.evaluateScript(runtime)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        context.evaluateScript(source)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        let invoke = context.evaluateScript("""
        (function() {
            const output = new Laser3DStream();
            return function(context, inputs) {
                output.reset();
                read(context, inputs, output);
                return output;
            };
        })()
        """)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        guard let invoke, !invoke.isUndefined else { throw JavaScriptCoreEngineError.contextUnavailable }
        self.invoke = invoke
    }

    public func read(context readContext: LaserScriptReadContext, inputs: [[Laser3DShape]]) throws -> [Laser3DShape] {
        guard !stopped else { throw JavaScriptCoreEngineError.stopped }
        context.exception = nil
        let encodedInputs: [[[String: Any]]] = inputs.map { stream in
            stream.map { shape in
                ["id": shape.id.rawValue, "vertices": shape.vertices.map { vertex in
                    ["position": [vertex.position.x, vertex.position.y, vertex.position.z, vertex.position.w],
                     "rgba": [vertex.rgba.x, vertex.rgba.y, vertex.rgba.z, vertex.rgba.w],
                     "mode": vertex.mode.rawValue] as [String: Any]
                }] as [String: Any]
            }
        }
        let output = invoke.call(withArguments: [["time": readContext.time, "sampleRate": readContext.sampleRate, "frameLength": readContext.frameLength], encodedInputs])
        if let exception = context.exception {
            stopped = true
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        do {
            guard let output else { throw JavaScriptCoreEngineError.invalidOutput }
            return try decode(output)
        } catch {
            stopped = true
            throw JavaScriptCoreEngineError.invalidOutput
        }
    }

    private func decode(_ output: JSValue) throws -> [Laser3DShape] {
        guard let shapeCountValue = output.forProperty("shapeCount"), shapeCountValue.isNumber,
              let vertexCountValue = output.forProperty("vertexCount"), vertexCountValue.isNumber,
              let shapeCount32 = UInt32(exactly: shapeCountValue.toDouble()),
              let vertexCount32 = UInt32(exactly: vertexCountValue.toDouble()),
              let shapeCount = Int(exactly: shapeCount32), let vertexCount = Int(exactly: vertexCount32),
              shapeCount <= Int.max / 3, vertexCount <= Int.max / 8,
              let shapeValue = output.forProperty("shapes"),
              let vertexValue = output.forProperty("values"),
              let modeValue = output.forProperty("modes"), context.exception == nil else {
            throw JavaScriptCoreEngineError.invalidOutput
        }
        let shapes: [UInt32] = try copyArray(shapeValue, count: shapeCount * 3, type: kJSTypedArrayTypeUint32Array)
        let vertices: [Double] = try copyArray(vertexValue, count: vertexCount * 8, type: kJSTypedArrayTypeFloat64Array)
        let modes: [UInt16] = try copyArray(modeValue, count: vertexCount, type: kJSTypedArrayTypeUint16Array)
        var result: [Laser3DShape] = []
        result.reserveCapacity(shapeCount)
        for i in 0..<shapeCount {
            guard let start = Int(exactly: shapes[i * 3 + 1]), let length = Int(exactly: shapes[i * 3 + 2]),
                  start <= vertexCount, length <= vertexCount - start else { throw JavaScriptCoreEngineError.invalidOutput }
            var shapeVertices: [LaserVertex] = []
            shapeVertices.reserveCapacity(length)
            for j in start..<(start + length) {
                let k = j * 8
                guard let mode = LaserPointMode(rawValue: modes[j]),
                      vertices[k..<(k + 8)].allSatisfy(\.isFinite) else { throw JavaScriptCoreEngineError.invalidOutput }
                shapeVertices.append(LaserVertex(position: SIMD4(vertices[k], vertices[k + 1], vertices[k + 2], vertices[k + 3]),
                                                 rgba: SIMD4(vertices[k + 4], vertices[k + 5], vertices[k + 6], vertices[k + 7]), mode: mode))
            }
            result.append(Laser3DShape(id: LaserShapeID(shapes[i * 3]), vertices: shapeVertices))
        }
        return result
    }

    private func copyArray<T>(_ value: JSValue, count: Int, type: JSTypedArrayType) throws -> [T] {
        let jsContext = context.jsGlobalContextRef
        var exception: JSValueRef?
        guard JSValueGetTypedArrayType(jsContext, value.jsValueRef, &exception) == type, exception == nil,
              let object = JSValueToObject(jsContext, value.jsValueRef, &exception), exception == nil,
              JSObjectGetTypedArrayLength(jsContext, object, &exception) >= count, exception == nil else {
            throw JavaScriptCoreEngineError.invalidOutput
        }
        let byteOffset = JSObjectGetTypedArrayByteOffset(jsContext, object, &exception)
        guard exception == nil else { throw JavaScriptCoreEngineError.invalidOutput }
        guard count > 0 else { return [] }
        guard let bytes = JSObjectGetTypedArrayBytesPtr(jsContext, object, &exception), exception == nil else {
            throw JavaScriptCoreEngineError.invalidOutput
        }
        return Array(UnsafeBufferPointer(start: bytes.advanced(by: byteOffset).assumingMemoryBound(to: T.self), count: count))
    }
}
#endif
