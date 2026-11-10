#if canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
import XLaser

final class SharedBufferBenchmark {
    private let context: JSContext
    private let run: JSValue
    private let inputValues: UnsafeMutablePointer<Double>
    private let inputModes: UnsafeMutablePointer<UInt16>
    private let inputShapes: UnsafeMutablePointer<UInt32>
    private let outputValues: UnsafeMutablePointer<Double>
    private let outputModes: UnsafeMutablePointer<UInt16>
    private let outputShapes: UnsafeMutablePointer<UInt32>
    private let capacity: Int
    private let shapeCapacity: Int

    init(capacity: Int, shapeCapacity: Int = 16) throws {
        guard capacity > 0, capacity <= Int(UInt32.max), capacity <= Int.max / 64,
              shapeCapacity > 0, shapeCapacity <= Int(UInt32.max), shapeCapacity <= Int.max / 12 else { throw Failure.capacity }
        self.capacity = capacity
        self.shapeCapacity = shapeCapacity
        guard let context = JSContext() else { throw Failure.context }
        self.context = context
        inputValues = try Self.install(context, name: "inputValues", count: capacity * 8, type: kJSTypedArrayTypeFloat64Array, as: Double.self)
        inputModes = try Self.install(context, name: "inputModes", count: capacity, type: kJSTypedArrayTypeUint16Array, as: UInt16.self)
        inputShapes = try Self.install(context, name: "inputShapes", count: shapeCapacity * 3, type: kJSTypedArrayTypeUint32Array, as: UInt32.self)
        outputValues = try Self.install(context, name: "outputValues", count: capacity * 8, type: kJSTypedArrayTypeFloat64Array, as: Double.self)
        outputModes = try Self.install(context, name: "outputModes", count: capacity, type: kJSTypedArrayTypeUint16Array, as: UInt16.self)
        outputShapes = try Self.install(context, name: "outputShapes", count: shapeCapacity * 3, type: kJSTypedArrayTypeUint32Array, as: UInt32.self)
        context.evaluateScript("""
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
        guard context.exception == nil, let run = context.objectForKeyedSubscript("run"), !run.isUndefined else { throw Failure.javascript }
        self.run = run
    }

    private static func install<T: ExpressibleByIntegerLiteral>(_ context: JSContext, name: String, count: Int, type: JSTypedArrayType, as: T.Type) throws -> UnsafeMutablePointer<T> {
        let bytes = count * MemoryLayout<T>.stride
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: max(8, MemoryLayout<T>.alignment))
        let typedPointer = pointer.bindMemory(to: T.self, capacity: count)
        typedPointer.initialize(repeating: 0, count: count)
        var exception: JSValueRef?
        let object = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef, type, pointer, bytes, { bytes, _ in bytes?.deallocate() }, nil, &exception)
        guard let object, exception == nil else { throw Failure.buffer }
        guard let value = JSValue(jsValueRef: object, in: context) else { throw Failure.buffer }
        context.setObject(value, forKeyedSubscript: name as NSString)
        guard context.exception == nil else { throw Failure.javascript }
        return typedPointer
    }

    func read(count: Int, input: [Laser3DShape]?, generatedShapeCount: Int = 1) throws -> [Laser3DShape] {
        let shapeCount = input?.count ?? generatedShapeCount
        guard count >= 0, count <= capacity, shapeCount >= 0, shapeCount <= shapeCapacity,
              input != nil || count == 0 || shapeCount > 0 else { throw Failure.capacity }
        if let input {
            var offset = 0
            for (index, shape) in input.enumerated() {
                guard shape.vertices.count <= count - offset else { throw Failure.capacity }
                inputShapes[index * 3] = shape.id.rawValue
                inputShapes[index * 3 + 1] = UInt32(offset)
                inputShapes[index * 3 + 2] = UInt32(shape.vertices.count)
                for vertex in shape.vertices {
                    let j = offset * 8
                    inputValues[j] = vertex.position.x; inputValues[j + 1] = vertex.position.y
                    inputValues[j + 2] = vertex.position.z; inputValues[j + 3] = vertex.position.w
                    inputValues[j + 4] = vertex.rgba.x; inputValues[j + 5] = vertex.rgba.y
                    inputValues[j + 6] = vertex.rgba.z; inputValues[j + 7] = vertex.rgba.w
                    inputModes[offset] = vertex.mode.rawValue
                    offset += 1
                }
            }
            guard offset == count else { throw Failure.capacity }
        }
        context.exception = nil
        run.call(withArguments: [count, shapeCount, input != nil])
        guard context.exception == nil else { throw Failure.javascript }
        var result = [Laser3DShape](); result.reserveCapacity(shapeCount)
        for shape in 0..<shapeCount {
            let start = Int(outputShapes[shape * 3 + 1]), length = Int(outputShapes[shape * 3 + 2])
            guard start <= count, length <= count - start else { throw Failure.invalidShape }
            var vertices = [LaserVertex](); vertices.reserveCapacity(length)
            for i in start..<(start + length) {
                let j = i * 8
                guard let mode = LaserPointMode(rawValue: outputModes[i]) else { throw Failure.invalidMode }
                vertices.append(LaserVertex(position: SIMD4(outputValues[j], outputValues[j+1], outputValues[j+2], outputValues[j+3]),
                                            rgba: SIMD4(outputValues[j+4], outputValues[j+5], outputValues[j+6], outputValues[j+7]), mode: mode))
            }
            result.append(Laser3DShape(id: LaserShapeID(outputShapes[shape * 3]), vertices: vertices))
        }
        return result
    }

    enum Failure: Error { case context, capacity, javascript, buffer, invalidMode, invalidShape }
}
#endif
