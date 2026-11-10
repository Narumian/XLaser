#if canImport(JavaScriptCore)
import Foundation
import Dispatch
import XLaser
import XLaserApple

func makeInput(vertices: Int, shapes: Int) throws -> Laser3DBuffer {
    var buffer = Laser3DBuffer()
    try buffer.reserveCapacity(shapes: shapes, vertices: vertices)
    for shape in 0..<shapes {
        try buffer.beginShape(id: LaserShapeID(UInt32(shape)))
        for vertex in (shape * vertices / shapes)..<((shape + 1) * vertices / shapes) {
            try buffer.appendVertex(LaserVertex(x: Float(vertex) / Float(vertices), y: 0))
        }
    }
    return buffer
}

func benchmark(_ name: String, source: String, inputs: [String: LaserInput], vertices: Int, iterations: Int) throws {
    let engine: any LaserScriptable = try JavaScriptCoreEngine(source: source)
    let context = LaserReadContext(time: 0, sampleRate: 30000, frameLength: vertices)
    var output = Laser3DBuffer()
    try output.reserveCapacity(shapes: 10, vertices: vertices)
    for _ in 0..<10 { try engine.read(context: context, inputs: inputs, output: &output) }
    let start = DispatchTime.now().uptimeNanoseconds
    var total = 0
    for _ in 0..<iterations {
        try engine.read(context: context, inputs: inputs, output: &output)
        total += output.vertexCount
    }
    guard total == vertices * iterations else { throw BenchError.invalidOutput }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
    print("\(name) shapes=10 vertices=\(vertices) ms/read=\(String(format: "%.3f", elapsed))")
}

enum BenchError: Error { case invalidOutput }
let input = try makeInput(vertices: 1000, shapes: 10)
try benchmark("jsc-passthrough", source: "function read(c, inputs, output) { output.addStream(inputs.first); }", inputs: ["first": .laser(input)], vertices: 1000, iterations: 100)
try benchmark("jsc-generate", source: """
function read(c, inputs, output) {
    for (let shape = 0; shape < 10; shape++) {
        output.beginShape(shape);
        for (let i = 0; i < 100; i++) output.addVertex(i / 100, 0, 0, 1, 1, 1, 1, 1, 0);
    }
}
""", inputs: [:], vertices: 1000, iterations: 100)
#else
print("LaserScriptBench requires JavaScriptCore.")
#endif
