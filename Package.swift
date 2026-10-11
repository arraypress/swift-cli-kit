// swift-tools-version: 6.2
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
            ],
            swiftSettings: [
                // Async functions run on the caller's executor rather than hopping
                // to the global pool — Swift 6.2's "nonisolated nonsending"
                // default. It also makes closures like DiskCache.cached's
                // `produce` nonsending, so a command adopting the same default
                // can capture itself in them.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .executableTarget(
            name: "AgenticIndex",
            dependencies: ["CLIKit"]
        ),
        .testTarget(
            name: "CLIKitTests",
            dependencies: [
                "CLIKit",
                // For the MCP round-trip tests, which parse a generated argv
                // with a real command to prove the two layers agree.
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
