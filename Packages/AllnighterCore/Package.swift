// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AllnighterCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "AllnighterCore", targets: ["AllnighterCore"]),
        .library(name: "AllnighterEngine", targets: ["AllnighterEngine"]),
        .executable(name: "prove-cli", targets: ["ProveCLI"]),
        .executable(name: "alln", targets: ["AllnighterCLI"])
    ],
    dependencies: [
        // AgentOS — the shared local-AI runtime. Allnighter is consumer #1;
        // the CLI-runtime primitives are being seeded into AgentOSCLI (roadmap P1)
        // and consumed back here. Local path dependency (sibling repo).
        .package(path: "../../../AgentOS")
    ],
    targets: [
        .target(
            name: "CCommonCrypto",
            path: "Sources/CCommonCrypto",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AllnighterCore",
            dependencies: [
                .product(name: "AgentOSCLI", package: "AgentOS"),
                .product(name: "AgentOSTeam", package: "AgentOS"),
                "CCommonCrypto",
            ],
            resources: [
                .copy("Resources/Fixtures"),
                .copy("Resources/Recipes"),
                .copy("Resources/Catalog/catalog_overlay.json"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            plugins: ["BuildInfoPlugin"]
        ),
        .testTarget(
            name: "AllnighterCoreTests",
            dependencies: ["AllnighterCore", "AllnighterEngine", "CCommonCrypto"]
        ),
        // Execution layer: subprocess team coordination. Depends on Core;
        // contains all the I/O so Core stays pure. The Mac app imports this.
        .target(
            name: "AllnighterEngine",
            dependencies: [
                "AllnighterCore",
                .product(name: "AgentOSCLI", package: "AgentOS"),
                .product(name: "AgentOSTeam", package: "AgentOS")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AllnighterEngineTests",
            dependencies: ["AllnighterEngine", "AllnighterCore", "AllnighterCLI"]
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
        ),
        .plugin(
            name: "BuildInfoPlugin",
            capability: .buildTool()
        )
    ]
)
