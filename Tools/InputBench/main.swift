import Foundation
import Dispatch
import XLaser
import XLaserV8
#if canImport(JavaScriptCore)
import XLaserApple
#endif

struct Scenario {
    let name: String
    let source: String
    let inputs: [String: LaserInput]
    let vertices: Int
    let iterations: Int
    let warmup: Int
}

enum BenchError: Error { case invalidOutput(String) }

func makeBuffer(vertices: Int, shapes: Int) throws -> Laser3DBuffer {
    var result = Laser3DBuffer()
    try result.reserveCapacity(shapes: shapes, vertices: vertices)
    for shape in 0..<shapes {
        try result.beginShape(id: LaserShapeID(UInt32(shape)))
        for vertex in (shape * vertices / shapes)..<((shape + 1) * vertices / shapes) {
            try result.appendVertex(LaserVertex(x: Double(vertex) / Double(vertices), y: 0.5))
        }
    }
    return result
}

func measure(_ scenario: Scenario, engine: any LaserScriptable, name: String) throws {
    let context = LaserReadContext(time: 1, sampleRate: 30000, frameLength: scenario.vertices)
    var output = Laser3DBuffer()
    try output.reserveCapacity(shapes: 10, vertices: scenario.vertices)
    for _ in 0..<scenario.warmup {
        try engine.read(context: context, inputs: scenario.inputs, output: &output)
        guard output.vertexCount == scenario.vertices else { throw BenchError.invalidOutput(scenario.name) }
    }
    if case .laser(let input)? = scenario.inputs["source"], output != input { throw BenchError.invalidOutput(scenario.name) }
    if scenario.name.hasPrefix("generate_") {
        let valid = output.withUnsafeBuffers { shapes, values, modes in
            shapes.count == 10 && shapes[9].id.rawValue == 9 && shapes[9].start == 900 && shapes[9].count == 100 &&
            values[8] == 0.01 && values[999 * 8] == 0.99 && values[999 * 8 + 3] == 1 && modes[999] == 0
        }
        guard valid else { throw BenchError.invalidOutput(scenario.name) }
    }
    var timings: [UInt64] = []
    timings.reserveCapacity(scenario.iterations)
    for _ in 0..<scenario.iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        try engine.read(context: context, inputs: scenario.inputs, output: &output)
        timings.append(DispatchTime.now().uptimeNanoseconds - start)
        guard output.vertexCount == scenario.vertices else { throw BenchError.invalidOutput(scenario.name) }
    }
    timings.sort()
    let median = Double(timings[timings.count / 2]) / 1_000_000
    let p95 = Double(timings[(timings.count * 95 - 1) / 100]) / 1_000_000
    print("\(name),\(scenario.name),\(scenario.iterations),\(String(format: "%.4f", median)),\(String(format: "%.4f", p95))")
}

let point = "o.beginShape(1); o.addVertex(0,0,0,1,1,1,1,1,0);"
let input1k = try makeBuffer(vertices: 1000, shapes: 10)
let input10k = try makeBuffer(vertices: 10000, shapes: 10)
let image512 = try LaserInputImage(width: 512, height: 512, rgba: Array(repeating: 127, count: 512 * 512 * 4))
let image1080 = try LaserInputImage(width: 1920, height: 1080, rgba: Array(repeating: 127, count: 1920 * 1080 * 4))
let audio = try LaserInputAudio(sampleRate: 48000, channels: 2, samples: Array(repeating: 0.25, count: 2048))
let spectrum = try LaserInputSpectrum(sampleRate: 48000, fftSize: 2048, bins: Array(repeating: 0.5, count: 1025))
let parameters: [String: LaserInput] = [
    "speed": .float(1.25), "count": .int(8), "enabled": .bool(true), "label": .string("laser"),
    "position": .vec3(SIMD3(1, 2, 3)), "color": .color(SIMD4(0.1, 0.2, 0.3, 0.4)),
]
let parameterSource = "function read(c,i,o) { if (i.speed !== 1.25 || i.count !== 8 || !i.enabled || i.label !== 'laser' || i.position[2] !== 3 || i.color[3] !== 0.4) throw new Error('bad'); \(point) }"
let declaredParameters = #"""
/*{"INPUTS":[{"NAME":"speed","TYPE":"float","DEFAULT":1.25},
{"NAME":"count","TYPE":"long","DEFAULT":8},{"NAME":"enabled","TYPE":"bool","DEFAULT":true},
{"NAME":"label","TYPE":"string","DEFAULT":"laser"},{"NAME":"position","TYPE":"vec3","DEFAULT":[1,2,3]},
{"NAME":"color","TYPE":"color","DEFAULT":[0.1,0.2,0.3,0.4]}]}*/
"""# + parameterSource
let imageSource = "function read(c,i,o) { if (i.image.rgba[0] !== 127 || i.image.rgba[i.image.rgba.length-1] !== 127) throw new Error('bad'); \(point) }"
let scenarios = [
    Scenario(name: "baseline_1_vertex", source: "function read(c,i,o) { \(point) }", inputs: [:], vertices: 1, iterations: 1000, warmup: 100),
    Scenario(name: "six_parameters", source: parameterSource, inputs: parameters, vertices: 1, iterations: 1000, warmup: 100),
    Scenario(name: "six_declared_parameters", source: declaredParameters, inputs: parameters, vertices: 1, iterations: 1000, warmup: 100),
    Scenario(name: "six_default_parameters", source: declaredParameters, inputs: [:], vertices: 1, iterations: 1000, warmup: 100),
    Scenario(name: "laser_passthrough_1k", source: "function read(c,i,o) { o.addStream(i.source); }", inputs: ["source": .laser(input1k)], vertices: 1000, iterations: 500, warmup: 100),
    Scenario(name: "laser_passthrough_10k", source: "function read(c,i,o) { o.addStream(i.source); }", inputs: ["source": .laser(input10k)], vertices: 10000, iterations: 300, warmup: 50),
    Scenario(name: "generate_1k", source: "function read(c,i,o) { for (let s=0;s<10;s++) { o.beginShape(s); for (let v=0;v<100;v++) o.addVertex(v/100,0,0,1,1,1,1,1,0); } }", inputs: [:], vertices: 1000, iterations: 500, warmup: 100),
    Scenario(name: "generate_1k_direct", source: """
    function read(c,i,o) {
        if (o.modes.length < 1000) { o.modes = o.allocate('uint16', 1000); o.values = o.allocate('float64', 8000); }
        for (let s=0;s<10;s++) {
            o.beginShape(s); o.shapes[s*3+1] = s*100; o.shapes[s*3+2] = 100;
            for (let v=0;v<100;v++) {
                const index = s*100+v, k = index*8;
                o.values[k]=v/100; o.values[k+1]=0; o.values[k+2]=0; o.values[k+3]=1;
                o.values[k+4]=1; o.values[k+5]=1; o.values[k+6]=1; o.values[k+7]=1; o.modes[index]=0;
            }
        }
        o.vertexCount=1000;
    }
    """, inputs: [:], vertices: 1000, iterations: 500, warmup: 100),
    Scenario(name: "generate_1k_reserved", source: """
    function read(c,i,o) {
        o.reserve(10, 1000);
        for (let s=0;s<10;s++) {
            o.beginShape(s);
            const start = o.reserveVertices(100), values = o.values, modes = o.modes;
            for (let v=0;v<100;v++) {
                const index=start+v, k=index*8;
                values[k]=v/100; values[k+1]=0; values[k+2]=0; values[k+3]=1;
                values[k+4]=1; values[k+5]=1; values[k+6]=1; values[k+7]=1; modes[index]=0;
            }
            o.commitVertices(100);
        }
    }
    """, inputs: [:], vertices: 1000, iterations: 500, warmup: 100),
    Scenario(name: "generate_1k_batch", source: """
    const batchValues = new Float64Array(800), batchModes = new Uint16Array(100);
    function read(c,i,o) {
        o.reserve(10, 1000);
        for (let s=0;s<10;s++) {
            o.beginShape(s);
            for (let v=0;v<100;v++) {
                const k=v*8;
                batchValues[k]=v/100; batchValues[k+1]=0; batchValues[k+2]=0; batchValues[k+3]=1;
                batchValues[k+4]=1; batchValues[k+5]=1; batchValues[k+6]=1; batchValues[k+7]=1; batchModes[v]=0;
            }
            o.addVertices(batchValues, batchModes);
        }
    }
    """, inputs: [:], vertices: 1000, iterations: 500, warmup: 100),
    Scenario(name: "image_rgba_512", source: imageSource, inputs: ["image": .image(image512)], vertices: 1, iterations: 200, warmup: 20),
    Scenario(name: "image_rgba_1080p", source: imageSource, inputs: ["image": .image(image1080)], vertices: 1, iterations: 100, warmup: 10),
    Scenario(name: "audio_1024_stereo_fft_1025", source: "function read(c,i,o) { if (i.audio.samples[0] !== 0.25 || i.fft.bins[0] !== 0.5) throw new Error('bad'); \(point) }", inputs: ["audio": .audio(audio), "fft": .audioFFT(spectrum)], vertices: 1, iterations: 500, warmup: 50),
]

print("engine,scenario,iterations,median_ms,p95_ms")
for scenario in scenarios {
#if canImport(JavaScriptCore)
    try measure(scenario, engine: JavaScriptCoreEngine(source: scenario.source), name: "JavaScriptCore")
#endif
    if V8Engine.isAvailable {
        try measure(scenario, engine: V8Engine(source: scenario.source), name: "V8")
    }
}
