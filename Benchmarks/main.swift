#if canImport(JavaScriptCore)
import Foundation
import Dispatch
import LaserScriptKit
import LaserScriptKitApple

let generator = """
function read(c, inputs, output) {
    const vertices = [];
    for (let i = 0; i < c.frameLength; i++)
        vertices.push({ position: [i / c.frameLength, 0, 0, 1], rgba: [1, 1, 1, 1], mode: 0 });
    output.addShape(1, vertices);
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

func benchmarkTypedArray(count: Int, input: Laser3DShape?, iterations: Int) throws {
    let engine = try TypedArrayBenchmark(capacity: count)
    let expected = input ?? Laser3DShape(id: 1, vertices: (0..<count).map { LaserVertex(x: Double($0) / Double(count), y: 0) })
    guard try engine.read(count: count, input: input) == [expected] else { throw BenchError.invalidOutput }
    for _ in 0..<10 { _ = try engine.read(count: count, input: input) }
    let start = DispatchTime.now().uptimeNanoseconds
    var total = 0
    for _ in 0..<iterations {
        total += try engine.read(count: count, input: input).reduce(0) { $0 + $1.vertices.count }
    }
    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    guard total == count * iterations else { throw BenchError.invalidOutput }
    let name = input == nil ? "generate" : "passthrough"
    print("typed-\(name) vertices=\(count) reads=\(iterations) ms/read=\(String(format: "%.3f", seconds * 1000 / Double(iterations)))")
}

enum BenchError: Error { case invalidOutput }

let checkEngine = try TypedArrayBenchmark(capacity: 2)
let checkInput = Laser3DShape(id: 1, vertices: [
    LaserVertex(x: -0.25, y: 0.5, z: 2, w: 0.75, rgba: SIMD4(0.1, 0.2, 0.3, 0.4), mode: .blank),
    LaserVertex(x: 2, y: -1, rgba: SIMD4(0.9, 0.8, 0.7, 0.6), mode: .dwell),
])
guard try checkEngine.read(count: 2, input: checkInput) == [checkInput] else { throw BenchError.invalidOutput }

for count in [2, 100, 1000] {
    let iterations = count == 1000 ? 100 : 500
    try benchmark(name: "generate", source: generator, count: count, inputs: [], iterations: iterations)
    let input = Laser3DShape(id: 1, vertices: (0..<count).map { LaserVertex(x: Double($0) / Double(count), y: 0) })
    try benchmark(name: "passthrough", source: passthrough, count: count, inputs: [[input]], iterations: iterations)
    try benchmarkTypedArray(count: count, input: nil, iterations: iterations)
    try benchmarkTypedArray(count: count, input: input, iterations: iterations)
}
#else
print("LaserScriptBench requires JavaScriptCore.")
#endif
