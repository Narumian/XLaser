import Foundation
import Dispatch
import XLaser
import XLaserV8

let source = "function read(c, inputs, output) { output.addStream(inputs[0]); }"
let engine: any LaserScriptEngine = try V8Engine(source: source)
let context = LaserScriptReadContext(time: 0, sampleRate: 30000, frameLength: 1000)
let inputs = [(0..<10).map { shape in
    Laser3DShape(id: LaserShapeID(UInt32(shape)), vertices: (0..<100).map { vertex in
        LaserVertex(x: Double(vertex) / 100, y: 0)
    })
}]
for _ in 0..<10 { _ = try engine.read(context: context, inputs: inputs) }
let iterations = 100
let start = DispatchTime.now().uptimeNanoseconds
var vertexCount = 0
for _ in 0..<iterations {
    vertexCount += try engine.read(context: context, inputs: inputs).reduce(0) { $0 + $1.vertices.count }
}
guard vertexCount == iterations * 1000 else { throw BenchError.invalidOutput }
let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
print("v8-json-passthrough shapes=10 vertices=1000 ms/read=\(String(format: "%.3f", milliseconds))")

enum BenchError: Error { case invalidOutput }
