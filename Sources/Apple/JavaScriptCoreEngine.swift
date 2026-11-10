#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import XLaser

public enum JavaScriptCoreEngineError: Error, Equatable {
    case contextUnavailable
    case runtimeUnavailable
    case javaScript(String)
    case invalidInput
    case invalidOutput
    case stopped
}

public final class JavaScriptCoreEngine: LaserScriptEngine {
    private let context: JSContext
    private let invoke: JSValue
    private let makeInput: JSValue
    private var inputBuffers: [JSValue] = []
    private var stopped = false

    public init(source: String) throws {
        guard let context = JSContext() else { throw JavaScriptCoreEngineError.contextUnavailable }
        self.context = context
        guard let runtime = try? LaserScriptJavaScriptRuntime.source() else {
            throw JavaScriptCoreEngineError.runtimeUnavailable
        }
        context.evaluateScript(runtime)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        guard let makeInput = context.evaluateScript("(function() { return new Laser3DInput(); })"),
              context.exception == nil else { throw JavaScriptCoreEngineError.runtimeUnavailable }
        self.makeInput = makeInput
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
        let encodedInputs: [JSValue]
        do {
            encodedInputs = try inputs.enumerated().map { try encodeInput($0.element, index: $0.offset) }
        } catch {
            stopped = true
            throw error
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

    private func encodeInput(_ shapes: [Laser3DShape], index: Int) throws -> JSValue {
        var count = 0
        guard UInt32(exactly: shapes.count) != nil, shapes.count <= Int.max / 3 else { throw JavaScriptCoreEngineError.invalidInput }
        for shape in shapes {
            let (next, overflow) = count.addingReportingOverflow(shape.vertices.count)
            guard !overflow, UInt32(exactly: next) != nil, next <= Int.max / 8 else { throw JavaScriptCoreEngineError.invalidInput }
            count = next
        }
        while inputBuffers.count <= index {
            guard let input = makeInput.call(withArguments: []), context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
            inputBuffers.append(input)
        }
        let input = inputBuffers[index]
        input.invokeMethod("prepare", withArguments: [count, shapes.count])
        guard context.exception == nil,
              let valueBuffer = input.forProperty("values"),
              let modeBuffer = input.forProperty("modes"),
              let shapeBuffer = input.forProperty("shapes"), context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
        var values: [Double] = []; values.reserveCapacity(count * 8)
        var modes: [UInt16] = []; modes.reserveCapacity(count)
        var ranges: [UInt32] = []; ranges.reserveCapacity(shapes.count * 3)
        var offset: UInt32 = 0
        for shape in shapes {
            guard let length = UInt32(exactly: shape.vertices.count) else { throw JavaScriptCoreEngineError.invalidInput }
            ranges.append(contentsOf: [shape.id.rawValue, offset, length])
            offset += length
            for vertex in shape.vertices {
                values.append(contentsOf: [vertex.position.x, vertex.position.y, vertex.position.z, vertex.position.w,
                                           vertex.rgba.x, vertex.rgba.y, vertex.rgba.z, vertex.rgba.w])
                modes.append(vertex.mode.rawValue)
            }
        }
        try writeArray(values, to: valueBuffer, type: kJSTypedArrayTypeFloat64Array)
        try writeArray(modes, to: modeBuffer, type: kJSTypedArrayTypeUint16Array)
        try writeArray(ranges, to: shapeBuffer, type: kJSTypedArrayTypeUint32Array)
        return input
    }

    private func writeArray<T>(_ values: [T], to target: JSValue, type: JSTypedArrayType) throws {
        let jsContext = context.jsGlobalContextRef
        var exception: JSValueRef?
        guard JSValueGetTypedArrayType(jsContext, target.jsValueRef, &exception) == type, exception == nil,
              let object = JSValueToObject(jsContext, target.jsValueRef, &exception), exception == nil,
              JSObjectGetTypedArrayLength(jsContext, object, &exception) >= values.count, exception == nil else {
            throw JavaScriptCoreEngineError.invalidInput
        }
        let offset = JSObjectGetTypedArrayByteOffset(jsContext, object, &exception)
        guard exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
        guard !values.isEmpty else { return }
        guard let bytes = JSObjectGetTypedArrayBytesPtr(jsContext, object, &exception), exception == nil else {
            throw JavaScriptCoreEngineError.invalidInput
        }
        values.withUnsafeBytes { source in
            if let base = source.baseAddress { bytes.advanced(by: offset).copyMemory(from: base, byteCount: source.count) }
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
