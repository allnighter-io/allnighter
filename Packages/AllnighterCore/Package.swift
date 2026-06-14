// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AllnighterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AllnighterCore", targets: ["AllnighterCore"]),
        .library(name: "AllnighterEngine", targets: ["AllnighterEngine"])
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
        )
    ]
)
