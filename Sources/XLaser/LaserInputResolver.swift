public enum LaserInputResolutionError: Error, Equatable, Sendable {
    case duplicateName(String)
    case invalidDefault(name: String, type: String)
    case typeMismatch(name: String, expected: String)
}

public struct LaserInputResolver: Sendable {
    private let types: [String: String]
    private let defaults: [String: LaserInput]

    public init(descriptor: LaserDescriptor) throws {
        var types: [String: String] = [:]
        var defaults: [String: LaserInput] = [:]
        for declaration in descriptor.inputs {
            let name = declaration.name, type = declaration.canonicalType
            guard types.updateValue(type, forKey: name) == nil else { throw LaserInputResolutionError.duplicateName(name) }
            if let value = declaration.defaultValue {
                guard let input = Self.defaultInput(value, type: type) else {
                    throw LaserInputResolutionError.invalidDefault(name: name, type: type)
                }
                defaults[name] = input
            }
        }
        self.types = types
        self.defaults = defaults
    }

    public func resolve(_ inputs: [String: LaserInput]) throws -> [String: LaserInput] {
        var result = defaults
        for (name, input) in inputs {
            if let type = types[name], !Self.matches(input, type: type) {
                throw LaserInputResolutionError.typeMismatch(name: name, expected: type)
            }
            result[name] = input
        }
        return result
    }

    private static func matches(_ input: LaserInput, type: String) -> Bool {
        switch (type, input) {
        case ("laser", .laser), ("float", .float), ("int", .integer), ("bool", .bool),
             ("string", .string), ("vec2", .vec2), ("vec3", .vec3), ("vec4", .vec4),
             ("color", .color), ("enum", .enumeration), ("event", .event), ("array", .array),
             ("matrix", .matrix), ("image", .image), ("audio", .audio), ("audioFFT", .audioFFT): true
        default: false
        }
    }

    private static func defaultInput(_ value: LaserDescriptor.Value, type: String) -> LaserInput? {
        func numbers(_ value: LaserDescriptor.Value, count: Int) -> [Double]? {
            guard case .array(let values) = value, values.count == count else { return nil }
            var result: [Double] = []
            for value in values {
                guard case .number(let number) = value, number.isFinite else { return nil }
                result.append(number)
            }
            return result
        }
        switch (type, value) {
        case ("float", .number(let number)) where number.isFinite: return .float(number)
        case ("int", .number(let number)):
            guard let integer = Int64(exactly: number) else { return nil }
            return .integer(integer)
        case ("enum", .number(let number)):
            guard let integer = Int64(exactly: number) else { return nil }
            return .enumeration(integer)
        case ("bool", .bool(let value)): return .bool(value)
        case ("event", .bool(let value)): return .event(value)
        case ("string", .string(let value)): return .string(value)
        case ("array", .array(let values)): return .array(values)
        case ("vec2", _):
            guard let v = numbers(value, count: 2) else { return nil }
            return .vec2(SIMD2(v[0], v[1]))
        case ("vec3", _):
            guard let v = numbers(value, count: 3) else { return nil }
            return .vec3(SIMD3(v[0], v[1], v[2]))
        case ("vec4", _), ("color", _):
            guard let v = numbers(value, count: 4) else { return nil }
            let vector = SIMD4(v[0], v[1], v[2], v[3])
            return type == "color" ? .color(vector) : .vec4(vector)
        case ("matrix", .object(let object)):
            guard case .number(let rowValue) = object["rows"], case .number(let columnValue) = object["columns"],
                  let rows = Int(exactly: rowValue), let columns = Int(exactly: columnValue),
                  rows > 0, columns > 0, rows <= Int.max / columns,
                  let v = object["values"], let values = numbers(v, count: rows * columns),
                  let matrix = try? LaserInputMatrix(rows: rows, columns: columns, values: values) else { return nil }
            return .matrix(matrix)
        default: return nil
        }
    }
}
