import Foundation
import Dispatch
import XLaser
import XLaserV8

let engine: any LaserScriptable = try V8Engine(source: "function read(c, inputs, output) { output.addStream(inputs.first); }")
let context = LaserReadContext(time: 0, sampleRate: 30000, frameLength: 1000)
var input = Laser3DBuffer()
try input.reserveCapacity(shapes: 10, vertices: 1000)
for shape in 0..<10 {
    try input.beginShape(id: LaserShapeID(UInt32(shape)))
    for vertex in 0..<100 { try input.appendVertex(LaserVertex(x: Double(vertex) / 100, y: 0)) }
}
var output = Laser3DBuffer()
try output.reserveCapacity(shapes: 10, vertices: 1000)
for _ in 0..<10 { try engine.read(context: context, inputs: ["first": .laser(input)], output: &output) }
let iterations = 100
let start = DispatchTime.now().uptimeNanoseconds
var vertexCount = 0
for _ in 0..<iterations {
    try engine.read(context: context, inputs: ["first": .laser(input)], output: &output)
    vertexCount += output.vertexCount
}
guard vertexCount == iterations * 1000 else { throw BenchError.invalidOutput }
let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(iterations)
print("v8-passthrough shapes=10 vertices=1000 ms/read=\(String(format: "%.3f", milliseconds))")

enum BenchError: Error { case invalidOutput }
