#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import LaserScriptKit

// Experimental benchmark only: one shape per read, copied typed arrays, no shared native storage.
final class TypedArrayBenchmark {
    private let context: JSContext
    private let run: JSValue
    private let inputValues: JSValue
    private let inputModes: JSValue
    private let outputValues: JSValue
    private let outputModes: JSValue
    private let capacity: Int

    init(capacity: Int) throws {
        self.capacity = capacity
        guard let context = JSContext() else { throw Failure.context }
        self.context = context
        context.evaluateScript("""
        var inputValues = new Float64Array(\(capacity * 8));
        var inputModes = new Uint16Array(\(capacity));
        var outputValues = new Float64Array(\(capacity * 8));
        var outputModes = new Uint16Array(\(capacity));
        function run(count, passthrough) {
            if (passthrough) {
                outputValues.set(inputValues.subarray(0, count * 8));
                outputModes.set(inputModes.subarray(0, count));
            } else {
                for (let i = 0; i < count; i++) {
                    const j = i * 8;
                    outputValues[j] = i / count;
                    outputValues[j + 1] = 0; outputValues[j + 2] = 0; outputValues[j + 3] = 1;
                    outputValues[j + 4] = 1; outputValues[j + 5] = 1; outputValues[j + 6] = 1; outputValues[j + 7] = 1;
                    outputModes[i] = 0;
                }
            }
        }
        """)
        guard context.exception == nil,
              let run = context.objectForKeyedSubscript("run"),
              let inputValues = context.objectForKeyedSubscript("inputValues"),
              let inputModes = context.objectForKeyedSubscript("inputModes"),
              let outputValues = context.objectForKeyedSubscript("outputValues"),
              let outputModes = context.objectForKeyedSubscript("outputModes") else { throw Failure.context }
        self.run = run
        self.inputValues = inputValues
        self.inputModes = inputModes
        self.outputValues = outputValues
        self.outputModes = outputModes
    }

    func read(count: Int, input: Laser3DShape?) throws -> [Laser3DShape] {
        guard count >= 0, count <= capacity, input == nil || input?.vertices.count == count else { throw Failure.capacity }
        if let input {
            var values = [Double](); values.reserveCapacity(count * 8)
            var modes = [UInt16](); modes.reserveCapacity(count)
            for vertex in input.vertices {
                values.append(contentsOf: [vertex.position.x, vertex.position.y, vertex.position.z, vertex.position.w,
                                          vertex.rgba.x, vertex.rgba.y, vertex.rgba.z, vertex.rgba.w])
                modes.append(vertex.mode.rawValue)
            }
            try copyToJavaScript(values, target: inputValues)
            try copyToJavaScript(modes, target: inputModes)
        }
        context.exception = nil
        run.call(withArguments: [count, input != nil])
        guard context.exception == nil else { throw Failure.javascript }
        let values: [Double] = try copyFromJavaScript(outputValues, count: count * 8)
        let modes: [UInt16] = try copyFromJavaScript(outputModes, count: count)
        var vertices = [LaserVertex](); vertices.reserveCapacity(count)
        for i in 0..<count {
            let j = i * 8
            guard let mode = LaserPointMode(rawValue: modes[i]) else { throw Failure.invalidMode }
            vertices.append(LaserVertex(position: SIMD4(values[j], values[j+1], values[j+2], values[j+3]),
                                        rgba: SIMD4(values[j+4], values[j+5], values[j+6], values[j+7]), mode: mode))
        }
        return [Laser3DShape(id: 1, vertices: vertices)]
    }

    private func pointer(_ value: JSValue) throws -> UnsafeMutableRawPointer {
        var exception: JSValueRef?
        let jsContext = context.jsGlobalContextRef
        guard let object = JSValueToObject(jsContext, value.jsValueRef, &exception), exception == nil,
              let pointer = JSObjectGetTypedArrayBytesPtr(jsContext, object, &exception), exception == nil else { throw Failure.buffer }
        return pointer
    }

    private func copyToJavaScript<T>(_ values: [T], target: JSValue) throws {
        let destination = try pointer(target)
        values.withUnsafeBytes { bytes in
            if let source = bytes.baseAddress, bytes.count > 0 { destination.copyMemory(from: source, byteCount: bytes.count) }
        }
    }

    private func copyFromJavaScript<T>(_ source: JSValue, count: Int) throws -> [T] {
        let bytes = try pointer(source)
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: T.self), count: count))
    }

    enum Failure: Error { case context, capacity, javascript, buffer, invalidMode }
}
#endif
