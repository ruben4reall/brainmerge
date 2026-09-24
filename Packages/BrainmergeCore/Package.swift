// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrainmergeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrainmergeCore", targets: ["BrainmergeCore"]),
        .library(name: "BrainmergeTestSupport", targets: ["BrainmergeTestSupport"]),
        .executable(name: "brainmerge", targets: ["brainmerge"]),
        .executable(name: "launcher", targets: ["launcher"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BrainmergeCore"),
        .executableTarget(name: "brainmerge", dependencies: [
            "BrainmergeCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .executableTarget(name: "launcher"),
        .target(name: "BrainmergeTestSupport", dependencies: ["BrainmergeCore"]),
        .testTarget(name: "BrainmergeCoreTests", dependencies: ["BrainmergeCore", "BrainmergeTestSupport"]),
    ]
)
