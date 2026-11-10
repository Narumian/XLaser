import Foundation

public enum LaserScriptJavaScriptRuntime {
    private struct Parameter: Encodable {
        let input: LaserInput
        func encode(to encoder: any Encoder) throws {
            switch input {
            case .laser, .image, .audio, .audioFFT:
                throw EncodingError.invalidValue(input, .init(codingPath: encoder.codingPath, debugDescription: "Buffers require a native transport"))
            case .float(let value):
                var container = encoder.singleValueContainer(); try container.encode(value)
            case .integer(let value), .enumeration(let value):
                var container = encoder.singleValueContainer(); try container.encode(value)
            case .bool(let value), .event(let value):
                var container = encoder.singleValueContainer(); try container.encode(value)
            case .string(let value):
                var container = encoder.singleValueContainer(); try container.encode(value)
            case .vec2(let value):
                var container = encoder.unkeyedContainer(); try container.encode(value.x); try container.encode(value.y)
            case .vec3(let value):
                var container = encoder.unkeyedContainer(); try container.encode(value.x); try container.encode(value.y); try container.encode(value.z)
            case .vec4(let value), .color(let value):
                var container = encoder.unkeyedContainer(); try container.encode(value.x); try container.encode(value.y); try container.encode(value.z); try container.encode(value.w)
            case .array(let value):
                var container = encoder.singleValueContainer(); try container.encode(value)
            case .matrix(let value):
                try value.encode(to: encoder)
            }
        }
    }

    public static func encodeParameter(_ input: LaserInput) throws -> String {
        switch input {
        case .integer(let value), .enumeration(let value):
            guard (-9_007_199_254_740_991...9_007_199_254_740_991).contains(value) else {
                throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Integer cannot be represented exactly as a JavaScript number"))
            }
        default: break
        }
        let data = try JSONEncoder().encode(Parameter(input: input))
        guard let json = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return json
    }

    public static func source() throws -> String {
        guard let url = Bundle.module.url(forResource: "LaserScript", withExtension: "js") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
