import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// C2: CLIDetector.ingestCensus verifies agent-discovered paths by running them
/// (health == runs) and prefers a stable launcher over an upgrade-fragile path.
///
/// Files are real (so `FileManager.isExecutableFile` passes), but the "run" is
/// mocked — the runner records which path was invoked and returns a version.
final class CensusIngestTests: XCTestCase {

    private actor PathRecorder: CommandRunner {
        private(set) var commands: [String] = []
        let stdout: String
        init(stdout: String) { self.stdout = stdout }
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            commands.append(command)
            return CommandResult(stdout: stdout, exitCode: 0)
        }
        func recorded() -> [String] { commands }
    }

    private func makeExecutable(_ path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
    }

    private func tmpRoot() throws -> String {
        let root = NSTemporaryDirectory() + "census-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    private func grokManifest(knownPaths: [String]) -> DriverManifest {
        DriverManifest(id: "grok", displayName: "Grok", kind: .headlessCLI,
                       detectCommand: "grok --version",
                       invoke: .init(command: "grok", args: []),
                       setup: SetupBlock(bins: ["grok"], knownPaths: knownPaths))
    }

    func testPrefersStableLauncherOverEphemeralCensusPath() async throws {
        let root = try tmpRoot()
        let ephemeral = "\(root)/.grok/downloads/grok-0.2.54-macos/grok"   // looksEphemeral
        let stable = "\(root)/stablebin/grok"                              // the upgrade-safe launcher
        try makeExecutable(ephemeral)
        try makeExecutable(stable)

        let census = try ToolCensus.parse("""
        { "grok": { "absolute_path": "\(ephemeral)", "version": "grok 0.2.54" } }
        """)
        let manifest = grokManifest(knownPaths: ["\(root)/stablebin"])
        let runner = PathRecorder(stdout: "grok 0.2.54")
        let det = CLIDetector(commandRunner: runner, home: root)

        let records = await det.ingestCensus(census, manifests: [manifest], models: [:],
                                             now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.invocation, .direct(path: stable),
                       "ingest must cache the stable launcher, not the /downloads blob")
        let invoked = await runner.recorded()
        XCTAssertEqual(invoked.first, stable, "the stable path is the one we actually ran")
        XCTAssertFalse(invoked.contains(ephemeral), "the ephemeral path should never be run when a stable one verifies")
    }

    func testVerifiesStableCensusPathDirectly() async throws {
        let root = try tmpRoot()
        let path = "\(root)/.local/bin/grok"   // already stable → used as-is
        try makeExecutable(path)

        let census = try ToolCensus.parse("""
        { "grok": { "absolute_path": "\(path)", "version": "grok 0.2.54" } }
        """)
        let runner = PathRecorder(stdout: "grok 0.2.54")
        let det = CLIDetector(commandRunner: runner, home: root)

        let records = await det.ingestCensus(census, manifests: [grokManifest(knownPaths: [])],
                                             models: [:], now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(records.first?.invocation, .direct(path: path))
        XCTAssertEqual(records.first?.status.kind, .installedNotProbed)
    }

    func testMissingCensusPathFallsBackToNotInstalled() async throws {
        let root = try tmpRoot()
        let census = try ToolCensus.parse("""
        { "grok": { "absolute_path": "\(root)/does/not/exist/grok", "version": "x" } }
        """)
        let runner = PathRecorder(stdout: "x")
        let det = CLIDetector(commandRunner: runner, home: root)

        let records = await det.ingestCensus(census, manifests: [grokManifest(knownPaths: [])],
                                             models: [:], now: .init(timeIntervalSince1970: 0), smoke: false)

        XCTAssertEqual(records.first?.status, .notInstalled)
        let invoked = await runner.recorded()
        XCTAssertTrue(invoked.isEmpty, "a non-existent path must never be executed")
    }
}
