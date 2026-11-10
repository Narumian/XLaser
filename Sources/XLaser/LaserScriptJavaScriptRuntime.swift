import Foundation

public enum LaserScriptJavaScriptRuntime {
    public static func source() throws -> String {
        guard let url = Bundle.module.url(forResource: "LaserScript", withExtension: "js") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
