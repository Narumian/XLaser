import Foundation
import XLaser
import XLaserV8
#if canImport(JavaScriptCore)
import XLaserApple
#endif

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let usage = """
usage: XLaserPreview <asset.js | Asset.ls> [options]

  --out <file.png>        output image (default preview.png)
  --times <t0,t1,...>     read times in seconds, in order (default 0)
  --frames <n> --duration <seconds>
                          n reads at i * duration / n, instead of --times
  --input <name=value>    set an input; vectors and colors as 1,2,3
  --laser <name=asset>    feed another asset's output into a laser input
  --size <pixels>         tile size (default 384)
  --columns <n>           tiles per row (default: square-ish)
  --sample-rate <pps>     read context sample rate (default 30000)
  --frame-length <points> read context frame length hint (default 1000)
  --yaw <degrees>         turn the view about the vertical axis (default 0)
  --pitch <degrees>       tilt the view about the horizontal axis (default 0)
  --shape <id,id,...>     draw and report only these shape IDs
  --shapes                list every shape of each read (default: up to 12)
  --blanks                also draw blanked moves in dark gray
  --engine <auto|jsc|v8>  script engine (default auto)

Reads run in the given order on one engine, so assets that keep state between
reads behave as they would in playback.

The view is orthographic. x is right, y is up and z points away from the
viewer. A positive yaw swings the far side to the right, a positive pitch swings
it up; yaw is applied first. The unit cube is drawn dimly with its axes: the
positive x, y and z halves in red, green and blue. The drawing is scaled down
when the turned cube would not fit. There is no depth shading. Segments go to
each non-blank vertex within a shape, nothing joins two shapes, and dwell
vertices are drawn as larger dots.
"""

struct Options {
    var asset = ""
    var out = "preview.png"
    var times: [Double] = [0]
    var inputs: [(name: String, value: String)] = []
    var lasers: [(name: String, path: String)] = []
    var size = 384
    var columns: Int?
    var sampleRate = 30000.0
    var frameLength = 1000
    var blanks = false
    var engine = "auto"
    var yaw: Float = 0
    var pitch: Float = 0
    var onlyShapes: Set<UInt32>?
    var listAllShapes = false
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var frames: Int?
    var duration: Double?
    var index = 0
    func value(for flag: String) throws -> String {
        index += 1
        guard index < arguments.count else { throw ToolError("\(flag) needs a value") }
        return arguments[index]
    }
    func number(_ text: String, _ flag: String) throws -> Double {
        guard let result = Double(text), result.isFinite else { throw ToolError("\(flag): not a number: \(text)") }
        return result
    }
    func pair(_ text: String, _ flag: String) throws -> (String, String) {
        guard let split = text.firstIndex(of: "="), split != text.startIndex else { throw ToolError("\(flag) expects name=value") }
        return (String(text[..<split]), String(text[text.index(after: split)...]))
    }
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--out": options.out = try value(for: argument)
        case "--times": options.times = try value(for: argument).split(separator: ",").map { try number(String($0), argument) }
        case "--frames": frames = Int(try value(for: argument))
        case "--duration": duration = try number(try value(for: argument), argument)
        case "--input": let (name, text) = try pair(try value(for: argument), argument); options.inputs.append((name, text))
        case "--laser": let (name, path) = try pair(try value(for: argument), argument); options.lasers.append((name, path))
        case "--size": options.size = Int(try value(for: argument)) ?? 0
        case "--columns": options.columns = Int(try value(for: argument))
        case "--sample-rate": options.sampleRate = try number(try value(for: argument), argument)
        case "--frame-length": options.frameLength = Int(try value(for: argument)) ?? 0
        case "--blanks": options.blanks = true
        case "--yaw": options.yaw = Float(try number(try value(for: argument), argument))
        case "--pitch": options.pitch = Float(try number(try value(for: argument), argument))
        case "--shape":
            let ids = try value(for: argument).split(separator: ",").map { UInt32($0.trimmingCharacters(in: .whitespaces)) }
            guard !ids.isEmpty, !ids.contains(nil) else { throw ToolError("--shape expects shape IDs like 1,2,3") }
            options.onlyShapes = Set(ids.compactMap { $0 })
        case "--shapes": options.listAllShapes = true
        case "--engine": options.engine = try value(for: argument)
        case "--help", "-h": print(usage); exit(0)
        default:
            guard !argument.hasPrefix("--"), options.asset.isEmpty else { throw ToolError("unknown argument: \(argument)") }
            options.asset = argument
        }
        index += 1
    }
    guard !options.asset.isEmpty else { throw ToolError("missing asset path\n\n\(usage)") }
    guard (16...4096).contains(options.size) else { throw ToolError("--size must be 16...4096") }
    guard options.frameLength > 0, options.sampleRate > 0 else { throw ToolError("--sample-rate and --frame-length must be positive") }
    if let frames {
        guard frames > 0, let duration else { throw ToolError("--frames needs a positive count and --duration") }
        options.times = (0..<frames).map { Double($0) * duration / Double(frames) }
    }
    guard !options.times.isEmpty, options.times.count <= 64 else { throw ToolError("between 1 and 64 reads are supported") }
    return options
}

func loadSource(_ path: String) throws -> String {
    var url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw ToolError("no such asset: \(path)") }
    if isDirectory.boolValue { url.appendPathComponent("main.js") }
    return try String(contentsOf: url, encoding: .utf8)
}

func makeEngine(source: String, kind: String) throws -> any LaserScriptable {
    func v8() throws -> any LaserScriptable {
        guard V8Engine.isAvailable else { throw ToolError("V8 is not enabled in this build (see XLASER_V8_* in Package.swift)") }
        return try V8Engine(source: source)
    }
    switch kind {
    case "v8": return try v8()
    case "jsc":
        #if canImport(JavaScriptCore)
        return try JavaScriptCoreEngine(source: source)
        #else
        throw ToolError("JavaScriptCore is not available on this platform")
        #endif
    case "auto":
        #if canImport(JavaScriptCore)
        return try JavaScriptCoreEngine(source: source)
        #else
        return try v8()
        #endif
    default: throw ToolError("unknown engine: \(kind)")
    }
}

func numbers(_ text: String, count: Int, _ name: String) throws -> [Double] {
    let values = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard values.count == count, text.split(separator: ",").count == count else { throw ToolError("input \(name) needs \(count) comma separated numbers") }
    return values
}

func parseInput(_ text: String, declared: LaserDescriptor.Input) throws -> LaserInput {
    let name = declared.name
    switch declared.canonicalType {
    case "float":
        guard let value = Double(text), value.isFinite else { throw ToolError("input \(name) needs a number") }
        return .float(value)
    case "int", "enum":
        guard let value = Int64(text) else { throw ToolError("input \(name) needs an integer") }
        return declared.canonicalType == "enum" ? .enumeration(value) : .integer(value)
    case "bool", "event":
        guard let value = Bool(text) else { throw ToolError("input \(name) needs true or false") }
        return declared.canonicalType == "event" ? .event(value) : .bool(value)
    case "string": return .string(text)
    case "vec2": let v = try numbers(text, count: 2, name); return .vec2(SIMD2(v[0], v[1]))
    case "vec3": let v = try numbers(text, count: 3, name); return .vec3(SIMD3(v[0], v[1], v[2]))
    case "vec4": let v = try numbers(text, count: 4, name); return .vec4(SIMD4(v[0], v[1], v[2], v[3]))
    case "color": let v = try numbers(text, count: 4, name); return .color(SIMD4(v[0], v[1], v[2], v[3]))
    default: throw ToolError("input \(name) of type \(declared.type) cannot be set from the command line")
    }
}

struct Stats {
    var shapes = 0, vertices = 0, normal = 0, dwell = 0, blank = 0, outside = 0, notFinite = 0
    var minimum = SIMD3<Float>(repeating: .infinity), maximum = SIMD3<Float>(repeating: -.infinity)

    var hasExtent: Bool { vertices > notFinite }
    var hasDepth: Bool { hasExtent && (minimum.z != 0 || maximum.z != 0) }

    mutating func add(_ other: Stats) {
        shapes += other.shapes; vertices += other.vertices
        normal += other.normal; dwell += other.dwell; blank += other.blank
        outside += other.outside; notFinite += other.notFinite
        minimum = pointwiseMin(minimum, other.minimum); maximum = pointwiseMax(maximum, other.maximum)
    }

    var text: String {
        var line = "vertices=\(vertices) normal=\(normal) dwell=\(dwell) blank=\(blank)"
        if hasExtent {
            line += String(format: " x=[%.3f, %.3f] y=[%.3f, %.3f]", minimum.x, maximum.x, minimum.y, maximum.y)
            if hasDepth { line += String(format: " z=[%.3f, %.3f]", minimum.z, maximum.z) }
        }
        if outside > 0 { line += " outside-unit-cube=\(outside)" }
        if notFinite > 0 { line += " non-finite=\(notFinite)" }
        return line
    }
}

func stats(of buffer: Laser3DBuffer, shape: Laser3DShapeRange) -> Stats {
    var result = Stats(shapes: 1)
    for index in Int(shape.start)..<Int(shape.start + shape.count) {
        let vertex = buffer.vertex(at: index)
        result.vertices += 1
        switch vertex.mode {
        case .normal: result.normal += 1
        case .dwell: result.dwell += 1
        case .blank: result.blank += 1
        }
        let position = SIMD3(vertex.position.x, vertex.position.y, vertex.position.z)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { result.notFinite += 1; continue }
        result.minimum = pointwiseMin(result.minimum, position)
        result.maximum = pointwiseMax(result.maximum, position)
        if abs(position.x) > 1 || abs(position.y) > 1 || abs(position.z) > 1 { result.outside += 1 }
    }
    return result
}

/// Notes on how a shape would behave, for the report.
func warnings(for shape: Laser3DShapeRange, _ summary: Stats) -> [String] {
    var notes: [String] = []
    if shape.count == 0 { notes.append("empty shape") }
    else if shape.count == 1 { notes.append("single vertex") }
    if shape.count > 0, summary.normal + summary.dwell == 0 { notes.append("every vertex is blank, nothing is lit") }
    return notes
}

/// The view: yaw about the vertical axis, then pitch about the horizontal axis,
/// then straight onto the screen. z points away from the viewer.
struct View {
    var yaw: Float
    var pitch: Float

    func project(_ p: SIMD3<Float>) -> SIMD2<Float> {
        let cy = cos(yaw * .pi / 180), sy = sin(yaw * .pi / 180)
        let cp = cos(pitch * .pi / 180), sp = sin(pitch * .pi / 180)
        let x = p.x * cy + p.z * sy
        let z = -p.x * sy + p.z * cy
        return SIMD2(x, p.y * cp + z * sp)
    }

    /// Largest screen distance from the center that the unit cube reaches.
    var cubeReach: Float {
        var reach: Float = 1
        for sx: Float in [-1, 1] { for sy: Float in [-1, 1] { for sz: Float in [-1, 1] {
            let p = project(SIMD3(sx, sy, sz))
            reach = max(reach, abs(p.x), abs(p.y))
        } } }
        return reach
    }
}

/// Supersampled max-blend canvas for one tile.
struct Canvas {
    static let supersample = 2
    let side: Int
    var pixels: [Float]

    init(tile: Int) {
        side = tile * Self.supersample
        pixels = Array(repeating: 0, count: side * side * 3)
    }

    mutating func plot(_ x: Int, _ y: Int, _ color: SIMD3<Float>) {
        guard x >= 0, y >= 0, x < side, y < side else { return }
        let base = (y * side + x) * 3
        pixels[base] = max(pixels[base], color.x)
        pixels[base + 1] = max(pixels[base + 1], color.y)
        pixels[base + 2] = max(pixels[base + 2], color.z)
    }

    mutating func disc(_ cx: Float, _ cy: Float, radius: Float, _ color: SIMD3<Float>) {
        let r = Int(radius.rounded(.up))
        for dy in -r...r {
            for dx in -r...r where Float(dx * dx + dy * dy) <= radius * radius + 0.25 {
                plot(Int(cx.rounded()) + dx, Int(cy.rounded()) + dy, color)
            }
        }
    }

    mutating func line(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float, _ color: SIMD3<Float>) {
        let delta = b - a
        let length = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        let steps = max(1, Int((length * 2).rounded(.up)))
        for step in 0...steps {
            let p = a + (b - a) * (Float(step) / Float(steps))
            disc(p.x, p.y, radius: radius, color)
        }
    }

    func downsampled() -> [UInt8] {
        let factor = Self.supersample, tile = side / factor
        var result = [UInt8](repeating: 0, count: tile * tile * 3)
        let weight = Float(factor * factor)
        for y in 0..<tile {
            for x in 0..<tile {
                var sum = SIMD3<Float>.zero
                for sy in 0..<factor {
                    for sx in 0..<factor {
                        let base = ((y * factor + sy) * side + x * factor + sx) * 3
                        sum += SIMD3(pixels[base], pixels[base + 1], pixels[base + 2])
                    }
                }
                let out = (y * tile + x) * 3
                for channel in 0..<3 { result[out + channel] = UInt8((min(1, sum[channel] / weight) * 255).rounded()) }
            }
        }
        return result
    }
}

func renderTile(_ buffer: Laser3DBuffer, shapes: [Laser3DShapeRange], view: View, tile: Int, blanks: Bool) -> [UInt8] {
    var canvas = Canvas(tile: tile)
    let side = Float(canvas.side)
    let scale = side * 0.5 * 0.92 / view.cubeReach
    func map(_ p: SIMD3<Float>) -> SIMD2<Float> {
        let screen = view.project(p)
        return SIMD2(side * 0.5 + screen.x * scale, side * 0.5 - screen.y * scale)
    }
    let guide = SIMD3<Float>(repeating: 0.14)
    let corners: [SIMD3<Float>] = (0..<8).map { SIMD3(($0 & 1) == 0 ? -1 : 1, ($0 & 2) == 0 ? -1 : 1, ($0 & 4) == 0 ? -1 : 1) }
    for a in 0..<8 {
        for bit in [1, 2, 4] where a & bit == 0 {
            canvas.line(from: map(corners[a]), to: map(corners[a | bit]), radius: 0.5, guide)
        }
    }
    let axes: [(SIMD3<Float>, SIMD3<Float>)] = [(SIMD3(1, 0, 0), SIMD3(0.55, 0.1, 0.1)),
                                                (SIMD3(0, 1, 0), SIMD3(0.1, 0.5, 0.1)),
                                                (SIMD3(0, 0, 1), SIMD3(0.15, 0.2, 0.65))]
    for (direction, color) in axes {
        canvas.line(from: map(-direction), to: map(.zero), radius: 0.5, guide)
        canvas.line(from: map(.zero), to: map(direction), radius: 0.5, color)
    }
    for shape in shapes {
        var previous: SIMD2<Float>?
        for index in Int(shape.start)..<Int(shape.start + shape.count) {
            let vertex = buffer.vertex(at: index)
            let position = SIMD3(vertex.position.x, vertex.position.y, vertex.position.z)
            guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { previous = nil; continue }
            let point = map(position)
            let rgb = (SIMD3(vertex.rgba.x, vertex.rgba.y, vertex.rgba.z) * vertex.rgba.w).clamped(lowerBound: .zero, upperBound: .one)
            switch vertex.mode {
            case .blank:
                if blanks, let previous { canvas.line(from: previous, to: point, radius: 0.5, SIMD3(repeating: 0.3)) }
            case .dwell:
                if let previous { canvas.line(from: previous, to: point, radius: 1.5, rgb) }
                canvas.disc(point.x, point.y, radius: 4, rgb)
            case .normal:
                if let previous { canvas.line(from: previous, to: point, radius: 1.5, rgb) }
                canvas.disc(point.x, point.y, radius: 2, rgb)
            }
            previous = point
        }
    }
    return canvas.downsampled()
}

func crc32(_ bytes: [UInt8]) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for n in 0..<256 {
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        table[n] = c
    }
    var crc: UInt32 = 0xFFFFFFFF
    for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFFFFFF
}

func encodePNG(width: Int, height: Int, rgb: [UInt8]) -> Data {
    func be32(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return be32(UInt32(body.count)) + typed + be32(crc32(typed))
    }
    var raw: [UInt8] = []
    raw.reserveCapacity((width * 3 + 1) * height)
    for y in 0..<height {
        raw.append(0)
        raw.append(contentsOf: rgb[(y * width * 3)..<((y + 1) * width * 3)])
    }
    var a: UInt32 = 1, b: UInt32 = 0
    for byte in raw { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
    var zlib: [UInt8] = [0x78, 0x01]
    var offset = 0
    repeat {
        let count = min(65535, raw.count - offset)
        let final: UInt8 = offset + count >= raw.count ? 1 : 0
        zlib += [final, UInt8(count & 0xFF), UInt8(count >> 8), UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)]
        zlib += raw[offset..<(offset + count)]
        offset += count
    } while offset < raw.count
    zlib += be32((b << 16) | a)
    var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    png += chunk("IHDR", be32(UInt32(width)) + be32(UInt32(height)) + [8, 2, 0, 0, 0])
    png += chunk("IDAT", zlib)
    png += chunk("IEND", [])
    return Data(png)
}

func run() throws {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let engine = try makeEngine(source: try loadSource(options.asset), kind: options.engine)
    let descriptor = engine.descriptor

    var inputs: [String: LaserInput] = [:]
    for (name, text) in options.inputs {
        guard let declared = descriptor.inputs.first(where: { $0.name == name }) else {
            throw ToolError("\(options.asset) declares no input named \(name); declared: \(descriptor.inputs.map(\.name).joined(separator: ", "))")
        }
        inputs[name] = try parseInput(text, declared: declared)
    }
    var sources: [(name: String, engine: any LaserScriptable)] = []
    for (name, path) in options.lasers {
        guard descriptor.inputs.contains(where: { $0.name == name && $0.canonicalType == "laser" }) else {
            throw ToolError("\(options.asset) declares no laser input named \(name)")
        }
        sources.append((name, try makeEngine(source: try loadSource(path), kind: options.engine)))
    }
    for declared in descriptor.inputs where declared.canonicalType == "laser" && !options.lasers.contains(where: { $0.name == declared.name }) {
        print("note: laser input \(declared.name) is not fed; pass --laser \(declared.name)=<asset> to preview an effect")
    }

    let tile = options.size
    let count = options.times.count
    let columns = max(1, min(count, options.columns ?? Int(Double(count).squareRoot().rounded(.up))))
    let rows = (count + columns - 1) / columns
    let gap = 4
    let width = columns * tile + (columns - 1) * gap
    let height = rows * tile + (rows - 1) * gap
    var image = [UInt8](repeating: 24, count: width * height * 3)

    print("asset: \(descriptor.name ?? options.asset)  engine: \(options.engine)  size: \(tile)px  reads: \(count)  view: yaw=\(options.yaw) pitch=\(options.pitch)")
    var output = Laser3DBuffer()
    for (frame, time) in options.times.enumerated() {
        let context = LaserReadContext(time: time, sampleRate: options.sampleRate, frameLength: options.frameLength)
        var frameInputs = inputs
        for source in sources {
            var buffer = Laser3DBuffer()
            try source.engine.read(context: context, inputs: [:], output: &buffer)
            frameInputs[source.name] = .laser(buffer)
        }
        try engine.read(context: context, inputs: frameInputs, output: &output)
        let selected = output.shapes.filter { options.onlyShapes?.contains($0.id.rawValue) ?? true }
        var total = Stats()
        var perShape: [(shape: Laser3DShapeRange, stats: Stats)] = []
        for shape in selected {
            let summary = stats(of: output, shape: shape)
            total.add(summary)
            perShape.append((shape, summary))
        }
        var header = "[\(frame)] t=\(time) shapes=\(output.shapeCount)"
        if options.onlyShapes != nil { header += " (showing \(selected.count))" }
        print("\(header) \(total.text)")
        if total.vertices == 0 { print("    empty output") }
        var counts: [UInt32: Int] = [:]
        for shape in output.shapes { counts[shape.id.rawValue, default: 0] += 1 }
        let duplicates = counts.filter { $0.value > 1 }.sorted { $0.key < $1.key }
        if !duplicates.isEmpty {
            print("    note: shape IDs used more than once: " + duplicates.map { "\($0.key) (x\($0.value))" }.joined(separator: ", "))
        }
        if perShape.count <= 12 || options.listAllShapes {
            for (shape, summary) in perShape {
                let notes = warnings(for: shape, summary)
                print("    shape id=\(shape.id.rawValue) start=\(shape.start) \(summary.text)" + (notes.isEmpty ? "" : "  <- " + notes.joined(separator: ", ")))
            }
        } else {
            let empty = perShape.filter { $0.shape.count == 0 }.count, single = perShape.filter { $0.shape.count == 1 }.count
            print("    \(perShape.count) shapes, not listed (--shapes lists them)" + (empty > 0 ? "; \(empty) empty" : "") + (single > 0 ? "; \(single) single-vertex" : ""))
        }

        let pixels = renderTile(output, shapes: selected, view: View(yaw: options.yaw, pitch: options.pitch), tile: tile, blanks: options.blanks)
        let originX = (frame % columns) * (tile + gap), originY = (frame / columns) * (tile + gap)
        for y in 0..<tile {
            let source = y * tile * 3, destination = ((originY + y) * width + originX) * 3
            image.replaceSubrange(destination..<(destination + tile * 3), with: pixels[source..<(source + tile * 3)])
        }
    }
    try encodePNG(width: width, height: height, rgb: image).write(to: URL(fileURLWithPath: options.out))
    print("wrote \(options.out) (\(width)x\(height), \(columns) columns x \(rows) rows)")
}

do { try run() } catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
