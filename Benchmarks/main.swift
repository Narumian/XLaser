#if canImport(JavaScriptCore)
import Foundation
import Dispatch
import LaserScriptKit
import LaserScriptKitApple

let generator = """
function read(c, inputs, output) {
    const shapeCount = Math.min(10, c.frameLength);
    for (let shape = 0; shape < shapeCount; shape++) {
        const vertices = [];
        const start = Math.floor(shape * c.frameLength / shapeCount);
        const end = Math.floor((shape + 1) * c.frameLength / shapeCount);
        for (let i = start; i < end; i++)
            vertices.push({ position: [i / c.frameLength, 0, 0, 1], rgba: [1, 1, 1, 1], mode: 0 });
        output.addShape(shape + 1, vertices);
    }
}
"""
let passthrough = """
function read(c, inputs, output) {
    for (const shape of inputs[0]) output.addShape(shape.id, shape.vertices);
}
"""

func benchmark(name: String, source: String, count: Int, inputs: [[Laser3DShape]], iterations: Int) throws {
    let engine: any LaserScriptEngine = try JavaScriptCoreEngine(source: source)
    let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: count)
    for _ in 0..<10 { _ = try engine.read(context: context, inputs: inputs) }
    let start = DispatchTime.now().uptimeNanoseconds
    var totalVertices = 0
    for _ in 0..<iterations {
        let output = try engine.read(context: context, inputs: inputs)
        totalVertices += output.reduce(0) { $0 + $1.vertices.count }
    }
    guard totalVertices == count * iterations else { throw BenchError.invalidOutput }
    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    print("\(name) vertices=\(count) reads=\(iterations) ms/read=\(String(format: "%.3f", seconds * 1000 / Double(iterations)))")
}

func benchmarkTypedArray(count: Int, input: [Laser3DShape]?, iterations: Int) throws {
    let engine = try TypedArrayBenchmark(capacity: count)
    let shapeCount = min(10, count)
    let expected = input ?? makeShapes(count: count, shapeCount: shapeCount)
    guard try engine.read(count: count, input: input, generatedShapeCount: shapeCount) == expected else { throw BenchError.invalidOutput }
    for _ in 0..<10 { _ = try engine.read(count: count, input: input, generatedShapeCount: shapeCount) }
    let start = DispatchTime.now().uptimeNanoseconds
    var total = 0
    for _ in 0..<iterations {
        total += try engine.read(count: count, input: input, generatedShapeCount: shapeCount).reduce(0) { $0 + $1.vertices.count }
    }
    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    guard total == count * iterations else { throw BenchError.invalidOutput }
    let name = input == nil ? "generate" : "passthrough"
    print("typed-\(name) vertices=\(count) reads=\(iterations) ms/read=\(String(format: "%.3f", seconds * 1000 / Double(iterations)))")
}

enum BenchError: Error { case invalidOutput }

func makeShapes(count: Int, shapeCount: Int) -> [Laser3DShape] {
    (0..<shapeCount).map { shape in
        let start = shape * count / shapeCount, end = (shape + 1) * count / shapeCount
        return Laser3DShape(id: LaserShapeID(UInt32(shape + 1)), vertices: (start..<end).map {
            LaserVertex(x: Double($0) / Double(count), y: 0)
        })
    }
}

let checkEngine = try TypedArrayBenchmark(capacity: 2)
let checkInput = [
    Laser3DShape(id: 91, vertices: [LaserVertex(x: -0.25, y: 0.5, z: 2, w: 0.75, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank)]),
    Laser3DShape(id: 77, vertices: []),
    Laser3DShape(id: 42, vertices: [LaserVertex(x: 2, y: -1, rgba: SIMD4(0.9, 0.8, 0.7, 0.6), mode: .dwell)]),
]
guard try checkEngine.read(count: 2, input: checkInput) == checkInput,
      try checkEngine.read(count: 0, input: []) == [],
      try checkEngine.read(count: 0, input: [Laser3DShape(id: 5, vertices: [])]) == [Laser3DShape(id: 5, vertices: [])],
      try checkEngine.read(count: 2, input: checkInput) == checkInput else { throw BenchError.invalidOutput }
do {
    _ = try checkEngine.read(count: 3, input: nil)
    throw BenchError.invalidOutput
} catch TypedArrayBenchmark.Failure.capacity {
    // Capacity overflow is reported rather than writing beyond the buffer.
}

for count in [2, 100, 1000] {
    let iterations = count == 1000 ? 100 : 500
    try benchmark(name: "generate", source: generator, count: count, inputs: [], iterations: iterations)
    let input = makeShapes(count: count, shapeCount: min(10, count))
    try benchmark(name: "passthrough", source: passthrough, count: count, inputs: [input], iterations: iterations)
    try benchmarkTypedArray(count: count, input: nil, iterations: iterations)
    try benchmarkTypedArray(count: count, input: input, iterations: iterations)
}
#else
print("LaserScriptBench requires JavaScriptCore.")
#endif
