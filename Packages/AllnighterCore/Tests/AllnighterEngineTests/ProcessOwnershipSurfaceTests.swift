import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

/// PO-S05: `alln ps` / `alln kill` — observable ownership from durable state.
/// Real signals only to processes this suite spawns; otherwise uses the
/// `ProcessOwnership.terminateSignalHook` spy.
final class ProcessOwnershipSurfaceTests: XCTestCase {

    override func tearDown() {
        ProcessOwnership.terminateSignalHook = nil
        ProcessOwnership.TurnOwnerDirectory.shared.set(nil)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func tempTree() throws -> (
        support: URL,
        runs: RunStore,
        relays: RelayStateStore,
        lanes: URL,
        surface: ProcessOwnershipSurface
    ) {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("po-s05-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let runsRoot = support.appendingPathComponent("Runs", isDirectory: true)
        let relaysRoot = support.appendingPathComponent("Relays", isDirectory: true)
        let lanesRoot = support.appendingPathComponent("Lanes", isDirectory: true)
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relaysRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lanesRoot, withIntermediateDirectories: true)
        let runs = RunStore(rootDirectory: runsRoot)
        let relays = RelayStateStore(rootDirectory: relaysRoot)
        let surface = ProcessOwnershipSurface(
            runStore: runs,
            relayStore: relays,
            lanesRoot: lanesRoot
        )
        return (support, runs, relays, lanesRoot, surface)
    }

    private func nonTerminalRun(id: String, repoRoot: String? = "/tmp/repo") -> TeamRun {
        TeamRun(
            id: id, prompt: "p", status: .fanningOut,
            workers: [Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            workerAnswers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus",
                role: "answer", result: WorkerRunResult(status: .queued)
            )],
            createdAt: Date(),
            repoRoot: repoRoot
        )
    }

    // MARK: - ps enumerates run + relay + lane holder

    func testPsEnumeratesRunRelayAndProofHolderWithIdentityAliveFlags() throws {
        let (support, runs, relays, lanes, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        // Live in-process run owner.
        let liveRun = nonTerminalRun(id: "run-alive")
        try runs.save(liveRun, models: [])
        let runDir = try runs.runDirectory(forRunId: "run-alive")
        let liveIdentity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .detachedRunner))
        try ProcessOwnership.writeOwnerIdentity(liveIdentity, in: runDir)
        try ProcessOwnership.recordProgress(in: runDir, phase: "fanning_out")

        // Dead-owner run (would reconcile).
        let deadRun = nonTerminalRun(id: "run-dead")
        try runs.save(deadRun, models: [])
        let deadDir = try runs.runDirectory(forRunId: "run-dead")
        let deadIdentity = ProcessOwnership.OwnerIdentity(
            pid: 2_100_001, pgid: 9_101, startTimeTicks: 1, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(deadIdentity, in: deadDir)

        // Running relay with live turn owner.
        var relay = RelayState(
            id: "relay_live_1",
            projectRoot: "/tmp/relay-repo",
            docPath: "docs/spec.md",
            pmWorkerId: "model_pm",
            devWorkerId: "model_dev",
            status: .running,
            createdAt: Date()
        )
        relay.rounds = [
            RelayRound(roundNumber: 1, startedAt: Date())
        ]
        _ = try relays.save(relay)
        let relayDir = try relays.directory(for: relay.id)
        // owner.pid for isOwnerDead
        try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8)
            .write(to: relayDir.appendingPathComponent("owner.pid"), options: .atomic)
        let turnLive = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .devTurn))
        try ProcessOwnership.writeTurnOwner(turnLive, in: relayDir)

        // Proof holder (harnessProof) with dead identity.
        let proofIdentity = ProcessOwnership.OwnerIdentity(
            pid: 2_100_002, pgid: 9_102, startTimeTicks: 1, kind: .harnessProof
        )
        let laneKey = ExecutionLane.key(repoRoot: "/tmp/proof-repo")
        let safe = ExecutionLaneFlock.sanitizedDirectoryName(for: laneKey)
        let laneDir = lanes.appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: laneDir, withIntermediateDirectories: true)
        let holder = ExecutionLaneFlock.HolderMetadata(
            identity: proofIdentity,
            kind: ExecutionLaneSite.harnessProof.rawValue,
            id: "proof-claim-1",
            acquiredAt: Date().addingTimeInterval(-30)
        )
        try CoreJSON.encode(holder).write(
            to: laneDir.appendingPathComponent(ExecutionLaneFlock.holderFileName),
            options: .atomic
        )

        let envelope = surface.list()
        XCTAssertGreaterThanOrEqual(envelope.processCount, 4)
        XCTAssertEqual(envelope.schemaVersion, 1)

        let byId = Dictionary(uniqueKeysWithValues: envelope.processes.map { ($0.id, $0) })

        let alive = try XCTUnwrap(byId["run-alive"])
        XCTAssertEqual(alive.kind, "run")
        XCTAssertTrue(alive.identityAlive)
        XCTAssertFalse(alive.wouldReconcile)
        XCTAssertEqual(alive.projectRoot, "/tmp/repo")
        XCTAssertNotNil(alive.lastProgressAt)
        XCTAssertNotNil(alive.heartbeatAgeSeconds)
        XCTAssertEqual(alive.identity?.kind, "detachedRunner")

        let dead = try XCTUnwrap(byId["run-dead"])
        XCTAssertEqual(dead.kind, "run")
        XCTAssertFalse(dead.identityAlive)
        XCTAssertTrue(dead.wouldReconcile, "ps reports what reconcile WOULD reap")

        let relayRow = try XCTUnwrap(byId["relay_live_1"])
        XCTAssertEqual(relayRow.kind, "relay")
        XCTAssertTrue(relayRow.identityAlive)
        XCTAssertFalse(relayRow.wouldReconcile)
        XCTAssertEqual(relayRow.projectRoot, "/tmp/relay-repo")

        let proof = try XCTUnwrap(byId["proof-claim-1"])
        XCTAssertEqual(proof.kind, "proof")
        XCTAssertFalse(proof.identityAlive)
        XCTAssertTrue(proof.wouldReconcile)
        XCTAssertEqual(proof.lane?.state, "held")
        XCTAssertEqual(proof.lane?.holderKind, "harnessProof")
    }

    func testPsHumanTableIsNonEmptyForInventory() throws {
        let (support, runs, _, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }
        try runs.save(nonTerminalRun(id: "run-table"), models: [])
        let table = ProcessOwnershipSurface.humanTable(surface.list())
        XCTAssertTrue(table.contains("run-table"))
        XCTAssertTrue(table.contains("KIND"))
    }

    // MARK: - kill seam (spy hook)

    func testKillRunStampsEndReasonAndSignalsRecordedPgid() throws {
        let (support, runs, _, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        try runs.save(nonTerminalRun(id: "kill-me"), models: [])
        let dir = try runs.runDirectory(forRunId: "kill-me")
        let identity = ProcessOwnership.OwnerIdentity(
            pid: 2_100_010, pgid: 9_110, startTimeTicks: 1, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(identity, in: dir)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let result = try surface.kill(id: "kill-me").get()
        XCTAssertEqual(result.id, "kill-me")
        XCTAssertEqual(result.kind, "run")
        XCTAssertEqual(result.endReason, "killed")
        XCTAssertTrue(result.signalled)
        XCTAssertEqual(signals, [9_110])

        let after = try XCTUnwrap(runs.loadRaw(runId: "kill-me"))
        XCTAssertTrue(after.status.isTerminal)
        XCTAssertEqual(after.endReason, .killed)

        // ps after kill shows terminal endReason.
        let row = try XCTUnwrap(surface.list().processes.first { $0.id == "kill-me" })
        XCTAssertEqual(row.endReason, "killed")
        XCTAssertFalse(row.identityAlive)
        XCTAssertFalse(row.wouldReconcile, "terminal work is not would-reconcile")
    }

    func testKillRefusesIdentityMismatchAndNeverSignals() throws {
        let (support, runs, _, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        try runs.save(nonTerminalRun(id: "recycled"), models: [])
        let dir = try runs.runDirectory(forRunId: "recycled")
        let livePid = ProcessInfo.processInfo.processIdentifier
        let liveTicks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(livePid))
        let recycled = ProcessOwnership.OwnerIdentity(
            pid: livePid,
            pgid: livePid,
            startTimeTicks: liveTicks &- 1_000_000,
            kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(recycled, in: dir)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let result = surface.kill(id: "recycled")
        guard case .failure(.identityMismatch(let id)) = result else {
            return XCTFail("expected identityMismatch, got \(result)")
        }
        XCTAssertEqual(id, "recycled")
        XCTAssertTrue(signals.isEmpty, "recycled pid must never be signalled")

        let still = try XCTUnwrap(runs.loadRaw(runId: "recycled"))
        XCTAssertFalse(still.status.isTerminal, "mismatch must not stamp terminal")
    }

    func testKillNotFoundAndAlreadyTerminal() throws {
        let (support, runs, _, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        XCTAssertEqual(surface.kill(id: "nope"), .failure(.notFound(id: "nope")))

        var done = nonTerminalRun(id: "done-run")
        done.status = .complete
        done.endReason = .completed
        try runs.save(done, models: [])
        let again = surface.kill(id: "done-run")
        guard case .failure(.alreadyTerminal(let id, let end)) = again else {
            return XCTFail("expected alreadyTerminal, got \(again)")
        }
        XCTAssertEqual(id, "done-run")
        XCTAssertEqual(end, "completed")
    }

    func testKillAllSkipsIdentityMismatchedAndKillsAlive() throws {
        let (support, runs, _, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        // Truly identity-alive killable tree: a sleep we spawned (never the test process).
        let spawned = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/bin/sleep",
            arguments: ["60"],
            workingDirectory: nil,
            kind: .detachedRunner
        )
        defer { _ = ProcessOwnership.terminateOwnerIdentityIfSafe(spawned.identity) }

        try runs.save(nonTerminalRun(id: "alive-all"), models: [])
        let aliveDir = try runs.runDirectory(forRunId: "alive-all")
        try ProcessOwnership.writeOwnerIdentity(spawned.identity, in: aliveDir)
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(spawned.identity))

        // Identity-mismatched (this process's live pid, wrong start).
        try runs.save(nonTerminalRun(id: "mismatch-all"), models: [])
        let misDir = try runs.runDirectory(forRunId: "mismatch-all")
        let livePid = ProcessInfo.processInfo.processIdentifier
        let liveTicks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(livePid))
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: livePid, pgid: 9_999, startTimeTicks: liveTicks &- 99, kind: .detachedRunner),
            in: misDir
        )

        // Dead identity (not identity-alive) — --all skips.
        try runs.save(nonTerminalRun(id: "dead-all"), models: [])
        let deadDir = try runs.runDirectory(forRunId: "dead-all")
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_100_099, pgid: 9_098, startTimeTicks: 1, kind: .detachedRunner),
            in: deadDir
        )

        // Real signals only to the sleep we spawned; mismatch path must refuse first.
        ProcessOwnership.terminateSignalHook = nil
        let result = surface.killAll()
        let killedIds = Set(result.killed.map(\.id))

        XCTAssertTrue(killedIds.contains("alive-all"), "identity-alive tree must be killed")
        XCTAssertFalse(killedIds.contains("mismatch-all"), "identity-mismatched must not be killed")
        XCTAssertFalse(killedIds.contains("dead-all"), "identity-dead is reconcile's job, not --all")

        // Reap the child we spawned so zombies don't keep the group "non-empty".
        reapChild(spawned.pid)
        XCTAssertTrue(ProcessOwnership.isProcessGroupEmpty(spawned.identity.pgid ?? spawned.pid))

        let after = try XCTUnwrap(runs.loadRaw(runId: "alive-all"))
        XCTAssertEqual(after.endReason, .killed)

        // Mismatch still non-terminal (refused).
        let mismatch = try XCTUnwrap(runs.loadRaw(runId: "mismatch-all"))
        XCTAssertFalse(mismatch.status.isTerminal)
    }

    func testKillRelayStampsDevTurnEndReasonKilled() throws {
        let (support, _, relays, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        var state = RelayState(
            id: "relay_kill_1",
            projectRoot: "/tmp/r",
            docPath: "d.md",
            pmWorkerId: "pm",
            devWorkerId: "dev",
            status: .running,
            createdAt: Date()
        )
        state.rounds = [RelayRound(roundNumber: 1, startedAt: Date())]
        _ = try relays.save(state)
        let dir = try relays.directory(for: state.id)
        try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8)
            .write(to: dir.appendingPathComponent("owner.pid"), options: .atomic)
        let turn = ProcessOwnership.OwnerIdentity(
            pid: 2_100_050, pgid: 9_150, startTimeTicks: 1, kind: .devTurn
        )
        try ProcessOwnership.writeTurnOwner(turn, in: dir)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }

        let row = try surface.kill(id: "relay_kill_1").get()
        XCTAssertEqual(row.kind, "relay")
        XCTAssertEqual(row.endReason, "killed")
        XCTAssertEqual(signals, [9_150])

        let after = try XCTUnwrap(relays.load(id: "relay_kill_1"))
        XCTAssertEqual(after.status, .stopped)
        XCTAssertEqual(after.rounds.last?.devTurnEndReason, .killed)

        let ps = try XCTUnwrap(surface.list().processes.first { $0.id == "relay_kill_1" })
        XCTAssertEqual(ps.endReason, "killed")
    }

    // MARK: - Real signal only to spawned child

    func testKillRealSpawnedSleepProcessEmptiesGroup() throws {
        let (support, runs, _, _, surface) = try tempTree()
        defer { try? FileManager.default.removeItem(at: support) }

        // Spawn a real sleep as process-group leader.
        let spawned = try ProcessOwnership.spawnProcessGroupLeader(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            workingDirectory: nil,
            kind: .detachedRunner
        )
        defer {
            // Safety net if kill path fails.
            _ = ProcessOwnership.terminateOwnerIdentityIfSafe(spawned.identity)
        }

        try runs.save(nonTerminalRun(id: "real-sleep"), models: [])
        let dir = try runs.runDirectory(forRunId: "real-sleep")
        try ProcessOwnership.writeOwnerIdentity(spawned.identity, in: dir)

        // No spy — real signals to the process we spawned.
        ProcessOwnership.terminateSignalHook = nil
        let row = try surface.kill(id: "real-sleep").get()
        XCTAssertTrue(row.signalled)
        XCTAssertEqual(row.endReason, "killed")

        reapChild(spawned.pid)
        XCTAssertTrue(
            ProcessOwnership.isProcessGroupEmpty(spawned.identity.pgid ?? spawned.pid),
            "spawned sleep group must be empty after kill"
        )
        let after = try XCTUnwrap(runs.loadRaw(runId: "real-sleep"))
        XCTAssertEqual(after.endReason, .killed)
    }

    /// Reap a child we spawned (mirrors PO-S02 spawn works test).
    private func reapChild(_ pid: Int32) {
        var status: Int32 = 0
        // Best-effort: SIGKILL may already have landed; waitpid reaps the zombie.
        for _ in 0..<50 {
            let rc = waitpid(pid, &status, WNOHANG)
            if rc == pid || (rc < 0 && errno == ECHILD) { break }
            usleep(20_000)
        }
        _ = waitpid(pid, &status, 0)
    }
}

private extension Result where Failure: Error {
    func get() throws -> Success {
        switch self {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}
