// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XLaser",
    products: [
        .library(name: "XLaser", targets: ["XLaser"]),
        .library(name: "XLaserApple", targets: ["XLaserApple"]),
    ],
    targets: [
        .target(name: "XLaser"),
        .target(name: "XLaserApple", dependencies: ["XLaser"], path: "Sources/Apple"),
        .executableTarget(name: "LaserScriptBench", dependencies: ["XLaser", "XLaserApple"], path: "Benchmarks"),
        .testTarget(name: "XLaserTests", dependencies: ["XLaser"]),
        .testTarget(name: "XLaserAppleTests", dependencies: ["XLaserApple", "XLaser"]),
    ]
)
