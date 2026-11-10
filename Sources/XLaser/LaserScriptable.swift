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
}

public struct LaserDescriptor: Sendable, Equatable {
    public enum Value: Sendable, Equatable, Decodable {
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
    }

    public struct Input: Sendable, Equatable {
        public let name: String
        public let type: String
        public let defaultValue: Value?
        public let minimum: Double?
        public let maximum: Double?

        public init(name: String, type: String, defaultValue: Value? = nil, minimum: Double? = nil, maximum: Double? = nil) {
            self.name = name
            self.type = type
            self.defaultValue = defaultValue
            self.minimum = minimum
            self.maximum = maximum
        }
    }

    public let name: String?
    public let inputs: [Input]

    public init(name: String? = nil, inputs: [Input] = []) {
        self.name = name
        self.inputs = inputs
    }
}

public protocol LaserScriptable: AnyObject {
    var descriptor: LaserDescriptor { get }
    func read(context: LaserReadContext, inputs: [String: LaserInput], output: inout Laser3DBuffer) throws
}
