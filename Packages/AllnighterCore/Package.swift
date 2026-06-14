// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AllnighterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AllnighterCore", targets: ["AllnighterCore"])
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
        )
    ]
)
