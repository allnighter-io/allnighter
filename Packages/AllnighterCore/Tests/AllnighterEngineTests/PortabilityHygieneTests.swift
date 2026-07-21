import XCTest

/// Portability hygiene gate for the `alln` CLI dependency chain
/// (AllnighterCore, AllnighterEngine, AllnighterCLI): Apple-only framework
/// imports must sit inside `#if canImport(...)` so the eventual Linux port
/// stays a bounded, pre-paid step instead of silently growing. Hygiene rule,
/// not a Linux support promise — there is no Linux CI and the non-Apple
/// branches are unverified until a port phase opens.
///
/// Established guard shapes:
///
///     #if canImport(CryptoKit)        #if canImport(Darwin)
///     import CryptoKit                import Darwin
///     #else                           #elseif canImport(Glibc)
///     import Crypto                   import Glibc
///     #endif                          #endif
///
/// ImageIO/CoreGraphics/UniformTypeIdentifiers have no Linux equivalent:
/// gate the whole feature (see `AttachmentIngestor`).
final class PortabilityHygieneTests: XCTestCase {

    /// Frameworks that do not exist on Linux. Foundation, FoundationNetworking,
    /// Dispatch, and CryptoKit-behind-guard are fine; anything here at #if
    /// depth 0 is a violation.
    private static let appleOnlyModules: Set<String> = [
        "CryptoKit", "Darwin", "ImageIO", "CoreGraphics",
        "UniformTypeIdentifiers", "AppKit", "UIKit", "SwiftUI", "Cocoa",
        "Security", "UserNotifications", "ScreenCaptureKit",
        "AuthenticationServices", "Carbon", "Combine", "IOKit",
        "CoreServices", "CoreImage", "Metal", "AVFoundation", "WebKit",
        "os", "OSLog", "MachO", "XPC", "CoreFoundation",
    ]

    /// The targets linked into the `alln` executable (this package's side;
    /// the AgentOS side is Foundation-only by its own package contract).
    private static let cliChainTargets = ["AllnighterCore", "AllnighterEngine", "AllnighterCLI"]

    private func sourcesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Sources")
    }

    func testNoUnguardedAppleOnlyImportsInCLIChain() throws {
        var violations: [String] = []
        for target in Self.cliChainTargets {
            let dir = sourcesRoot().appendingPathComponent(target)
            let files = try swiftFiles(under: dir)
            XCTAssertFalse(files.isEmpty, "no Swift sources under \(dir.path) — target moved? update this gate")
            for file in files {
                violations.append(contentsOf: try unguardedImports(in: file))
            }
        }
        XCTAssertTrue(violations.isEmpty, """
        Unguarded Apple-only imports in the alln CLI chain:
        \(violations.joined(separator: "\n"))
        Wrap the import in `#if canImport(<Module>)` (CryptoKit gets an \
        `#else`/`import Crypto` arm, Darwin gets `#elseif canImport(Glibc)`); \
        for frameworks with no Linux analogue, gate the whole feature.
        """)
    }

    private func swiftFiles(under dir: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func unguardedImports(in file: URL) throws -> [String] {
        let text = try String(contentsOf: file, encoding: .utf8)
        var depth = 0
        var violations: [String] = []
        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#if") { depth += 1; continue }
            if line.hasPrefix("#endif") { depth = max(0, depth - 1); continue }
            guard depth == 0, let module = importedModule(line) else { continue }
            if Self.appleOnlyModules.contains(module) {
                violations.append("\(file.lastPathComponent):\(index + 1): import \(module)")
            }
        }
        return violations
    }

    /// Extracts the top-level module from an import line, tolerating
    /// attributes (`@preconcurrency import Darwin`), access modifiers, and
    /// scoped imports (`import struct Foundation.Data` → Foundation).
    private func importedModule(_ line: String) -> String? {
        var tokens = line.split(separator: " ").map(String.init)
        while let first = tokens.first,
              first.hasPrefix("@") || ["public", "internal", "package", "private", "fileprivate"].contains(first) {
            tokens.removeFirst()
        }
        guard tokens.first == "import", tokens.count >= 2 else { return nil }
        var moduleToken = tokens[1]
        if ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"].contains(moduleToken) {
            guard tokens.count >= 3 else { return nil }
            moduleToken = tokens[2]
        }
        return moduleToken.split(separator: ".").first.map(String.init)
    }
}
