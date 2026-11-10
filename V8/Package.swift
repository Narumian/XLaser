// swift-tools-version: 6.0
import PackageDescription
import Foundation

let includePath = ProcessInfo.processInfo.environment["XLASER_V8_INCLUDE"] ?? ""
let libraryPath = ProcessInfo.processInfo.environment["XLASER_V8_LIBRARY"] ?? ""
let compilerFlags = (ProcessInfo.processInfo.environment["XLASER_V8_CXX_FLAGS"] ?? "").split(separator: " ").map(String.init)
let package = Package(
    name: "XLaserV8",
    products: [.library(name: "XLaserV8", targets: ["XLaserV8"])],
    dependencies: [.package(path: "..")],
    targets: [
        .target(name: "CV8Bridge", cxxSettings: [.unsafeFlags(["-I", includePath] + compilerFlags)], linkerSettings: [.unsafeFlags([libraryPath])]),
        .target(name: "XLaserV8", dependencies: ["CV8Bridge", .product(name: "XLaser", package: "XLaser")]),
        .executableTarget(name: "XLaserV8Bench", dependencies: ["XLaserV8", .product(name: "XLaser", package: "XLaser")]),
        .testTarget(name: "XLaserV8Tests", dependencies: ["XLaserV8", .product(name: "XLaser", package: "XLaser")]),
    ],
    cxxLanguageStandard: .cxx20
)
