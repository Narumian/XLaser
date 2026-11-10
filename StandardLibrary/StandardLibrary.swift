import Foundation

public enum LaserStandardLibraryError: Error {
    case missingResources
}

public enum LaserStandardLibrary {
    public enum Category: String, CaseIterable, Sendable {
        case animations = "Animations"
        case effects = "Effects"
    }

    public static func urls(in category: Category) throws -> [URL] {
        guard let directory = Bundle.module.url(forResource: category.rawValue, withExtension: nil) else {
            throw LaserStandardLibraryError.missingResources
        }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
