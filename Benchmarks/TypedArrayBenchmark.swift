#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import XLaser

// Experimental benchmark only: copied typed arrays, no shared native storage.
final class TypedArrayBenchmark {
    private let context: JSContext
    private let run: JSValue
    private let inputValues: JSValue
    private let inputModes: JSValue
    private let outputValues: JSValue
    private let outputModes: JSValue
    private let inputShapes: JSValue
    private let outputShapes: JSValue
    private let capacity: Int
    private let shapeCapacity: Int

    init(capacity: Int, shapeCapacity: Int = 16) throws {
        guard capacity > 0, capacity <= Int(UInt32.max), shapeCapacity > 0, shapeCapacity <= Int(UInt32.max), capacity <= Int.max / 8, shapeCapacity <= Int.max / 3 else { throw Failure.capacity }
        self.capacity = capacity
        self.shapeCapacity = shapeCapacity
        guard let context = JSContext() else { throw Failure.context }
        self.context = context
        context.evaluateScript("""
        var inputValues = new Float64Array(\(capacity * 8));
        var inputModes = new Uint16Array(\(capacity));
        var outputValues = new Float64Array(\(capacity * 8));
        var outputModes = new Uint16Array(\(capacity));
        var inputShapes = new Uint32Array(\(shapeCapacity * 3));
        var outputShapes = new Uint32Array(\(shapeCapacity * 3));
        function run(count, shapeCount, passthrough) {
            if (passthrough) {
                outputValues.set(inputValues.subarray(0, count * 8));
                outputModes.set(inputModes.subarray(0, count));
                outputShapes.set(inputShapes.subarray(0, shapeCount * 3));
            } else {
                for (let shape = 0; shape < shapeCount; shape++) {
                    const start = Math.floor(shape * count / shapeCount);
                    const end = Math.floor((shape + 1) * count / shapeCount);
                    outputShapes[shape * 3] = shape + 1;
                    outputShapes[shape * 3 + 1] = start;
                    outputShapes[shape * 3 + 2] = end - start;
                }
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
              let outputModes = context.objectForKeyedSubscript("outputModes"),
              let inputShapes = context.objectForKeyedSubscript("inputShapes"),
              let outputShapes = context.objectForKeyedSubscript("outputShapes") else { throw Failure.context }
        self.run = run
        self.inputValues = inputValues
        self.inputModes = inputModes
        self.outputValues = outputValues
        self.outputModes = outputModes
        self.inputShapes = inputShapes
        self.outputShapes = outputShapes
    }

    func read(count: Int, input: [Laser3DShape]?, generatedShapeCount: Int = 1) throws -> [Laser3DShape] {
        let shapeCount = input?.count ?? generatedShapeCount
        guard count >= 0, count <= capacity, shapeCount >= 0, shapeCount <= shapeCapacity,
              input != nil || count == 0 || shapeCount > 0 else { throw Failure.capacity }
        if let input {
            var values = [Double](); values.reserveCapacity(count * 8)
            var modes = [UInt16](); modes.reserveCapacity(count)
            var shapes = [UInt32](); shapes.reserveCapacity(shapeCount * 3)
            var offset = 0
            for shape in input {
                guard shape.vertices.count <= count - offset else { throw Failure.capacity }
                shapes.append(contentsOf: [shape.id.rawValue, UInt32(offset), UInt32(shape.vertices.count)])
                for vertex in shape.vertices {
                    values.append(contentsOf: [vertex.position.x, vertex.position.y, vertex.position.z, vertex.position.w,
                                              vertex.rgba.x, vertex.rgba.y, vertex.rgba.z, vertex.rgba.w])
                    modes.append(vertex.mode.rawValue)
                }
                offset += shape.vertices.count
            }
            guard offset == count else { throw Failure.capacity }
            try copyToJavaScript(values, target: inputValues)
            try copyToJavaScript(modes, target: inputModes)
            try copyToJavaScript(shapes, target: inputShapes)
        }
        context.exception = nil
        run.call(withArguments: [count, shapeCount, input != nil])
        guard context.exception == nil else { throw Failure.javascript }
        let values: [Double] = try copyFromJavaScript(outputValues, count: count * 8)
        let modes: [UInt16] = try copyFromJavaScript(outputModes, count: count)
        let shapes: [UInt32] = try copyFromJavaScript(outputShapes, count: shapeCount * 3)
        var result = [Laser3DShape](); result.reserveCapacity(shapeCount)
        for shape in 0..<shapeCount {
            let start = Int(shapes[shape * 3 + 1]), length = Int(shapes[shape * 3 + 2])
            guard start <= count, length <= count - start else { throw Failure.invalidShape }
            var vertices = [LaserVertex](); vertices.reserveCapacity(length)
            for i in start..<(start + length) {
                let j = i * 8
                guard let mode = LaserPointMode(rawValue: modes[i]) else { throw Failure.invalidMode }
                vertices.append(LaserVertex(position: SIMD4(values[j], values[j+1], values[j+2], values[j+3]),
                                            rgba: SIMD4(values[j+4], values[j+5], values[j+6], values[j+7]), mode: mode))
            }
            result.append(Laser3DShape(id: LaserShapeID(shapes[shape * 3]), vertices: vertices))
        }
        return result
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

    enum Failure: Error { case context, capacity, javascript, buffer, invalidMode, invalidShape }
}
#endif
