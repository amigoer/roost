// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoostCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RoostCore", targets: ["RoostCore"])
    ],
    targets: [
        .target(name: "RoostCore"),
        .testTarget(name: "RoostCoreTests", dependencies: ["RoostCore"])
    ]
)
