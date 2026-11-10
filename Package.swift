// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaserScriptKit",
    products: [
        .library(name: "LaserScriptKit", targets: ["LaserScriptKit"]),
        .library(name: "LaserScriptKitApple", targets: ["LaserScriptKitApple"]),
    ],
    targets: [
        .target(name: "LaserScriptKit"),
        .target(name: "LaserScriptKitApple", dependencies: ["LaserScriptKit"], path: "Sources/Apple"),
        .testTarget(name: "LaserScriptKitAppleTests", dependencies: ["LaserScriptKitApple", "LaserScriptKit"]),
    ]
)
