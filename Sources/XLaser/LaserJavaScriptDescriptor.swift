import Foundation

public enum LaserDescriptorError: Error {
    case invalidHeader
}

public enum LaserJavaScriptDescriptor {
    private struct Header: Decodable {
        struct Input: Decodable {
            let name: String
            let type: String
            let defaultValue: LaserDescriptor.Value?
            let minimum: Double?
            let maximum: Double?

            enum CodingKeys: String, CodingKey {
                case name = "NAME", type = "TYPE", defaultValue = "DEFAULT", minimum = "MIN", maximum = "MAX"
            }
        }

        let name: String?
        let inputs: [Input]?
        enum CodingKeys: String, CodingKey { case name = "NAME", inputs = "INPUTS" }
    }

    public static func parse(_ source: String) throws -> LaserDescriptor {
        guard source.hasPrefix("/*") else { return LaserDescriptor() }
        guard let end = source.range(of: "*/"),
              let data = String(source[source.index(source.startIndex, offsetBy: 2)..<end.lowerBound]).data(using: .utf8),
              let header = try? JSONDecoder().decode(Header.self, from: data) else { throw LaserDescriptorError.invalidHeader }
        return LaserDescriptor(name: header.name, inputs: (header.inputs ?? []).map {
            LaserDescriptor.Input(name: $0.name, type: $0.type, defaultValue: $0.defaultValue,
                                  minimum: $0.minimum, maximum: $0.maximum)
        })
    }
}
