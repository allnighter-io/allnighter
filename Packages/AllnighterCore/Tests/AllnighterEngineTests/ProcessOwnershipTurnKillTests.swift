import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PO-S02 seam tests: identity-checked group kill, turn endReason stamping,
/// relay-death reconcile reaps the recorded group. Never sends real signals to
/// arbitrary pids — uses `ProcessOwnership.terminateSignalHook`.
final class ProcessOwnershipTurnKillTests: HermeticSupportTestCase {

    override func tearDown() {
        ProcessOwnership.terminateSignalHook = nil
        ProcessOwnership.TurnOwnerDirectory.shared.set(nil)
        super.tearDown()
    }

    // MARK: - Kill function: identity mismatch → no signal

    func testTerminateOwnerIdentityMismatchNeverSignals() {
        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let livePid = ProcessInfo.processInfo.processIdentifier
        let liveTicks = ProcessOwnership.processStartTimeTicks(livePid) ?? 0
        // Same live pid, wrong start time → recycled identity → must not signal.
        let recycled = ProcessOwnership.OwnerIdentity(
            pid: livePid,
            pgid: livePid,
            startTimeTicks: liveTicks &- 1_000_000,
            kind: .devTurn
        )
        XCTAssertFalse(ProcessOwnership.isIdentityAlive(recycled))
        XCTAssertFalse(ProcessOwnership.terminateOwnerIdentityIfSafe(recycled))
        XCTAssertTrue(signals.isEmpty, "recycled pid must never be signalled")
    }

    func testTerminateOwnerIdentityInProcessNeverSignals() {
        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let inProcess = ProcessOwnership.OwnerIdentity(
            pid: 2_000_000, pgid: nil, startTimeTicks: 1, kind: .inProcess
        )
        XCTAssertFalse(ProcessOwnership.terminateOwnerIdentityIfSafe(inProcess))
        XCTAssertTrue(signals.isEmpty)
    }

    func testTerminateOwnerIdentityNeverInventsPgidFromPid() {
        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        // Killable kind but no recorded pgid → never invent pgid == pid.
        let noPgid = ProcessOwnership.OwnerIdentity(
            pid: 2_000_001, pgid: nil, startTimeTicks: 1, kind: .devTurn
        )
        XCTAssertFalse(ProcessOwnership.terminateOwnerIdentityIfSafe(noPgid))
        XCTAssertTrue(signals.isEmpty)
    }

    func testTerminateOwnerIdentityDeadDetachedSignalsRecordedPgid() {
        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_000_002, pgid: 9_001, startTimeTicks: 1, kind: .devTurn
        )
        XCTAssertTrue(ProcessOwnership.terminateOwnerIdentityIfSafe(dead))
        XCTAssertEqual(signals, [9_001], "must signal the *recorded* pgid only")
    }

    func testTerminateRecordedOwnerDelegatesToIdentityKill() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s02-owner-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_000_003, pgid: 9_002, startTimeTicks: 1, kind: .devTurn),
            in: dir
        )
        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        XCTAssertTrue(ProcessOwnership.terminateRecordedOwnerIfSafe(in: dir))
        XCTAssertEqual(signals, [9_002])
    }

    // MARK: - Turn-owner file + orphan reconcile reaps group

    func testTurnOwnerFileRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s02-turn-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let identity = ProcessOwnership.OwnerIdentity(
            pid: 2_000_004, pgid: 9_003, startTimeTicks: 42, kind: .devTurn
        )
        try ProcessOwnership.writeTurnOwner(identity, in: dir)
        let read = try XCTUnwrap(ProcessOwnership.readTurnOwner(in: dir))
        XCTAssertEqual(read, identity)
        ProcessOwnership.clearTurnOwner(in: dir)
        XCTAssertNil(ProcessOwnership.readTurnOwner(in: dir))
    }

    func testReconcileOrphanReapsRecordedDevTurnGroup() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s02-reconcile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RelayStateStore(rootDirectory: root)
        var state = RelayState(
            id: "relay_orphan_1",
            projectRoot: "/tmp/repo",
            docPath: "docs/spec.md",
            pmModelId: "model_pm",
            devModelId: "model_dev",
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        state.rounds = [
            RelayRound(
                roundNumber: 1,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                devTurnOwner: ProcessOwnerRecord(
                    pid: 2_000_005, pgid: 9_004, startTimeTicks: 7, kind: "devTurn"
                )
            )
        ]
        try store.save(state)
        // owner.pid names a dead process → isOwnerDead == true
        let relayDir = try store.directory(for: state.id)
        try Data("1999999".utf8).write(
            to: relayDir.appendingPathComponent("owner.pid"), options: .atomic
        )
        // Also write the active turn-owner file (mid-turn death before stamp on round).
        try ProcessOwnership.writeTurnOwner(
            .init(pid: 2_000_005, pgid: 9_004, startTimeTicks: 7, kind: .devTurn),
            in: relayDir
        )

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let reconciled = RelayCoordinator.reconcileOrphan(
            state, stateStore: store, threadProjector: nil, now: { Date(timeIntervalSince1970: 1_700_000_100) }
        )
        XCTAssertEqual(reconciled.status, .stopped)
        XCTAssertEqual(reconciled.stoppedReason, RelayState.orphanReconciledReason)
        XCTAssertEqual(signals, [9_004], "orphan reconcile must PG-kill the recorded turn group")
        XCTAssertEqual(reconciled.rounds.last?.devTurnEndReason, .killed)
        XCTAssertNil(ProcessOwnership.readTurnOwner(in: relayDir), "turn owner file cleared after kill")
    }

    // MARK: - endReason stamped on turn-end paths (coordinator)

    func testDevTurnReportedStampsEndReason() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s02-reported-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let repo = try makeGitRepo(in: tmp)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Review.\n\n```json\n{\"verdict\": \"continue\", \"handover\": \"Do the thing.\"}\n```"),
            .init(stdout: "Done.\n\n```json\n{\"verdict\": \"done\", \"note\": \"Shipped.\"}\n```"),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Implemented and committed."),
        ]
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore
        )
        let coordinator = RelayCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore
        )
        let state = try await coordinator.run(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )).get()
        XCTAssertEqual(state.status, .done)
        let devRound = try XCTUnwrap(state.rounds.first { $0.devRunId != nil })
        XCTAssertEqual(devRound.devTurnEndReason, .reported,
                       "successful dev turn must stamp endReason=reported (never inferred)")

        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        let logEntry = try XCTUnwrap(json.roundLog.first { $0.devRunId != nil })
        XCTAssertEqual(logEntry.endReason, "reported")
    }

    func testDevTurnStalledBudgetStampsEndReason() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s02-stalled-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let repo = try makeGitRepo(in: tmp)
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        // PM continues once; dev always fails (non-done exit) → stalled retries then escalate.
        let maxStalled = RelayTurnClassifier.RetryCeiling.maxStalledAttempts
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Review.\n\n```json\n{\"verdict\": \"continue\", \"handover\": \"Do the thing.\"}\n```"),
        ]
        // Enough failing scripts for initial + maxStalled retries.
        let devScripts = (0..<(maxStalled + 2)).map { _ in
            MockCommandRunner.Script(stdout: "still working", exitCode: 1)
        }
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore
        )
        let coordinator = RelayCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore
        )
        let state = try await coordinator.run(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )).get()
        XCTAssertEqual(state.status, .escalated)
        let round = try XCTUnwrap(state.rounds.last)
        XCTAssertEqual(round.devTurnEndReason, .stalled,
                       "budget-exhausted stall must stamp endReason=stalled")
        let json = RelayJSON.project(state, contractVersion: ContractRegistry.contractVersion)
        XCTAssertEqual(json.roundLog.last?.endReason, "stalled")
    }

    // MARK: - Kind choice: devTurn is PG-killable

    func testDevTurnKindIsProcessGroupKillable() {
        XCTAssertTrue(ProcessOwnership.OwnerKind.devTurn.isProcessGroupKillable)
        XCTAssertTrue(ProcessOwnership.OwnerKind.detachedRunner.isProcessGroupKillable)
        XCTAssertFalse(ProcessOwnership.OwnerKind.inProcess.isProcessGroupKillable)
    }

    // MARK: - Live spawn: process-group leader + identity-checked kill

    func testSpawnProcessGroupLeaderRecordsIdentityAndKillHookSeesPgid() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s02-spawn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        ProcessOwnership.TurnOwnerDirectory.shared.set(dir)
        defer { ProcessOwnership.TurnOwnerDirectory.shared.set(nil) }

        // Short-lived sleep in its own group (posix_spawn SETPGROUP).
        let spawned = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            workingDirectory: nil,
            stdinMode: .devNull,
            stdoutMode: .devNull,
            stderrMode: .devNull,
            kind: .devTurn
        )
        XCTAssertEqual(spawned.identity.kind, .devTurn)
        XCTAssertEqual(spawned.identity.pgid, spawned.pid, "SETPGROUP leader has pgid == pid")
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(spawned.identity))
        let fileOwner = try XCTUnwrap(ProcessOwnership.readTurnOwner(in: dir))
        XCTAssertEqual(fileOwner.pid, spawned.pid)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        // Real process: use identity kill via the ONE function (hook intercepts).
        XCTAssertTrue(ProcessOwnership.terminateOwnerIdentityIfSafe(spawned.identity))
        XCTAssertEqual(signals, [spawned.pid])

        // Actually reap the sleep so we don't leave a 30s orphan (hook replaced kill).
        ProcessOwnership.terminateSignalHook = nil
        ProcessOwnership.terminateProcessGroup(pgid: spawned.pid)
        // waitpid reaps the zombie; processAlive may still see the zombie briefly.
        var status: Int32 = 0
        _ = waitpid(spawned.pid, &status, 0)
        XCTAssertFalse(ProcessOwnership.processAlive(spawned.pid))
        XCTAssertTrue(ProcessOwnership.isProcessGroupEmpty(spawned.pid))
    }

    // MARK: - Fixtures

    private func makeGitRepo(in tmp: URL) throws -> URL {
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

    private func makeService(
        pmScripts: [MockCommandRunner.Script],
        devScripts: [MockCommandRunner.Script],
        runStore: RunStore
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
            writeLock: RunWriteLockRegistry(),
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
