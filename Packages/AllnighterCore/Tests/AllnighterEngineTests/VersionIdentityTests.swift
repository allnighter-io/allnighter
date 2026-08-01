import XCTest
import AllnighterCore
@testable import AllnighterCLI

/// ADP-S05 — single source of truth for the binary version. Before this
/// slice, `AllnighterCLI.binaryVersion` and the Codex `clientInfo` handshake
/// each hardcoded their own `"0.9.0"` literal — a drift risk (bump one, forget
/// the other). Both now project `AllnighterVersionIdentity.binaryVersion`.
/// This is a drift *gate*, not a Linux-port test — it scans the same CLI
/// chain sources tree `PortabilityHygieneTests` does.
final class VersionIdentityTests: XCTestCase {

    /// Single-source: the CLI-facing constant is exactly the Core identity —
    /// no independent literal to drift out of sync.
    func testCLIBinaryVersionProjectsVersionIdentity() {
        XCTAssertEqual(AllnighterCLI.binaryVersion, AllnighterVersionIdentity.binaryVersion)
    }

    /// The Codex `app-server` handshake's `clientInfo.version` must be the
    /// same single-sourced constant, not an independent literal.
    func testCodexHandshakeProjectsVersionIdentity() throws {
        let line = Codex.initialize(id: 1)
        XCTAssertTrue(
            line.contains("\"version\":\"\(AllnighterVersionIdentity.binaryVersion)\""),
            "Codex.initialize() clientInfo.version must equal AllnighterVersionIdentity.binaryVersion; got: \(line)"
        )
        XCTAssertFalse(line.contains("0.9.0"), "Codex handshake must not carry the retired 0.9.0 literal")
    }

    /// Bump rule (Agent_Dogfood_Papercuts.md §Version rule): LVC-S05
    /// (`docs/phases/Loop_Verb_Cutover.md`) bumps 0.10.7 → 0.11.0 because
    /// `contractVersion` takes its major cut (6.13.0 → 7.0.0) — `pair relay*`/
    /// `pair pilot*` retire behind one `alln loop` verb and the `PMMode` wire
    /// enum is deleted. Pin the value so an accidental revert is caught here,
    /// not discovered downstream.
    func testCurrentBinaryVersionIsBumped() {
        XCTAssertEqual(AllnighterVersionIdentity.binaryVersion, "0.11.4")
    }

    /// Drift gate: no OTHER hardcoded `"0.9.0"` string literal survives in the
    /// alln CLI chain sources (AllnighterCore, AllnighterEngine, AllnighterCLI).
    /// Every binary-version/clientInfo field must project
    /// `AllnighterVersionIdentity.binaryVersion` instead of carrying its own
    /// literal. Matches on the quoted literal `"0.9.0"` so it does not
    /// false-positive on unrelated test fixtures like `"0.9.0-test"`.
    func testNoHardcodedOldVersionLiteralInCLIChainSources() throws {
        var violations: [String] = []
        for target in Self.cliChainTargets {
            let dir = sourcesRoot().appendingPathComponent(target)
            let files = try swiftFiles(under: dir)
            XCTAssertFalse(files.isEmpty, "no Swift sources under \(dir.path) — target moved? update this gate")
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (index, raw) in text.components(separatedBy: "\n").enumerated() {
                    if raw.contains("\"0.9.0\"") {
                        violations.append("\(file.lastPathComponent):\(index + 1): \(raw.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, """
        Hardcoded "0.9.0" literal(s) found in the alln CLI chain sources — \
        project AllnighterVersionIdentity.binaryVersion instead:
        \(violations.joined(separator: "\n"))
        """)
    }

    // MARK: - Sources-tree scan (mirrors PortabilityHygieneTests)

    private static let cliChainTargets = ["AllnighterCore", "AllnighterEngine", "AllnighterCLI"]

    private func sourcesRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Sources")
    }

    private func swiftFiles(under dir: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
