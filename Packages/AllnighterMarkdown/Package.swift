// swift-tools-version:5.9
import PackageDescription

// AllnighterMarkdown — Allnighter's owned, themeable Markdown renderer.
//
// Forked from gonzalezreal/swift-markdown-ui (MIT) + gonzalezreal/NetworkImage
// (MIT) — vendored into this repo so we own and evolve the renderer ourselves
// (Cursor-quality rendering of agent output across the Inbox and the Floor),
// rather than depending on a third-party tool. We deliberately do NOT reinvent
// the Markdown parser: parsing stays on swiftlang/swift-cmark (the standard
// cmark-gfm), the one wheel worth keeping. See LICENSE-* for attribution.
let package = Package(
    name: "AllnighterMarkdown",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "AllnighterMarkdown", targets: ["AllnighterMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.4.0"),
    ],
    targets: [
        .target(name: "NetworkImage"),
        .target(
            name: "AllnighterMarkdown",
            dependencies: [
                "NetworkImage",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
    ]
)
