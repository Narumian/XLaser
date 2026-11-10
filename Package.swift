// swift-tools-version: 6.0
import PackageDescription
import Foundation

let environment = ProcessInfo.processInfo.environment
let v8Include = environment["XLASER_V8_INCLUDE"] ?? ""
let v8Library = environment["XLASER_V8_LIBRARY"] ?? ""
let v8Flags = (environment["XLASER_V8_CXX_FLAGS"] ?? "").split(separator: " ").map(String.init)
let v8Enabled = !v8Include.isEmpty && !v8Library.isEmpty
let v8CXXSettings: [CXXSetting] = v8Enabled ? [.define("XLASER_V8_ENABLED"), .unsafeFlags(["-I", v8Include] + v8Flags)] : []
let v8LinkerSettings: [LinkerSetting] = v8Enabled ? [.unsafeFlags([v8Library])] : []

let package = Package(
    name: "XLaser",
    products: [
        .library(name: "XLaser", targets: ["XLaser"]),
        .library(name: "XLaserApple", targets: ["XLaserApple"]),
        .library(name: "XLaserV8", targets: ["XLaserV8"]),
        .library(name: "LaserCubeImplementation", targets: ["LaserCubeImplementation"]),
    ],
    targets: [
        .target(name: "XLaser", resources: [.copy("Resources/LaserScript.js")]),
        .target(name: "LaserCubeImplementation", dependencies: ["XLaser"]),
        .target(name: "XLaserApple", dependencies: ["XLaser"], path: "Sources/Apple"),
        .target(name: "CV8Bridge", cxxSettings: v8CXXSettings, linkerSettings: v8LinkerSettings),
        .target(name: "XLaserV8", dependencies: ["XLaser", "CV8Bridge"], path: "Sources/V8"),
        .executableTarget(name: "LaserScriptBench", dependencies: ["XLaser", "XLaserApple"], path: "Benchmarks"),
        .executableTarget(name: "XLaserV8Bench", dependencies: ["XLaser", "XLaserV8"], path: "Tools/V8Bench"),
        .testTarget(name: "XLaserTests", dependencies: ["XLaser"]),
        .testTarget(name: "LaserCubeImplementationTests", dependencies: ["LaserCubeImplementation", "XLaser"]),
        .testTarget(name: "XLaserAppleTests", dependencies: ["XLaserApple", "XLaser"]),
        .testTarget(name: "XLaserV8Tests", dependencies: ["XLaserV8", "XLaser"]),
    ],
    cxxLanguageStandard: .cxx20
)
