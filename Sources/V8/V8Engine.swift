import Foundation
import CV8Bridge
import XLaser

public enum V8EngineError: Error, Equatable {
    case unavailable
    case javaScript(String)
    case invalidInput
    case invalidOutput
    case stopped
}

public final class V8Engine: LaserScriptable {
    public let descriptor: LaserDescriptor
    private let inputResolver: LaserInputResolver
    public static var isAvailable: Bool { xlv8_available() != 0 }

    private let runtime: OpaquePointer
    private var stopped = false

    public init(source: String) throws {
        guard Self.isAvailable else { throw V8EngineError.unavailable }
        descriptor = try LaserJavaScriptDescriptor.parse(source)
        inputResolver = try LaserInputResolver(descriptor: descriptor)
        let host = try LaserScriptJavaScriptRuntime.source()
        guard !source.utf8.contains(0), !host.utf8.contains(0) else { throw V8EngineError.invalidInput }
        guard let runtime = host.withCString({ runtime in
            source.withCString { script in xlv8_create(runtime, script) }
        }) else { throw V8EngineError.javaScript(String(cString: xlv8_error())) }
        self.runtime = runtime
    }

    deinit { xlv8_destroy(runtime) }

    public func read(context: LaserReadContext, inputs: [String: LaserInput], output: inout Laser3DBuffer) throws {
        output.removeAll()
        guard !stopped else { throw V8EngineError.stopped }
        do {
            let packed = try PackedInputs(inputResolver.resolve(inputs))
            var nativeOutput = XLaserV8Output()
            let status = packed.withInputs { descriptors in
                xlv8_read(runtime, context.time, context.sampleRate, Double(context.frameLength),
                          descriptors.baseAddress, descriptors.count, &nativeOutput)
            }
            if status == 2 { throw V8EngineError.invalidOutput }
            guard status == 0 else { throw V8EngineError.javaScript(String(cString: xlv8_error())) }
            try decode(nativeOutput, into: &output)
        } catch {
            output.removeAll()
            stopped = true
            throw error
        }
    }

    private func decode(_ output: XLaserV8Output, into buffer: inout Laser3DBuffer) throws {
        let count = output.vertex_count, shapeCount = output.shape_count
        guard count >= 0, shapeCount >= 0, count <= Int.max / 8, shapeCount <= Int.max / 3,
              count == 0 || (output.values != nil && output.modes != nil),
              shapeCount == 0 || output.shapes != nil else { throw V8EngineError.invalidOutput }
        do {
            try buffer.replaceContents(
                shapes: UnsafeBufferPointer(start: output.shapes, count: shapeCount * 3),
                values: UnsafeBufferPointer(start: output.values, count: count * 8),
                modes: UnsafeBufferPointer(start: output.modes, count: count))
        } catch { throw V8EngineError.invalidOutput }
    }
}

private struct PackedInputs {
    enum Kind {
        case laser(vertexOffset: Int, shapeOffset: Int, vertices: Int, shapes: Int)
        case number(Double)
        case json(String)
        case image(offset: Int, count: Int, width: UInt32, height: UInt32)
        case audio(offset: Int, count: Int, channels: UInt32, sampleRate: Double)
        case spectrum(offset: Int, count: Int, fftSize: UInt32, sampleRate: Double)
    }
    struct Entry {
        let name: String
        let kind: Kind
    }

    var values: [Float] = []
    var modes: [UInt16] = []
    var shapes: [UInt32] = []
    var bytes: [UInt8] = []
    var samples: [Float] = []
    var entries: [Entry] = []

    init(_ inputs: [String: LaserInput]) throws {
        for (name, input) in inputs.sorted(by: { $0.key < $1.key }) {
            guard !name.utf8.contains(0) else { throw V8EngineError.invalidInput }
            let kind: Kind
            switch input {
            case .laser(let stream):
                let vertexOffset = modes.count, shapeOffset = shapes.count
                guard UInt32(exactly: stream.shapeCount) != nil, UInt32(exactly: stream.vertexCount) != nil,
                      stream.shapeCount <= (Int.max - shapeOffset) / 3,
                      stream.vertexCount <= (Int.max - values.count) / 8 else { throw V8EngineError.invalidInput }
                stream.withUnsafeBuffers { streamShapes, streamValues, streamModes in
                    for shape in streamShapes { shapes.append(contentsOf: [shape.id.rawValue, shape.start, shape.count]) }
                    values.append(contentsOf: streamValues)
                    modes.append(contentsOf: streamModes)
                }
                kind = .laser(vertexOffset: vertexOffset, shapeOffset: shapeOffset, vertices: stream.vertexCount, shapes: stream.shapeCount)
            case .float(let number):
                guard number.isFinite else { throw V8EngineError.invalidInput }
                kind = .number(number)
            case .image(let image):
                guard let width = UInt32(exactly: image.width), let height = UInt32(exactly: image.height) else { throw V8EngineError.invalidInput }
                let offset = bytes.count
                bytes.append(contentsOf: image.rgba)
                kind = .image(offset: offset, count: image.rgba.count, width: width, height: height)
            case .audio(let audio):
                guard let channels = UInt32(exactly: audio.channels) else { throw V8EngineError.invalidInput }
                let offset = samples.count
                samples.append(contentsOf: audio.samples)
                kind = .audio(offset: offset, count: audio.samples.count, channels: channels, sampleRate: audio.sampleRate)
            case .audioFFT(let spectrum):
                guard let fftSize = UInt32(exactly: spectrum.fftSize) else { throw V8EngineError.invalidInput }
                let offset = samples.count
                samples.append(contentsOf: spectrum.bins)
                kind = .spectrum(offset: offset, count: spectrum.bins.count, fftSize: fftSize, sampleRate: spectrum.sampleRate)
            default:
                guard let json = try? LaserScriptJavaScriptRuntime.encodeParameter(input) else { throw V8EngineError.invalidInput }
                kind = .json(json)
            }
            entries.append(Entry(name: name, kind: kind))
        }
    }

    func withInputs<Result>(_ body: (UnsafeBufferPointer<XLaserV8Input>) -> Result) -> Result {
        values.withUnsafeBufferPointer { values in
            modes.withUnsafeBufferPointer { modes in
                shapes.withUnsafeBufferPointer { shapes in
                    bytes.withUnsafeBufferPointer { bytes in
                        samples.withUnsafeBufferPointer { samples in
                            let names = entries.map { strdup($0.name) }
                            defer { for name in names { free(name) } }
                            let jsons = entries.map { entry -> UnsafeMutablePointer<CChar>? in
                                if case .json(let json) = entry.kind { return strdup(json) }
                                return nil
                            }
                            defer { for json in jsons { free(json) } }
                            let descriptors = entries.indices.map { index in
                                var descriptor = XLaserV8Input()
                                descriptor.name = UnsafePointer(names[index])
                                switch entries[index].kind {
                                case .laser(let vertexOffset, let shapeOffset, let vertices, let shapeCount):
                                    descriptor.kind = 0
                                    descriptor.values = values.baseAddress?.advanced(by: vertexOffset * 8)
                                    descriptor.modes = modes.baseAddress?.advanced(by: vertexOffset)
                                    descriptor.shapes = shapes.baseAddress?.advanced(by: shapeOffset)
                                    descriptor.vertex_count = vertices; descriptor.shape_count = shapeCount
                                case .number(let value):
                                    descriptor.kind = 1; descriptor.number = value
                                case .json:
                                    descriptor.kind = 2; descriptor.json = UnsafePointer(jsons[index])
                                case .image(let offset, let count, let width, let height):
                                    descriptor.kind = 3; descriptor.media_data = bytes.baseAddress.map { UnsafeRawPointer($0.advanced(by: offset)) }
                                    descriptor.media_count = count; descriptor.dimension_a = width; descriptor.dimension_b = height
                                case .audio(let offset, let count, let channels, let sampleRate):
                                    descriptor.kind = 4; descriptor.media_data = samples.baseAddress.map { UnsafeRawPointer($0.advanced(by: offset)) }
                                    descriptor.media_count = count; descriptor.dimension_a = channels; descriptor.sample_rate = sampleRate
                                case .spectrum(let offset, let count, let fftSize, let sampleRate):
                                    descriptor.kind = 5; descriptor.media_data = samples.baseAddress.map { UnsafeRawPointer($0.advanced(by: offset)) }
                                    descriptor.media_count = count; descriptor.dimension_a = fftSize; descriptor.sample_rate = sampleRate
                                }
                                return descriptor
                            }
                            return descriptors.withUnsafeBufferPointer(body)
                        }
                    }
                }
            }
        }
    }
}
