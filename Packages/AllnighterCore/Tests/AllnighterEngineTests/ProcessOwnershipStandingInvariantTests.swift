import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PO-F4 works tests: harness-owned standing invariants (contract-freshness gate).
///
/// Uses fixture/temp scratch + a scripted proof `CommandRunner` so tests do not
/// depend on the real repo being dirty or on a live `alln` product.
final class ProcessOwnershipStandingInvariantTests: XCTestCase {

    override func tearDown() {
        ProcessOwnership.terminateSignalHook = nil
        ProcessOwnership.TurnOwnerDirectory.shared.set(nil)
        super.tearDown()
    }

    // MARK: - StandingInvariants.run (unit, fixture scratch)

    func testStaleContractsFailStandingInvariantWithMarkers() async throws {
        let tmp = makeTempRoot("po-f4-stale")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repo = try makeGitRepo(in: tmp)
        let scratch = tmp.appendingPathComponent("scratch", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        try plantFakeAlln(scratchPath: scratch)

        let runner = StandingProofScriptRunner(checkExitCode: 1, checkTail: "contract drift: docs/generated/alln/* stale")
        let service = ProjectVerificationService(
            commandRunner: runner,
            perCommandTimeoutSeconds: 5
        )

        let outcome = await StandingInvariants.run(
            service: service,
            repoRoot: repo.path,
            scratchPath: scratch
        )

        XCTAssertEqual(outcome.failed, [StandingInvariants.contractDrift])
        XCTAssertEqual(outcome.results.count, 1)
        let r = try XCTUnwrap(outcome.results.first)
        XCTAssertTrue(r.standing, "standing marker required on harness-injected proof")
        XCTAssertEqual(r.invariant, StandingInvariants.contractDrift)
        XCTAssertFalse(r.passed)
        XCTAssertEqual(r.exitCode, 1)
        XCTAssertTrue(
            runner.capturedShellCommands.contains { $0.contains("export-contracts --check") },
            "must invoke export-contracts --check via the proof runner path: \(runner.capturedShellCommands)"
        )
        XCTAssertTrue(
            runner.capturedShellCommands.contains { $0.contains("alln") || $0.contains(scratch) },
            "must use the turn-tree alln under scratch, not a bare global alln: \(runner.capturedShellCommands)"
        )
        // No rebuild when product already present.
        XCTAssertFalse(
            runner.capturedShellCommands.contains { $0.contains("swift build") },
            "must reuse existing scratch alln product"
        )
    }

    func testCleanContractsPassStandingInvariantNoFailed() async throws {
        let tmp = makeTempRoot("po-f4-clean")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repo = try makeGitRepo(in: tmp)
        let scratch = tmp.appendingPathComponent("scratch", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        try plantFakeAlln(scratchPath: scratch)

        let runner = StandingProofScriptRunner(checkExitCode: 0, checkTail: "contracts fresh")
        let service = ProjectVerificationService(
            commandRunner: runner,
            perCommandTimeoutSeconds: 5
        )

        let outcome = await StandingInvariants.run(
            service: service,
            repoRoot: repo.path,
            scratchPath: scratch
        )

        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertEqual(outcome.results.count, 1)
        let r = try XCTUnwrap(outcome.results.first)
        XCTAssertTrue(r.standing)
        XCTAssertEqual(r.invariant, StandingInvariants.contractDrift)
        XCTAssertTrue(r.passed)
        XCTAssertEqual(r.exitCode, 0)
    }

    func testMissingAllnProductBuildsThenChecks() async throws {
        let tmp = makeTempRoot("po-f4-build")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repo = try makeGitRepo(in: tmp)
        let scratch = tmp.appendingPathComponent("scratch", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        // No alln planted — runner plants it on the first swift build.

        let runner = StandingProofScriptRunner(
            checkExitCode: 0,
            checkTail: "ok",
            plantAllnOnBuild: true,
            plantScratchPath: scratch
        )
        let service = ProjectVerificationService(
            commandRunner: runner,
            perCommandTimeoutSeconds: 5
        )

        let outcome = await StandingInvariants.run(
            service: service,
            repoRoot: repo.path,
            scratchPath: scratch
        )

        XCTAssertTrue(outcome.failed.isEmpty, "failed: \(outcome.failed) tails: \(outcome.results.map(\.outputTail))")
        XCTAssertTrue(
            runner.capturedShellCommands.contains { $0.contains("swift build") && $0.contains("--product alln") },
            "must build alln on scratch when product missing: \(runner.capturedShellCommands)"
        )
        XCTAssertTrue(
            runner.capturedShellCommands.contains { $0.contains("export-contracts --check") }
        )
        XCTAssertNotNil(StandingInvariants.findAllnProduct(scratchPath: scratch))
    }

    // MARK: - Full relay path (zero proofCommands still runs standing)

    func testDeliveredTurnWithStaleContractsSurfacesStandingFailed() async throws {
        let tmp = makeTempRoot("po-f4-relay-stale")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let support = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let repo = try makeGitRepo(in: tmp)
        let scratch = ExecutionLaneFlock.ensuredScratchPath(repoRoot: repo.path)
        try plantFakeAlln(scratchPath: scratch)

        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let lane = ExecutionLaneRegistry()

        // Zero declared proofCommands — standing must still run.
        let report = "Implemented the registry change. Committed."
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Review.\n\n```json\n{\"verdict\": \"continue\", \"handover\": \"Ship it.\"}\n```"),
            .init(stdout: "Still not clean.\n\n```json\n{\"verdict\": \"done\", \"note\": \"Stop.\"}\n```"),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: report),
        ]
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore, writeLock: lane
        )
        let proofRunner = StandingProofScriptRunner(
            checkExitCode: 1,
            checkTail: "stale docs/generated/alln/alln-contract.json"
        )
        let coordinator = RelayCoordinator(
            runService: service,
            stateStore: stateStore,
            runStore: runStore,
            executionLane: lane,
            proofCommandRunner: proofRunner
        )

        let state = try await coordinator.run(config: .init(
            projectRoot: repo.path,
            docPath: "docs/spec.md",
            pmWorkerId: "model_pm",
            devWorkerId: "model_dev",
            maxRounds: 5
        )).get()

        let devRound = try XCTUnwrap(state.rounds.first { $0.devRunId != nil })
        XCTAssertEqual(
            devRound.devTurnEndReason, .reported,
            "standing failure must NOT rewrite endReason (analogous to scopeViolation)"
        )
        XCTAssertEqual(devRound.standingFailed, [StandingInvariants.contractDrift])
        XCTAssertTrue(devRound.proofCommands.isEmpty, "zero declared proofs")
        XCTAssertFalse(devRound.proofResults.isEmpty, "standing still produces proofResults")
        let standing = try XCTUnwrap(devRound.proofResults.first { $0.standing })
        XCTAssertEqual(standing.invariant, StandingInvariants.contractDrift)
        XCTAssertFalse(standing.passed)

        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let logEntry = try XCTUnwrap(json.roundLog.first { $0.devRunId != nil })
        XCTAssertEqual(logEntry.standingFailed, [StandingInvariants.contractDrift])
        XCTAssertEqual(logEntry.endReason, "reported")
        XCTAssertTrue(logEntry.proofResults.contains { $0.standing && $0.invariant == "contractDrift" })
    }

    func testCleanDeliveredTurnNoStandingFailed() async throws {
        let tmp = makeTempRoot("po-f4-relay-clean")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let support = tmp.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let repo = try makeGitRepo(in: tmp)
        // The dev-turn execution-lane run clears this per-root scratch, so a fake
        // alln planted up front is gone by the time the standing check runs. In
        // production the standing check's real `swift build` re-creates alln on the
        // scratch; the mock proof runner below simulates that by planting on the
        // build step (plantAllnOnBuild), so the post-build findAllnProduct resolves it.
        let scratch = ExecutionLaneFlock.ensuredScratchPath(repoRoot: repo.path)

        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let lane = ExecutionLaneRegistry()

        let report = "Clean turn. Contracts already regenerated."
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Review.\n\n```json\n{\"verdict\": \"continue\", \"handover\": \"Ship it.\"}\n```"),
            .init(stdout: "Done.\n\n```json\n{\"verdict\": \"done\", \"note\": \"Shipped.\"}\n```"),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: report),
        ]
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore, writeLock: lane
        )
        let proofRunner = StandingProofScriptRunner(
            checkExitCode: 0, checkTail: "fresh",
            plantAllnOnBuild: true, plantScratchPath: scratch)
        let coordinator = RelayCoordinator(
            runService: service,
            stateStore: stateStore,
            runStore: runStore,
            executionLane: lane,
            proofCommandRunner: proofRunner
        )

        let state = try await coordinator.run(config: .init(
            projectRoot: repo.path,
            docPath: "docs/spec.md",
            pmWorkerId: "model_pm",
            devWorkerId: "model_dev",
            maxRounds: 5
        )).get()

        let devRound = try XCTUnwrap(state.rounds.first { $0.devRunId != nil })
        XCTAssertEqual(devRound.devTurnEndReason, .reported)
        XCTAssertNil(devRound.standingFailed, "clean standing → no standingFailed field")
        let standing = try XCTUnwrap(devRound.proofResults.first { $0.standing })
        XCTAssertEqual(standing.invariant, StandingInvariants.contractDrift)
        XCTAssertTrue(standing.passed)

        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let logEntry = try XCTUnwrap(json.roundLog.first { $0.devRunId != nil })
        XCTAssertNil(logEntry.standingFailed)
        XCTAssertTrue(logEntry.proofResults.contains { $0.standing && $0.passed })
    }

    // MARK: - Wire surface + catalog

    func testStandingFailedProjectedOnRelayJSONAndErrorCatalog() throws {
        let round = RelayRound(
            roundNumber: 1,
            startedAt: Date(timeIntervalSince1970: 1),
            devTurnEndReason: .reported,
            proofResults: [
                HarnessProofResult(
                    command: "/tmp/scratch/debug/alln dev export-contracts --check",
                    exitCode: 1,
                    durationMs: 42,
                    outputTail: "drift",
                    standing: true,
                    invariant: StandingInvariants.contractDrift
                )
            ],
            standingFailed: [StandingInvariants.contractDrift]
        )
        var r = round
        r.devRunId = "run_dev"
        let state = RelayState(
            id: "relay_standing",
            projectRoot: "/r",
            docPath: "d",
            pmWorkerId: "pm",
            devWorkerId: "dev",
            status: .awaitingPM,
            rounds: [r],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        XCTAssertEqual(json.roundLog[0].standingFailed, ["contractDrift"])
        XCTAssertEqual(json.roundLog[0].endReason, "reported")
        XCTAssertTrue(json.roundLog[0].proofResults[0].standing)
        XCTAssertEqual(json.roundLog[0].proofResults[0].invariant, "contractDrift")

        XCTAssertNotNil(
            ContractRegistry.milestone1.errors.first { $0.code == "STANDING_INVARIANT_FAILED" },
            "typed error must be registered so agents recover via catalog"
        )
        XCTAssertEqual(StandingInvariants.all, [StandingInvariants.contractDrift])
    }

    func testHarnessProofResultLenientDecodePreF4() throws {
        // Pre-F4 shapes lack standing/invariant — must decode with defaults.
        let raw = """
        {"command":"true","exitCode":0,"durationMs":1,"outputTail":"","timedOut":false}
        """
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let decoded = try JSONDecoder().decode(HarnessProofResult.self, from: data)
        XCTAssertFalse(decoded.standing)
        XCTAssertNil(decoded.invariant)
        XCTAssertTrue(decoded.passed)
    }

    // MARK: - Fixtures

    private func makeTempRoot(_ label: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeGitRepo(in tmp: URL) throws -> URL {
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func git(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir.path] + args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            p.standardInput = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"],
                  ["config", "user.name", "T"], ["config", "commit.gpgsign", "false"]] {
            git(a)
        }
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        git(["add", "."]); git(["commit", "-q", "-m", "c1"])
        return dir
    }

    /// Plant a tiny executable at `scratch/debug/alln` so StandingInvariants reuses it.
    private func plantFakeAlln(scratchPath: String) throws {
        let debug = (scratchPath as NSString).appendingPathComponent("debug")
        try FileManager.default.createDirectory(atPath: debug, withIntermediateDirectories: true)
        let alln = (debug as NSString).appendingPathComponent("alln")
        try "#!/bin/sh\nexit 0\n".write(toFile: alln, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: alln
        )
    }

    private func makeService(
        pmScripts: [MockCommandRunner.Script],
        devScripts: [MockCommandRunner.Script],
        runStore: RunStore,
        writeLock: RunWriteLockRegistry = RunWriteLockRegistry()
    ) -> (RunService, SequencedCommandRunner) {
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "pm_cli", role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "pm_cli", command: "pm_cli"),
            TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: ["pm_cli": pmScripts, "dev_cli": devScripts])
        let service = RunService(
            models: [pmModel, devModel],
            registry: registry,
            runStore: runStore,
            commandRunner: runner,
            writeLock: writeLock,
            defaultSettings: { DefaultModelSettings() },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: "pm_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "dev_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                ]
            }
        )
        return (service, runner)
    }
}

// MARK: - Scripted proof runner (inspects `/bin/sh -c` body)

/// Routes on the shell command body so standing-invariant tests can script
/// `export-contracts --check` and optional `swift build --product alln` without
/// a real binary or dirty repo.
final class StandingProofScriptRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var capturedShellCommands: [String] = []
    var checkExitCode: Int32
    var checkTail: String
    var plantAllnOnBuild: Bool
    var plantScratchPath: String?

    init(
        checkExitCode: Int32,
        checkTail: String = "",
        plantAllnOnBuild: Bool = false,
        plantScratchPath: String? = nil
    ) {
        self.checkExitCode = checkExitCode
        self.checkTail = checkTail
        self.plantAllnOnBuild = plantAllnOnBuild
        self.plantScratchPath = plantScratchPath
    }

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        _ = command
        _ = stdin
        _ = env
        _ = workingDirectory
        _ = timeout
        // ProjectVerificationService always invokes `/bin/sh -c <cmd>`.
        let shell = args.count >= 2 ? args[1] : args.joined(separator: " ")
        lock.withLock { capturedShellCommands.append(shell) }

        if shell.contains("swift build") && shell.contains("alln") {
            if plantAllnOnBuild, let scratch = plantScratchPath {
                let debug = (scratch as NSString).appendingPathComponent("debug")
                try? FileManager.default.createDirectory(atPath: debug, withIntermediateDirectories: true)
                let alln = (debug as NSString).appendingPathComponent("alln")
                try? "#!/bin/sh\nexit 0\n".write(toFile: alln, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: alln)
            }
            return CommandResult(stdout: "Build complete!", exitCode: 0)
        }
        if shell.contains("export-contracts --check") {
            return CommandResult(
                stdout: checkExitCode == 0 ? checkTail : "",
                stderr: checkExitCode == 0 ? "" : checkTail,
                exitCode: checkExitCode
            )
        }
        // Other declared proofs (if any) succeed by default.
        return CommandResult(stdout: "", exitCode: 0)
    }
}
