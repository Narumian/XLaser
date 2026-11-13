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

func benchmark(_ name: String, source: String, inputs: [String: LaserInput], vertices: Int, iterations: Int, shapes: Int = 10) throws {
    let engine: any LaserScriptable = try JavaScriptCoreEngine(source: source)
    let context = LaserReadContext(time: 0, sampleRate: 30000, frameLength: vertices)
    var output = Laser3DBuffer()
    try output.reserveCapacity(shapes: shapes, vertices: vertices)
    for _ in 0..<10 { try engine.read(context: context, inputs: inputs, output: &output) }
    let start = DispatchTime.now().uptimeNanoseconds
    var total = 0
    for _ in 0..<iterations {
        try engine.read(context: context, inputs: inputs, output: &output)
        total += output.vertexCount
    }
    guard total == vertices * iterations else { throw BenchError.invalidOutput }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
    print("\(name) shapes=\(shapes) vertices=\(vertices) ms/read=\(String(format: "%.3f", elapsed))")
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

let rotateSource = try String(contentsOfFile: CommandLine.arguments.dropFirst().first ?? "StandardLibrary/Effects/Rotate.js", encoding: .utf8)
let bigInput = try makeInput(vertices: 10000, shapes: 100)
try benchmark("jsc-rotate", source: rotateSource, inputs: ["source": .laser(bigInput), "angle": .float(30)], vertices: 10000, iterations: 100, shapes: 100)
// The same rotation as Rotate.js, as one model matrix per shape instead of a loop over every vertex.
let rotateMatrixSource = """
function read(context, inputs, output) {
  const source = inputs.source;
  if (source === undefined) return;
  const angle = radians(inputs.angle), c = Math.cos(angle), s = Math.sin(angle);
  output.addStream(source, { matrix: [c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] });
}
"""
try benchmark("jsc-rotate-matrix", source: rotateMatrixSource, inputs: ["source": .laser(bigInput), "angle": .float(30)], vertices: 10000, iterations: 100, shapes: 100)
do {
    let engine: any LaserScriptable = try JavaScriptCoreEngine(source: rotateMatrixSource)
    var output = Laser3DBuffer()
    let context = LaserReadContext(time: 0, sampleRate: 30000, frameLength: 10000)
    try engine.read(context: context, inputs: ["source": .laser(bigInput), "angle": .float(30)], output: &output)
    let start = DispatchTime.now().uptimeNanoseconds
    var checksum: Float = 0
    for _ in 0..<100 { checksum += output.baked().vertex(at: 1).position.x }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / 100
    print("native baked() shapes=100 vertices=10000 ms/call=\(String(format: "%.3f", elapsed)) (checksum \(checksum != 0))")
}
#else
print("LaserScriptBench requires JavaScriptCore.")
#endif
