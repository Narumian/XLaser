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
            let label: String?
            let description: String?
            let unit: String?

            enum CodingKeys: String, CodingKey {
                case name = "NAME", type = "TYPE", defaultValue = "DEFAULT", minimum = "MIN", maximum = "MAX"
                case label = "LABEL", description = "DESCRIPTION", unit = "UNIT"
            }
        }

        let name: String?
        let description: String?
        let categories: [String]?
        let tags: [String]?
        let author: String?
        let license: String?
        let id: String?
        let version: String?
        let inputs: [Input]?
        enum CodingKeys: String, CodingKey {
            case name = "NAME", description = "DESCRIPTION", categories = "CATEGORIES", tags = "TAGS"
            case author = "AUTHOR", license = "LICENSE", id = "ID", version = "VERSION", inputs = "INPUTS"
        }
    }

    public static func parse(_ source: String) throws -> LaserDescriptor {
        guard source.hasPrefix("/*") else { return LaserDescriptor() }
        guard let end = source.range(of: "*/"),
              let data = String(source[source.index(source.startIndex, offsetBy: 2)..<end.lowerBound]).data(using: .utf8),
              let header = try? JSONDecoder().decode(Header.self, from: data) else { throw LaserDescriptorError.invalidHeader }
        return LaserDescriptor(name: header.name, inputs: (header.inputs ?? []).map {
            LaserDescriptor.Input(name: $0.name, type: $0.type, defaultValue: $0.defaultValue,
                                  minimum: $0.minimum, maximum: $0.maximum,
                                  label: $0.label, description: $0.description, unit: $0.unit)
        }, description: header.description, categories: header.categories, tags: header.tags, author: header.author,
           license: header.license, id: header.id, version: header.version)
    }
}
