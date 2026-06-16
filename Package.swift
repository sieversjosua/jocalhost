// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "jocalhost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalhostCore", targets: ["LocalhostCore"]),
        .executable(name: "jocalhost", targets: ["LocalhostApp"]),
        .executable(name: "jocalhostctl", targets: ["LocalhostCLI"]),
        .executable(name: "jocalhost-mcp", targets: ["LocalhostMCP"]),
        .executable(name: "jocalhost-checks", targets: ["LocalhostChecks"])
    ],
    targets: [
        .target(
            name: "LocalhostCore"
        ),
        .executableTarget(
            name: "LocalhostApp",
            dependencies: ["LocalhostCore"]
        ),
        .executableTarget(
            name: "LocalhostCLI",
            dependencies: ["LocalhostCore"]
        ),
        .executableTarget(
            name: "LocalhostMCP",
            dependencies: ["LocalhostCore"]
        ),
        .executableTarget(
            name: "LocalhostChecks",
            dependencies: ["LocalhostCore"]
        ),
        .testTarget(
            name: "LocalhostCoreTests",
            dependencies: ["LocalhostCore"]
        ),
    ]
)
