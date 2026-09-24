// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BrainmergeUI",
    platforms: [.macOS(.v26)],
    products: [.library(name: "BrainmergeUI", targets: ["BrainmergeUI"])],
    dependencies: [.package(path: "../BrainmergeCore")],
    targets: [
        .target(name: "BrainmergeUI", dependencies: [.product(name: "BrainmergeCore", package: "BrainmergeCore")]),
        .testTarget(name: "BrainmergeUITests", dependencies: [
            "BrainmergeUI",
            .product(name: "BrainmergeTestSupport", package: "BrainmergeCore"),
        ]),
    ]
)
