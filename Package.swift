// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "altertable-swift",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "Altertable",
            targets: ["Altertable"]),
    ],
    dependencies: [
        // No external dependencies for now
    ],
    targets: [
        .target(
            name: "Altertable",
            dependencies: []),
        .testTarget(
            name: "AltertableTests",
            dependencies: ["Altertable"]),
    ]
)
