import XCTest
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// ASR-S03f2b — `alln serve status` / `alln serve --health` emit `ServeStatusJSON`
/// v2 with §5.3 exit codes. Injectable gatherer; no real host.
final class ServeStatusCLITests: XCTestCase {

    // MARK: - JSON parity (`status` vs `--health`)

    func testStatusAndHealthJSONAreByteIdentical() {
        let status = sampleStatus(state: .healthy, recovery: nil)
        let fromStatus = jsonOutput(opts: Options(["status", "--json"]), status: status)
        let fromHealth = jsonOutput(opts: Options(["--health", "--json"]), status: status)
        XCTAssertEqual(fromStatus, fromHealth)
    }

    func testJSONStdoutIsExactlyOneObject() throws {
        let status = sampleStatus(
            state: .degraded,
            recovery: .init(reasonCode: "SERVE_UNAVAILABLE", command: "alln serve repair"))
        let stdout = jsonOutput(opts: Options(["status", "--json"]), status: status)
        XCTAssertFalse(stdout.isEmpty)
        let decoded = try CoreJSON.decode(ServeStatusJSON.self, from: Data(stdout.utf8))
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.state, .degraded)
        XCTAssertEqual(stdout, AllnighterCLI.serveStatusJSONString(decoded))
    }

    // MARK: - §5.3 exit codes (faked status, no host)

    func testExitCodeHealthyIsZero() {
        XCTAssertEqual(
            AllnighterCLI.serveStatusExitCode(for: sampleStatus(state: .healthy, recovery: nil)),
            ExitCode.success)
    }

    func testExitCodeDisabledIsZero() {
        XCTAssertEqual(
            AllnighterCLI.serveStatusExitCode(for: sampleStatus(state: .disabled, recovery: nil)),
            ExitCode.success)
    }

    func testExitCodeDegradedIsUnavailable() {
        XCTAssertEqual(
            AllnighterCLI.serveStatusExitCode(for: sampleStatus(
                state: .degraded,
                recovery: .init(reasonCode: "SERVE_UNAVAILABLE", command: "alln serve repair"))),
            69)
    }

    func testExitCodeRequiresApprovalIsNoPerm() {
        XCTAssertEqual(
            AllnighterCLI.serveStatusExitCode(for: sampleStatus(
                state: .requiresApproval,
                recovery: .init(
                    reasonCode: "SERVE_REQUIRES_APPROVAL",
                    command: "Open System Settings > General > Login Items & Extensions and enable com.allnighter.resident-coordinator"))),
            77)
    }

    // MARK: - Human recovery line

    func testHealthyHumanOutputHasNoRecoveryLine() {
        let lines = AllnighterCLI.serveStatusHumanLines(
            for: sampleStatus(state: .healthy, recovery: nil))
        XCTAssertEqual(lines.first, "serve healthy")
        XCTAssertFalse(lines.contains(where: { $0.hasPrefix("alln serve") }))
    }

    func testDegradedHumanOutputEndsWithOneRecoveryCommand() {
        let command = "alln serve repair"
        let lines = AllnighterCLI.serveStatusHumanLines(for: sampleStatus(
            state: .degraded,
            recovery: .init(reasonCode: "SERVE_UNAVAILABLE", command: command)))
        XCTAssertEqual(lines.last, command)
        XCTAssertEqual(lines.filter { $0 == command }.count, 1)
    }

    func testRequiresApprovalHumanOutputEndsWithOneRecoveryCommand() {
        let command = "Open System Settings > General > Login Items & Extensions and enable com.allnighter.resident-coordinator"
        let lines = AllnighterCLI.serveStatusHumanLines(for: sampleStatus(
            state: .requiresApproval,
            recovery: .init(reasonCode: "SERVE_REQUIRES_APPROVAL", command: command)))
        XCTAssertEqual(lines.last, command)
    }

    // MARK: - Read-only (no writes)

    func testStatusPathPerformsNoWritesOnReadOnlyFilesystem() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("serve-status-cli-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gatherer = makeInjectedGatherer(root: root)
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let before = listFilePaths(under: coordDir)
        let status = gatherer.gather().status
        AllnighterCLI.emitServeStatus(opts: Options(["status", "--json"]), status: status)
        let after = listFilePaths(under: coordDir)
        XCTAssertEqual(before.sorted(), after.sorted())
    }

    func testServeStatusCommandIsRegistered() {
        let names = ContractRegistry.milestone1.commands.map(\.name)
        XCTAssertTrue(names.contains("serve status"))
        let serve = ContractRegistry.milestone1.commands.first { $0.name == "serve" }
        XCTAssertEqual(serve?.outputSchema, .serveStatusJSON)
    }

    // MARK: - Fixtures

    private func jsonOutput(opts: Options, status: ServeStatusJSON) -> String {
        XCTAssertTrue(opts.flag("json"))
        return AllnighterCLI.serveStatusJSONString(status)
    }

    private func sampleStatus(
        state: ServeStatusJSON.State,
        recovery: ServeStatusJSON.Recovery?
    ) -> ServeStatusJSON {
        ServeStatusJSON(
            schemaVersion: 2,
            desiredState: state == .disabled ? .disabled : .enabled,
            state: state,
            supervisor: .init(
                label: ServeLaunchAgentStatus.label,
                loaded: state != .disabled,
                authorization: state == .requiresApproval ? .requiresApproval : .enabled,
                pid: state == .disabled ? nil : 1234
            ),
            binary: .init(
                path: "/tmp/alln-test/.local/share/allnighter/bin/alln",
                expectedGitSha: "abc123",
                runningGitSha: "abc123",
                expectedCodeIdentity: .init(
                    cdhash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", version: "1.0.0"),
                runningCodeIdentity: .init(
                    cdhash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", version: "1.0.0"),
                matches: true
            ),
            daemon: .init(daemonId: "d1", pid: state == .disabled ? nil : 1234),
            schedulers: [],
            recovery: recovery
        )
    }

    private func makeInjectedGatherer(root: URL) -> ServeStatusGatherer {
        let t0 = Date(timeIntervalSince1970: 1_720_000_000)
        let t1 = Date(timeIntervalSince1970: 1_720_000_100)
        let sha = "abc123"
        let cdhash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let canonicalPath = "/tmp/alln-test/.local/share/allnighter/bin/alln"
        let label = ServeLaunchAgentStatus.label
        let coordDir = root.appendingPathComponent("Coordinator", isDirectory: true)
        let homeDir = root.appendingPathComponent("Home", isDirectory: true)
        let plistURL = homeDir
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")

        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coordDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: plistURL.path, contents: Data("plist".utf8))
        FileManager.default.createFile(atPath: URL(fileURLWithPath: canonicalPath).path, contents: Data([0xCF]))

        let store = ServeDaemonStore(directory: coordDir)
        try? store.save(.init(
            daemonId: "d1",
            pid: 1234,
            startedAt: t0,
            loopbackHost: "127.0.0.1",
            loopbackPort: 18743,
            binaryVersion: "1.0.0",
            binaryGitSha: sha,
            contractVersion: "1.0.0"
        ))

        let receipts = ServeRuntimeReceipts(directory: coordDir, clock: { t0 })
        let rows = ServeRuntimeReceipts.requiredSchedulerIds.sorted().map {
            ServeRuntimeReceipts.SchedulerRow(
                id: $0, state: .waiting, lastAttemptAt: t0, lastSuccessAt: t0,
                lastError: nil, nextWakeAt: t1)
        }
        _ = receipts.write(daemonId: "d1", pid: 1234, startedAt: t0, rows: rows)

        return ServeStatusGatherer(
            homeDirectory: homeDir,
            clock: { t1 },
            readDesiredState: { .present(state: .enabled, updatedAt: t0) },
            launchAgent: ServeLaunchAgentStatus(
                plistURL: plistURL,
                plistExists: { _ in true },
                printListing: { "state = running\npid = 1234\n" }
            ),
            readAuthorization: { _ in .enabled },
            healthClient: ServeHealthClient(transport: { _, _ in
                (Data("{\"daemonId\":\"d1\",\"pid\":1234}".utf8), 200)
            }),
            readReceipt: { receipts.read() },
            daemonStore: store,
            readCanonicalInstall: {
                .init(path: canonicalPath, expectedGitSha: sha, expectedCodeIdentity: .init(cdhash: cdhash, version: "1.0.0"))
            },
            readRunningCodeIdentity: { _ in .init(cdhash: cdhash, version: "1.0.0") },
            activeObligationCount: { 0 }
        )
    }

    private func listFilePaths(under directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            paths.append(url.path)
        }
        return paths
    }
}
