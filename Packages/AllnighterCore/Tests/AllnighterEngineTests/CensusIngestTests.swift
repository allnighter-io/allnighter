import XCTest
import AllnighterCore
import AgentOSCLI
@testable import AllnighterEngine

/// C2: CensusIngest verifies agent-discovered paths by running them
/// (health == runs) and prefers a stable launcher over an upgrade-fragile path.
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

    private func detector(runner: CommandRunner, home: String) -> CLIDetector {
        CLIDetector(
            commandRunner: runner,
            home: home,
            workingDirectory: AllnighterPaths.ensuredProbeScratchPath()
        )
    }

    func testPrefersStableLauncherOverEphemeralCensusPath() async throws {
        let root = try tmpRoot()
        let ephemeral = "\(root)/.grok/downloads/grok-0.2.54-macos/grok"
        let stable = "\(root)/stablebin/grok"
        try makeExecutable(ephemeral)
        try makeExecutable(stable)

        let census = try ToolCensus.parse("""
        { "grok": { "absolute_path": "\(ephemeral)", "version": "grok 0.2.54" } }
        """)
        let manifest = grokManifest(knownPaths: ["\(root)/stablebin"])
        let runner = PathRecorder(stdout: "grok 0.2.54")
        let det = detector(runner: runner, home: root)

        let records = await CensusIngest.ingest(
            census, manifests: [manifest], models: [:],
            now: .init(timeIntervalSince1970: 0), smoke: false,
            detector: det, home: root
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.invocation, .direct(path: stable))
        let invoked = await runner.recorded()
        XCTAssertEqual(invoked.first, stable)
        XCTAssertFalse(invoked.contains(ephemeral))
    }

    func testVerifiesStableCensusPathDirectly() async throws {
        let root = try tmpRoot()
        let path = "\(root)/.local/bin/grok"
        try makeExecutable(path)

        let census = try ToolCensus.parse("""
        { "grok": { "absolute_path": "\(path)", "version": "grok 0.2.54" } }
        """)
        let runner = PathRecorder(stdout: "grok 0.2.54")
        let det = detector(runner: runner, home: root)

        let records = await CensusIngest.ingest(
            census, manifests: [grokManifest(knownPaths: [])],
            models: [:], now: .init(timeIntervalSince1970: 0), smoke: false,
            detector: det, home: root
        )

        XCTAssertEqual(records.first?.invocation, .direct(path: path))
        XCTAssertEqual(records.first?.status.kind, .installedNotProbed)
    }

    func testMissingCensusPathFallsBackToNotInstalled() async throws {
        let root = try tmpRoot()
        let census = try ToolCensus.parse("""
        { "grok": { "absolute_path": "\(root)/does/not/exist/grok", "version": "x" } }
        """)
        let runner = PathRecorder(stdout: "x")
        let det = detector(runner: runner, home: root)

        let records = await CensusIngest.ingest(
            census, manifests: [grokManifest(knownPaths: [])],
            models: [:], now: .init(timeIntervalSince1970: 0), smoke: false,
            detector: det, home: root
        )

        XCTAssertEqual(records.first?.status, .notInstalled)
        let invoked = await runner.recorded()
        XCTAssertTrue(invoked.isEmpty)
    }

    // MARK: - notInstalled must not clobber still-valid ready

    func testUnresolvedPassRetainsPriorReadyWhenPathStillExecutable() async throws {
        let root = try tmpRoot()
        let path = "\(root)/.opencode/bin/opencode"
        try makeExecutable(path)
        let prior = ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: "1.18.16"),
            invocation: .direct(path: path),
            version: "1.18.16",
            lastProbeAt: Date(timeIntervalSince1970: 100),
            lastDetectedAt: Date(timeIntervalSince1970: 100)
        )
        let census = try ToolCensus.parse("""
        { "opencode": { "absolute_path": "\(root)/missing/opencode", "version": "x" } }
        """)
        let manifest = DriverManifest(
            id: "opencode", displayName: "OpenCode", kind: .headlessCLI,
            detectCommand: "opencode --version",
            invoke: .init(command: "opencode", args: []),
            setup: SetupBlock(bins: ["opencode"], knownPaths: [])
        )
        let runner = PathRecorder(stdout: "x")
        let det = detector(runner: runner, home: root)
        let now = Date(timeIntervalSince1970: 200)

        let records = await CensusIngest.ingest(
            census, manifests: [manifest], models: [:], now: now, smoke: false,
            detector: det, home: root, priorRecords: [prior]
        )

        XCTAssertEqual(records.first?.status, .ready(version: "1.18.16"))
        XCTAssertEqual(records.first?.invocation, .direct(path: path))
        XCTAssertEqual(records.first?.failureCode, ProbeRecordMerge.retainedReadyFailureCode)
        let invoked = await runner.recorded()
        XCTAssertTrue(invoked.isEmpty)
    }

    func testUnresolvedPassReportsNotInstalledWhenPriorPathDeleted() async throws {
        let root = try tmpRoot()
        let gone = "\(root)/.opencode/bin/opencode"
        let prior = ToolProbeRecord(
            driverId: "opencode",
            status: .ready(version: "1.18.16"),
            invocation: .direct(path: gone),
            version: "1.18.16",
            lastProbeAt: Date(timeIntervalSince1970: 100)
        )
        let census = try ToolCensus.parse("""
        { "opencode": { "absolute_path": "\(root)/missing/opencode", "version": "x" } }
        """)
        let manifest = DriverManifest(
            id: "opencode", displayName: "OpenCode", kind: .headlessCLI,
            detectCommand: "opencode --version",
            invoke: .init(command: "opencode", args: []),
            setup: SetupBlock(bins: ["opencode"], knownPaths: [])
        )
        let runner = PathRecorder(stdout: "x")
        let det = detector(runner: runner, home: root)

        let records = await CensusIngest.ingest(
            census, manifests: [manifest], models: [:],
            now: .init(timeIntervalSince1970: 200), smoke: false,
            detector: det, home: root, priorRecords: [prior]
        )

        XCTAssertEqual(records.first?.status, .notInstalled)
    }

    func testUnresolvedPassReportsNotInstalledWhenNoPrior() async throws {
        let root = try tmpRoot()
        let census = try ToolCensus.parse("""
        { "qwen": { "absolute_path": "\(root)/missing/qwen", "version": "x" } }
        """)
        let manifest = DriverManifest(
            id: "qwen", displayName: "Qwen", kind: .headlessCLI,
            detectCommand: "qwen --version",
            invoke: .init(command: "qwen", args: []),
            setup: SetupBlock(bins: ["qwen"], knownPaths: [])
        )
        let runner = PathRecorder(stdout: "x")
        let det = detector(runner: runner, home: root)

        let records = await CensusIngest.ingest(
            census, manifests: [manifest], models: [:],
            now: .init(timeIntervalSince1970: 200), smoke: false,
            detector: det, home: root, priorRecords: []
        )

        XCTAssertEqual(records.first?.status, .notInstalled)
    }

    func testResolvedCensusPathStillYieldsVersionedRecord() async throws {
        let root = try tmpRoot()
        let path = "\(root)/.local/bin/opencode"
        try makeExecutable(path)
        let census = try ToolCensus.parse("""
        { "opencode": { "absolute_path": "\(path)", "version": "1.18.16" } }
        """)
        let manifest = DriverManifest(
            id: "opencode", displayName: "OpenCode", kind: .headlessCLI,
            detectCommand: "opencode --version",
            invoke: .init(command: "opencode", args: []),
            setup: SetupBlock(bins: ["opencode"], knownPaths: [])
        )
        let runner = PathRecorder(stdout: "1.18.16")
        let det = detector(runner: runner, home: root)

        let records = await CensusIngest.ingest(
            census, manifests: [manifest], models: [:],
            now: .init(timeIntervalSince1970: 200), smoke: false,
            detector: det, home: root
        )

        XCTAssertEqual(records.first?.status, .installedNotProbed(version: "1.18.16"))
        XCTAssertEqual(records.first?.invocation, .direct(path: path))
        XCTAssertEqual(records.first?.version, "1.18.16")
    }
}
