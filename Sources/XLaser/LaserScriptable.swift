import Foundation

public struct LaserReadContext: Sendable, Equatable {
    public var time: Double
    public var sampleRate: Double
    public var frameLength: Int

    public init(time: Double, sampleRate: Double, frameLength: Int) {
        self.time = time
        self.sampleRate = sampleRate
        self.frameLength = frameLength
    }
}

public enum LaserInput: Sendable, Equatable {
    case laser(Laser3DBuffer)
    case float(Double)
    case integer(Int64)
    case bool(Bool)
    case string(String)
    case vec2(SIMD2<Double>)
    case vec3(SIMD3<Double>)
    case vec4(SIMD4<Double>)
    case color(SIMD4<Double>)
    case enumeration(Int64)
    case event(Bool)
    case array([LaserDescriptor.Value])
    case matrix(LaserInputMatrix)
    case image(LaserInputImage)
    case audio(LaserInputAudio)
    case audioFFT(LaserInputSpectrum)

    public static func int(_ value: Int64) -> Self { .integer(value) }
    public static func long(_ value: Int64) -> Self { .integer(value) }
    public static func point2D(_ value: SIMD2<Double>) -> Self { .vec2(value) }


}

public struct LaserDescriptor: Sendable, Equatable {
    public enum Value: Sendable, Equatable, Codable {
        case number(Double), bool(Bool), string(String), array([Value]), object([String: Value]), null

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { self = .null }
            else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
            else if let number = try? value.decode(Double.self) { self = .number(number) }
            else if let string = try? value.decode(String.self) { self = .string(string) }
            else if let array = try? value.decode([Value].self) { self = .array(array) }
            else { self = .object(try value.decode([String: Value].self)) }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }

    public struct Input: Sendable, Equatable {
        public let name: String
        public let type: String
        public let defaultValue: Value?
        public let minimum: Double?
        public let maximum: Double?
        public let label: String?
        public let description: String?
        public let unit: String?

        public var canonicalType: String {
            switch type {
            case "long": "int"
            case "point2D": "vec2"
            default: type
            }
        }

        public init(name: String, type: String, defaultValue: Value? = nil, minimum: Double? = nil, maximum: Double? = nil,
                    label: String? = nil, description: String? = nil, unit: String? = nil) {
            self.name = name
            self.type = type
            self.defaultValue = defaultValue
            self.minimum = minimum
            self.maximum = maximum
            self.label = label
            self.description = description
            self.unit = unit
        }
    }

    public let name: String?
    public let description: String?
    public let categories: [String]?
    public let tags: [String]?
    public let author: String?
    public let license: String?
    public let id: String?
    public let version: String?
    public let inputs: [Input]

    public init(name: String? = nil, inputs: [Input] = [], description: String? = nil, categories: [String]? = nil,
                tags: [String]? = nil, author: String? = nil, license: String? = nil, id: String? = nil, version: String? = nil) {
        self.name = name
        self.inputs = inputs
        self.description = description
        self.categories = categories
        self.tags = tags
        self.author = author
        self.license = license
        self.id = id
        self.version = version
    }
}

public protocol LaserScriptable: AnyObject {
    var descriptor: LaserDescriptor { get }
    func read(context: LaserReadContext, inputs: [String: LaserInput], output: inout Laser3DBuffer) throws
}
