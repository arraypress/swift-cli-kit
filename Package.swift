// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CLIKit",
    // Apple silicon, modern macOS only. macOS 14 is the floor because it is the
    // oldest release Apple still ships security updates for and the oldest
    // Homebrew officially supports — going lower would buy compatibility with
    // machines that cannot install these tools anyway.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CLIKit",
            targets: ["CLIKit"]
        ),
        // Builds the family's combined manifest. Lives here because the merge
        // logic belongs with the manifest type it merges.
        .executable(
            name: "agentic-index",
            targets: ["AgenticIndex"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CLIKit",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "AgenticIndex",
            dependencies: ["CLIKit"]
        ),
        .testTarget(
            name: "CLIKitTests",
            dependencies: ["CLIKit"]
        ),
    ]
)
