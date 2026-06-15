// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AllnighterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AllnighterCore", targets: ["AllnighterCore"]),
        .library(name: "AllnighterEngine", targets: ["AllnighterEngine"]),
        .executable(name: "prove-cli", targets: ["ProveCLI"]),
        .executable(name: "alln", targets: ["AllnighterCLI"])
    ],
    targets: [
        .target(
            name: "AllnighterCore",
            resources: [.copy("Resources/Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AllnighterCoreTests",
            dependencies: ["AllnighterCore"]
        ),
        // Execution layer: subprocess fan-out + coordination. Depends on Core;
        // contains all the I/O so Core stays pure. The Mac app imports this.
        .target(
            name: "AllnighterEngine",
            dependencies: ["AllnighterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AllnighterEngineTests",
            dependencies: ["AllnighterEngine", "AllnighterCore"]
        ),
        // Live CLI smoke proof — `swift run prove-cli` from repo root.
        .executableTarget(
            name: "ProveCLI",
            dependencies: ["AllnighterEngine", "AllnighterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Team-as-Tool (RB6): the `alln` CLI / MCP stdio surface. Links
        // only the team engine — no dispatch/executor modules (judgment only).
        .executableTarget(
            name: "AllnighterCLI",
            dependencies: ["AllnighterEngine", "AllnighterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
