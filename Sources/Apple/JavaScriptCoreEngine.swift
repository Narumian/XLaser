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

public final class JavaScriptCoreEngine: LaserScriptable {
    public let descriptor: LaserDescriptor
    private let inputResolver: LaserInputResolver
    private let context: JSContext
    private let invoke: JSValue
    private let makeInput: JSValue
    private let parseParameter: JSValue
    private let makeMediaArray: JSValue
    private var inputBuffers: [JSValue] = []
    private var stopped = false

    public init(source: String) throws {
        descriptor = try LaserJavaScriptDescriptor.parse(source)
        inputResolver = try LaserInputResolver(descriptor: descriptor)
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
        guard let parseParameter = context.evaluateScript("(function() { const parse = JSON.parse; return text => parse(text); })()"),
              context.exception == nil else { throw JavaScriptCoreEngineError.runtimeUnavailable }
        self.parseParameter = parseParameter
        guard let makeMediaArray = context.evaluateScript("(type, count) => type === 0 ? new Uint8Array(count) : new Float32Array(count)"),
              context.exception == nil else { throw JavaScriptCoreEngineError.runtimeUnavailable }
        self.makeMediaArray = makeMediaArray
        context.evaluateScript(source)
        if let exception = context.exception {
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        let invoke = context.evaluateScript("""
        (function() {
            const output = new Laser3DBuffer();
            return function(context, inputs) {
                output.reset();
                read(context, inputs, output);
                output.finishRead();
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

    public func read(context readContext: LaserReadContext, inputs: [String: LaserInput], output: inout Laser3DBuffer) throws {
        output.removeAll()
        guard !stopped else { throw JavaScriptCoreEngineError.stopped }
        context.exception = nil
        let encodedInputs: JSValue
        do {
            guard let object = context.evaluateScript("Object.create(null)") else { throw JavaScriptCoreEngineError.invalidInput }
            var index = 0
            for (name, value) in try inputResolver.resolve(inputs).sorted(by: { $0.key < $1.key }) {
                guard !name.utf8.contains(0) else { throw JavaScriptCoreEngineError.invalidInput }
                switch value {
                case .laser(let buffer):
                    object.setValue(try encodeInput(buffer, index: index), forProperty: name)
                    index += 1
                case .float(let number):
                    guard number.isFinite else { throw JavaScriptCoreEngineError.invalidInput }
                    object.setValue(number, forProperty: name)
                case .image(let image):
                    let media = try makeMediaObject(image.rgba, type: kJSTypedArrayTypeUint8Array, key: "rgba")
                    media.setValue(image.width, forProperty: "width")
                    media.setValue(image.height, forProperty: "height")
                    object.setValue(media, forProperty: name)
                case .audio(let audio):
                    let media = try makeMediaObject(audio.samples, type: kJSTypedArrayTypeFloat32Array, key: "samples")
                    media.setValue(audio.sampleRate, forProperty: "sampleRate")
                    media.setValue(audio.channels, forProperty: "channels")
                    object.setValue(media, forProperty: name)
                case .audioFFT(let spectrum):
                    let media = try makeMediaObject(spectrum.bins, type: kJSTypedArrayTypeFloat32Array, key: "bins")
                    media.setValue(spectrum.sampleRate, forProperty: "sampleRate")
                    media.setValue(spectrum.fftSize, forProperty: "fftSize")
                    object.setValue(media, forProperty: name)
                default:
                    guard let json = try? LaserScriptJavaScriptRuntime.encodeParameter(value),
                          let parameter = parseParameter.call(withArguments: [json]),
                          context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
                    object.setValue(parameter, forProperty: name)
                }
                guard context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
            }
            encodedInputs = object
        } catch {
            stopped = true
            throw error
        }
        let jsOutput = invoke.call(withArguments: [["time": readContext.time, "sampleRate": readContext.sampleRate, "frameLength": readContext.frameLength], encodedInputs])
        if let exception = context.exception {
            stopped = true
            throw JavaScriptCoreEngineError.javaScript(exception.toString() ?? "JavaScript exception")
        }
        do {
            guard let jsOutput else { throw JavaScriptCoreEngineError.invalidOutput }
            try decode(jsOutput, into: &output)
        } catch {
            output.removeAll()
            stopped = true
            throw JavaScriptCoreEngineError.invalidOutput
        }
    }

    private func makeMediaObject<T>(_ values: [T], type: JSTypedArrayType, key: String) throws -> JSValue {
        guard let array = makeMediaArray.call(withArguments: [type == kJSTypedArrayTypeUint8Array ? 0 : 1, values.count]),
              let object = JSValue(newObjectIn: context), context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
        try values.withUnsafeBufferPointer { try writeArray($0, to: array, type: type) }
        object.setValue(array, forProperty: key)
        guard context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
        return object
    }

    private func encodeInput(_ buffer: Laser3DBuffer, index: Int) throws -> JSValue {
        // Scripts read vertices as they are, so each input's model matrices and tints are applied first.
        let buffer = buffer.baked()
        guard UInt32(exactly: buffer.vertexCount) != nil, UInt32(exactly: buffer.shapeCount) != nil,
              buffer.shapeCount <= Int.max / 3 else { throw JavaScriptCoreEngineError.invalidInput }
        while inputBuffers.count <= index {
            guard let input = makeInput.call(withArguments: []), context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
            inputBuffers.append(input)
        }
        let input = inputBuffers[index]
        input.invokeMethod("prepare", withArguments: [buffer.vertexCount, buffer.shapeCount])
        guard context.exception == nil,
              let valueBuffer = input.forProperty("values"),
              let modeBuffer = input.forProperty("modes"),
              let shapeBuffer = input.forProperty("shapes"), context.exception == nil else { throw JavaScriptCoreEngineError.invalidInput }
        try buffer.withUnsafeBuffers { shapes, values, modes in
            var ranges: [UInt32] = []; ranges.reserveCapacity(shapes.count * 3)
            for shape in shapes { ranges.append(contentsOf: [shape.id.rawValue, shape.start, shape.count]) }
            try writeArray(values, to: valueBuffer, type: kJSTypedArrayTypeFloat32Array)
            try writeArray(modes, to: modeBuffer, type: kJSTypedArrayTypeUint16Array)
            try ranges.withUnsafeBufferPointer { try writeArray($0, to: shapeBuffer, type: kJSTypedArrayTypeUint32Array) }
        }
        return input
    }

    private func writeArray<T>(_ values: UnsafeBufferPointer<T>, to target: JSValue, type: JSTypedArrayType) throws {
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
        guard let bytes = JSObjectGetTypedArrayBytesPtr(jsContext, object, &exception), exception == nil,
              let source = values.baseAddress else { throw JavaScriptCoreEngineError.invalidInput }
        bytes.advanced(by: offset).copyMemory(from: source, byteCount: values.count * MemoryLayout<T>.stride)
    }

    private func decode(_ output: JSValue, into buffer: inout Laser3DBuffer) throws {
        guard let shapeCountValue = output.forProperty("shapeCount"), shapeCountValue.isNumber,
              let vertexCountValue = output.forProperty("vertexCount"), vertexCountValue.isNumber,
              let shapeCount32 = UInt32(exactly: shapeCountValue.toDouble()),
              let vertexCount32 = UInt32(exactly: vertexCountValue.toDouble()),
              let shapeCount = Int(exactly: shapeCount32), let vertexCount = Int(exactly: vertexCount32),
              shapeCount <= Int.max / 3, vertexCount <= Int.max / 8,
              let shapeValue = output.forProperty("shapes"),
              let vertexValue = output.forProperty("values"),
              let modeValue = output.forProperty("modes"),
              let matrixValue = output.forProperty("shapeMatrices"),
              let colorValue = output.forProperty("shapeColors"), context.exception == nil,
              shapeCount <= Int.max / 16 else {
            throw JavaScriptCoreEngineError.invalidOutput
        }
        let shapes: [UInt32] = try copyArray(shapeValue, count: shapeCount * 3, type: kJSTypedArrayTypeUint32Array)
        let vertices: [Float] = try copyArray(vertexValue, count: vertexCount * 8, type: kJSTypedArrayTypeFloat32Array)
        let modes: [UInt16] = try copyArray(modeValue, count: vertexCount, type: kJSTypedArrayTypeUint16Array)
        let matrices: [Float] = try copyArray(matrixValue, count: shapeCount * 16, type: kJSTypedArrayTypeFloat32Array)
        let tints: [Float] = try copyArray(colorValue, count: shapeCount * 4, type: kJSTypedArrayTypeFloat32Array)
        try shapes.withUnsafeBufferPointer { shapes in
            try vertices.withUnsafeBufferPointer { vertices in
                try modes.withUnsafeBufferPointer { modes in
                    try matrices.withUnsafeBufferPointer { matrices in
                        try tints.withUnsafeBufferPointer { tints in
                            try buffer.replaceContents(shapes: shapes, values: vertices, modes: modes, matrices: matrices, tints: tints)
                        }
                    }
                }
            }
        }
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
