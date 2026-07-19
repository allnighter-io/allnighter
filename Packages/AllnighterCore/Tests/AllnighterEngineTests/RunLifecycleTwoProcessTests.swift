import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S00 **two-process** reproductions (`docs/phases/Run_Lifecycle_Reliability.md`
/// § Trusted workflow slice / Works Test). Extends the
/// `ConcurrentInvocationTwoProcessTests` fixture shape: two real `alln`
/// subprocesses over one support root with the deterministic fake worker CLI
/// (`scripts/rlr_fake_worker.sh` installed as a `claude` stub on a curated PATH
/// — no real model, no quota).
///
/// S00 landed these as red (gated `RLR_RED=1`). S01–S04 flipped the signatures
/// green; **S06 ungates them** so the default Core wall runs the Works Test
/// proofs. Optional focus:
///
///     swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
///
/// Signature (a) — `testStatusPolledFromSecondProcessDisagreesWithDurableJournalDuringHang`:
///   a second process polling `team status` must agree the worker has started
///   (never project `accepted` / one-worker `fanning_out` while a live child exists).
///
/// Signature (b) — `testKillStampsTerminalKilledWhileLiveWorkerSurvives`:
///   `alln kill <id>` over a TERM-ignoring recorded worker must leave the
///   lifecycle non-terminal with `KillOutcome.partial` — never a `killed` lie.
final class RunLifecycleTwoProcessTests: XCTestCase {

    private static let teamId = "custom_rlr_lifecycle_gate"

    // MARK: - Signature (a): status ≠ journal during the hang

    func testStatusPolledFromSecondProcessDisagreesWithDurableJournalDuringHang() throws {
        let alln = try Self.locateAllnBinary()

        var fixture = try Fixture.make(name: "rlr-status2proc")
        defer { fixture.tearDown(alln: alln, markerSleeps: ["4931"]) }

        // Silent, blocking worker: no stdout, no stream events → the coordinator
        // never advances the worker past `queued`, reproducing the frozen
        // heartbeat / "stuck at accepted" hang.
        try fixture.installFakeWorker(extraEnv: [
            "RLR_FAKE_SLEEP_SECONDS": "4931",
            "RLR_FAKE_HANG": "1",
        ])
        try fixture.seedReadyClaude()
        try fixture.seedSingleWorkerTeam(id: Self.teamId)

        let env = fixture.env
        let store = RunStore(rootDirectory: fixture.support.appendingPathComponent("Runs", isDirectory: true))

        // Process 1: start the run (returns after the accepted handshake; the
        // detached runner keeps the blocking worker alive).
        let start = try Self.startTeam(alln, prompt: "hang brief a", cwd: fixture.repo, env: env, teamId: Self.teamId)
        let runId = try XCTUnwrap(start["runId"] as? String, "team start must return a runId")

        // The worker process actually spawned and is a live OS child.
        _ = fixture.waitForWorkerLog(needles: ["hang brief a"], test: self)
        let liveWorkerPids = Self.waitForAlive(matching: "sleep 4931", timeout: 15)
        XCTAssertFalse(liveWorkerPids.isEmpty, "precondition: the fake worker child must be alive before polling")

        // Durable journal truth (in-process read of run.json).
        let journal = try XCTUnwrap(store.loadRaw(runId: runId), "journal must round-trip")
        XCTAssertFalse(journal.status.isTerminal, "precondition: run is mid-flight, not terminal")

        // Process 2: a *second* process polls the same run id.
        let statusProc = try Self.runAlln(alln, ["team", "status", runId, "--json"], cwd: fixture.repo, env: env, timeout: 30)
        XCTAssertEqual(statusProc.status, 0, "team status failed: \(statusProc.stderr)")
        let statusJSON = try Self.jsonObject(statusProc.stdout)
        let polledStatus = statusJSON["status"] as? String

        // --- Spec-correct assertions (RED today) ------------------------------

        // A1 (RLR-L1): the truth a second process polls must AGREE that the
        // worker has started — a live worker child + a mid-fanout journal cannot
        // project to "accepted" (= not yet running). Field signature: `accepted`.
        XCTAssertNotEqual(
            polledStatus, "accepted",
            """
            RLR-L1 disagreement: a second process polled status=\(polledStatus ?? "nil") \
            (durable journal status=\(journal.status.rawValue)) while a live worker child \
            (pids \(liveWorkerPids)) exists. `accepted` denies the worker that is running.
            """
        )

        // A2 (RLR-L3): `fanning_out` must not be the durable phase for a
        // one-worker run — the projection cannot even name it, which is the
        // structural source of the cross-process disagreement.
        XCTAssertNotEqual(
            journal.status, .fanningOut,
            "RLR-L3: single-worker run must not carry fanning_out (journal=\(journal.status.rawValue))"
        )
    }

    // MARK: - Signature (b): terminal `killed` lie over a live worker

    func testKillStampsTerminalKilledWhileLiveWorkerSurvives() throws {
        let alln = try Self.locateAllnBinary()

        var fixture = try Fixture.make(name: "rlr-kill2proc")
        defer { fixture.tearDown(alln: alln, markerSleeps: ["4933", "4934"]) }

        // RLR-S04b §2.4: the worker traps+ignores SIGTERM and re-loops its marked
        // sleep, so THE RECORDED worker (its own process-group leader, whose pgid is
        // now recorded by S04a) stays identity-alive through `alln kill`'s
        // TERM→grace window. The settlement verify observes a live recorded member →
        // KillOutcome.partial → non-terminal. The setsid grandchild is kept as
        // belt-and-suspenders but is a no-op on macOS (setsid absent); the recorded
        // worker is the load-bearing, deterministic survivor.
        try fixture.installFakeWorker(extraEnv: [
            "RLR_FAKE_SLEEP_SECONDS": "4933",
            "RLR_FAKE_GRANDCHILD_SLEEP": "4934",
            "RLR_FAKE_IGNORE_SIGTERM": "1",
            "RLR_FAKE_SPAWN_GRANDCHILD": "1",
            "RLR_FAKE_HANG": "1",
        ])
        try fixture.seedReadyClaude()
        try fixture.seedSingleWorkerTeam(id: Self.teamId)

        let env = fixture.env
        let store = RunStore(rootDirectory: fixture.support.appendingPathComponent("Runs", isDirectory: true))

        let start = try Self.startTeam(alln, prompt: "kill brief b", cwd: fixture.repo, env: env, teamId: Self.teamId)
        let runId = try XCTUnwrap(start["runId"] as? String, "team start must return a runId")

        _ = fixture.waitForWorkerLog(needles: ["kill brief b"], test: self)
        XCTAssertFalse(Self.waitForAlive(matching: "sleep 4933", timeout: 15).isEmpty,
                       "precondition: the fake worker child must be alive before kill")

        // Process 2: kill the recorded ownership tree.
        let kill = try Self.runAlln(alln, ["kill", runId, "--json"], cwd: fixture.repo, env: env, timeout: 30)
        XCTAssertEqual(kill.status, 0, "kill failed: \(kill.stderr)")

        // The recorded worker survives the kill — a TERM to its group is trapped
        // and it re-loops its marked sleep. This is the "kill did not reach a
        // verified stop" leg; if it is empty the signature is NOT present.
        let survivors = Self.waitForAlive(matching: "sleep 4933", timeout: 5)
            + Self.waitForAlive(matching: "sleep 4934", timeout: 5)
        XCTAssertFalse(
            survivors.isEmpty,
            "could NOT reproduce (b): kill reaped the worker tree (no survivors) — the terminal stamp would be honest"
        )

        // §2.4: the survivor is a RECORDED, identity-alive member — the settlement
        // verified a live worker and therefore returned `partial`.
        let runDir = try store.runDirectory(forRunId: runId)
        let recorded = ProcessOwnership.readWorkerOwners(inRunDirectory: runDir)
        XCTAssertTrue(
            recorded.contains { ProcessOwnership.isIdentityAlive($0.identity) },
            "the survivor must be a RECORDED, identity-alive worker (owners: \(recorded.map(\.workerId)))"
        )

        // --- Spec-correct assertions (GREEN after S04b) -----------------------
        // RLR-L5: an operator kill that does not reach a verified stop leaves the
        // lifecycle non-terminal with a typed KillOutcome — it must NOT stamp
        // endReason=killed while a live recorded worker survives.
        let journal = try XCTUnwrap(store.loadRaw(runId: runId), "journal must round-trip")
        XCTAssertNotEqual(
            journal.endReason, .killed,
            """
            RLR-L5 terminal lie: journal stamped endReason=killed \
            (status=\(journal.status.rawValue)) while worker survivors \(survivors) are alive. \
            A non-verified stop must stay non-terminal (KillOutcome partial/refused), not `killed`.
            """
        )
        XCTAssertFalse(
            journal.status.isTerminal,
            "RLR-L5: lifecycle must not be terminal (status=\(journal.status.rawValue)) while live survivors \(survivors) remain"
        )
        XCTAssertEqual(
            journal.killOutcome, .partial,
            "RLR-L5: a non-verified stop over a live recorded worker records KillOutcome.partial (got \(String(describing: journal.killOutcome)))"
        )
    }

    // MARK: - RLR-S02c / Works Test 14: kill of a BLOCKED run withdraws its FIFO
    //         ticket from a SECOND process; the blocked run self-abandons.

    private static let mutatingTeamId = "custom_rlr_mutating_gate"

    /// Works Test 14 acceptance shape. A durable per-root holder pins the write lock;
    /// run B (a real, mutating foreground `alln run`) blocks behind it at the write-lock
    /// wait — BEFORE any worker spawn — with a durable FIFO blocker. A THIRD waiter C
    /// sits behind B. A SECOND process then `alln kill`s B and we assert:
    ///  - B's terminal revision is `cancelled` + `killed` with `blocker == nil` (atomic);
    ///  - B's FIFO waiter file is withdrawn FROM THE KILLER'S PROCESS (C advances 2 → 1) —
    ///    the killer cannot reach B's parked continuation, only its on-disk waiter;
    ///  - B never spawned a worker (no `brief B` invocation) — no spawn while blocked;
    ///  - B's OWN `alln run` process self-abandons the parked wait and EXITS well within
    ///    the poll bound. A blocked foreground `alln run` records NO owner, so the killer
    ///    could not signal it — the ONLY way it unblocks is the `shouldAbandon` self-poll;
    ///  - the holder is completely unaffected.
    ///
    /// The holder is a durable `holder.json` written with THIS (alive) process's identity —
    /// a live foreign holder to B's separate process, deterministic and independent of the
    /// mutating execution path (B never reaches execution; it blocks at the lock).
    func testKillOfBlockedRunWithdrawsFifoTicketFromSecondProcess() throws {
        let alln = try Self.locateAllnBinary()

        var fixture = try Fixture.make(name: "rlr-blockedkill")
        // Point THIS process's lane paths at the fixture support root so in-test
        // holder/waiter-file I/O reads the same `Lanes/` the `alln` children write.
        setenv("ALLNIGHTER_SUPPORT_DIR", fixture.support.path, 1)
        defer {
            unsetenv("ALLNIGHTER_SUPPORT_DIR")
            fixture.tearDown(alln: alln, markerSleeps: [])
        }

        try fixture.installFakeWorker(extraEnv: ["RLR_FAKE_HANG": "1"])
        try fixture.seedReadyClaude()
        try fixture.seedMutatingSingleWorkerTeam(id: Self.mutatingTeamId)

        let env = fixture.env
        let store = RunStore(rootDirectory: fixture.support.appendingPathComponent("Runs", isDirectory: true))

        // Register the repo as a project and read its canonical normalized root.
        let add = try Self.runAlln(alln, ["project", "add", fixture.repo.path, "--json"],
                                   cwd: fixture.repo, env: env, timeout: 30)
        XCTAssertEqual(add.status, 0, "project add failed: \(add.stderr)")
        let addJSON = try Self.jsonObject(add.stdout)
        let normalizedRoot = try XCTUnwrap(
            (addJSON["project"] as? [String: Any])?["normalizedRootPath"] as? String,
            "project add must return the canonical normalizedRootPath")
        // The exact lane key a mutating run on this project keys onto.
        let laneKey = ExecutionLane.key(repoRoot: normalizedRoot)

        // Pin the lane with a durable holder owned by THIS live process (foreign to B).
        let holderIdentity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        try ExecutionLaneFlock.writeHolders(laneKey: laneKey, holders: [
            .init(identity: holderIdentity, kind: "run", id: "held-holder", acquiredAt: Date())
        ])
        XCTAssertTrue(ExecutionLaneFlock.readHolders(laneKey: laneKey).contains { $0.id == "held-holder" })

        // --- Process 1: run B (mutating) blocks behind the held lane. ---
        let runB = Self.spawnAllnDetached(
            alln, ["run", "brief B", "--project", fixture.repo.path,
                   "--team", Self.mutatingTeamId, "--effort", "low", "--json"],
            cwd: fixture.repo, env: env)
        defer { if runB.isRunning { runB.terminate() } }

        let blockedB = try XCTUnwrap(
            Self.waitForRun(store: store, where: {
                $0.prompt == "brief B" && $0.status == .queued && $0.blocker?.holderId != nil
            }, timeout: 30),
            "run B must be durably blocked with FIFO ticket facts naming the holder")
        let runBId = blockedB.id
        XCTAssertEqual(blockedB.phase, .waitingForWriteLock)
        XCTAssertEqual(blockedB.blocker?.resource, .repoWriteLock)
        XCTAssertEqual(blockedB.blocker?.holderId, "held-holder", "B's ticket names the pinned holder")
        XCTAssertEqual(blockedB.blocker?.holderKind, "run", "public holderKind is `run` in P0")
        XCTAssertEqual(ExecutionLaneFlock.waiterCount(laneKey: laneKey), 1, "only B's waiter is queued behind the holder")

        // No worker spawned for B while it is blocked.
        let logBeforeKill = (try? String(contentsOf: fixture.workerLog, encoding: .utf8)) ?? ""
        XCTAssertFalse(logBeforeKill.contains("brief B"), "no worker may spawn for a blocked run")

        // A THIRD waiter C sits behind B (position 2).
        let cURL = try XCTUnwrap(ExecutionLaneFlock.registerWaiter(
            laneKey: laneKey,
            claim: .make(id: "waiter-C-\(UUID().uuidString)", kind: ExecutionLaneSite.mutatingRun.rawValue,
                         identity: holderIdentity),
            enqueuedAt: Date()))
        defer { ExecutionLaneFlock.unregisterWaiter(cURL) }
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: laneKey, waiterURL: cURL), 2,
                       "C queues behind the blocked run B")

        // --- Process 2: kill B from a SECOND process. ---
        let kill = try Self.runAlln(alln, ["kill", runBId, "--json"], cwd: fixture.repo, env: env, timeout: 30)
        XCTAssertEqual(kill.status, 0, "kill of blocked run B failed: \(kill.stderr)")

        // (a) Terminal revision: cancelled + killed + blocker nil in one snapshot.
        let terminalB = try XCTUnwrap(store.loadRaw(runId: runBId), "B's journal must round-trip")
        XCTAssertEqual(terminalB.status, .cancelled)
        XCTAssertEqual(terminalB.endReason, .killed)
        XCTAssertNil(terminalB.blocker, "the terminal revision clears the blocker (RLR-L3)")

        // (b)+(c) B's waiter file is withdrawn cross-process; C advances to the head.
        XCTAssertEqual(ExecutionLaneFlock.waiterCount(laneKey: laneKey), 1, "B's waiter file is withdrawn; only C remains")
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: laneKey, waiterURL: cURL), 1,
                       "the next waiter's position advances the instant B's ticket is withdrawn")

        // (d) B's own `alln run` process self-abandons and EXITS (not parked to timeout).
        let exited = Self.waitForProcessExit(runB, timeout: 15)
        XCTAssertTrue(exited, "run B must self-abandon its parked wait and exit, not park to the 1800s timeout")

        // Never spawned a worker for B, even after the kill.
        let logAfterKill = (try? String(contentsOf: fixture.workerLog, encoding: .utf8)) ?? ""
        XCTAssertFalse(logAfterKill.contains("brief B"), "a killed blocked run must never spawn a worker")

        // The holder is completely unaffected by killing a blocked waiter.
        XCTAssertTrue(ExecutionLaneFlock.readHolders(laneKey: laneKey).contains { $0.id == "held-holder" },
                      "killing a blocked waiter must not touch the holder")
    }

    // MARK: - RLR-S04a: async worker runtimeOwnership recorded as a group leader

    /// The async `alln team start` worker is now spawned via
    /// `ProcessGroupCommandRunner` (RLR-S04a), so its OS identity is recorded as
    /// `runtimeOwnership` keyed by worker id — `pgid == its own pid`, atomic at
    /// spawn — and the recorded group is genuinely reachable. This proves the old
    /// `SubprocessCommandRunner` setpgid detachment (site C, unrecorded own group)
    /// is gone. No kill is exercised (that flips green in S04b).
    func testAsyncWorkerRuntimeOwnershipRecordedAsGroupLeader() throws {
        let alln = try Self.locateAllnBinary()

        var fixture = try Fixture.make(name: "rlr-s04a-async")
        defer { fixture.tearDown(alln: alln, markerSleeps: ["4935"]) }

        try fixture.installFakeWorker(extraEnv: [
            "RLR_FAKE_SLEEP_SECONDS": "4935",
            "RLR_FAKE_HANG": "1",
        ])
        try fixture.seedReadyClaude()
        try fixture.seedSingleWorkerTeam(id: Self.teamId)

        let env = fixture.env
        let store = RunStore(rootDirectory: fixture.support.appendingPathComponent("Runs", isDirectory: true))

        let start = try Self.startTeam(alln, prompt: "owner brief c", cwd: fixture.repo, env: env, teamId: Self.teamId)
        let runId = try XCTUnwrap(start["runId"] as? String, "team start must return a runId")

        _ = fixture.waitForWorkerLog(needles: ["owner brief c"], test: self)
        XCTAssertFalse(Self.waitForAlive(matching: "sleep 4935", timeout: 15).isEmpty,
                       "precondition: the fake worker child must be alive")

        let runDir = try store.runDirectory(forRunId: runId)

        // A recorded worker runtimeOwnership receipt appears (keyed by the team's
        // worker id "r1"), pgid == its own pid.
        var owners: [(workerId: String, identity: ProcessOwnership.OwnerIdentity)] = []
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            owners = ProcessOwnership.readWorkerOwners(inRunDirectory: runDir)
            if let first = owners.first, first.identity.pgid != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let worker = try XCTUnwrap(owners.first, "worker runtimeOwnership must be recorded on the async path")
        let pgid = try XCTUnwrap(worker.identity.pgid, "recorded worker must carry a pgid")
        XCTAssertEqual(pgid, worker.identity.pid, "recorded worker pgid == its own pid (group leader, not detached)")
        XCTAssertEqual(worker.identity.kind, .devTurn)
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(worker.identity),
                      "the live recorded worker is identity-alive")

        // The recorded group is reachable (non-empty) — the site-C detachment is gone.
        XCTAssertFalse(ProcessOwnership.isProcessGroupEmpty(pgid),
                       "recorded worker group must be reachable (not detached into an unrecorded group)")

        // The coordinator is a SEPARATE owner at the run-dir root (detached runner).
        let coordinator = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir),
                                        "coordinator owner.json must exist separately")
        XCTAssertEqual(coordinator.kind, .detachedRunner)
        XCTAssertNotEqual(coordinator.pid, worker.identity.pid,
                          "coordinator and worker are distinct owners")
    }

    // MARK: - Fixture

    /// One hermetic two-process fixture: temp support root, a `repo`, a curated
    /// `fakebin` PATH carrying the deterministic worker as `claude`, and a
    /// private HOME/TMPDIR. Mirrors `ConcurrentInvocationTwoProcessTests`.
    private struct Fixture {
        let temp: URL
        let support: URL
        let repo: URL
        let fakebin: URL
        let home: URL
        let workerLog: URL
        var env: [String: String]

        static func make(name: String) throws -> Fixture {
            let fm = FileManager.default
            let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
            let support = temp.appendingPathComponent("support", isDirectory: true)
            let repo = temp.appendingPathComponent("repo", isDirectory: true)
            let fakebin = temp.appendingPathComponent("fakebin", isDirectory: true)
            let home = temp.appendingPathComponent("home", isDirectory: true)
            let workerLog = temp.appendingPathComponent("fake_worker_args.log")
            for dir in [support, repo, fakebin, home] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let env: [String: String] = [
                "ALLNIGHTER_SUPPORT_DIR": support.path,
                "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
                "PATH": "\(fakebin.path):/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": home.path,
                "TMPDIR": home.path,
                "RLR_FAKE_LOG": workerLog.path,
            ]
            return Fixture(temp: temp, support: support, repo: repo, fakebin: fakebin,
                           home: home, workerLog: workerLog, env: env)
        }

        /// Install `scripts/rlr_fake_worker.sh` as the `claude` stub and fold the
        /// behaviour-selecting env vars into this fixture's spawn environment.
        mutating func installFakeWorker(extraEnv: [String: String]) throws {
            let fm = FileManager.default
            let scriptURL = RunLifecycleTwoProcessTests.fakeWorkerScriptURL()
            XCTAssertTrue(fm.isExecutableFile(atPath: scriptURL.path),
                          "fake worker harness missing at \(scriptURL.path)")
            let dest = fakebin.appendingPathComponent("claude")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: scriptURL, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            for (k, v) in extraEnv { env[k] = v }
        }

        func seedReadyClaude() throws {
            try SetupStore(fileURL: support.appendingPathComponent("Config/cli_setup.json"))
                .save(.init(
                    records: [ToolProbeRecord(
                        driverId: "claude_code", status: .ready(version: "rlr-fake-0.0.1"),
                        invocation: nil, version: "rlr-fake-0.0.1", lastProbeAt: Date()
                    )],
                    setupCompletedAt: Date()
                ))
        }

        func seedSingleWorkerTeam(id: String) throws {
            let fm = FileManager.default
            let team = TeamPreset(
                id: id, displayName: "RLR Lifecycle Gate", lane: .code, outputKind: .plan,
                defaultEffort: .low, isDefaultForLane: false,
                workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"),
                builtIn: false
            )
            let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
            try fm.createDirectory(at: teamsDir, withIntermediateDirectories: true)
            try CoreJSON.encode(CatalogEnvelope(kind: .team, definition: team))
                .write(to: teamsDir.appendingPathComponent("\(team.id).json"))
        }

        /// A **mutating** single-worker team: `alln run` takes the per-root write
        /// lock (RLR-L4), so a second run behind a held lane blocks with a durable
        /// FIFO blocker — the substrate Works Test 14 needs.
        func seedMutatingSingleWorkerTeam(id: String) throws {
            let fm = FileManager.default
            let team = TeamPreset(
                id: id, displayName: "RLR Mutating Gate", lane: .code, outputKind: .plan,
                mutating: true, defaultEffort: .low, isDefaultForLane: false,
                workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"),
                builtIn: false
            )
            let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
            try fm.createDirectory(at: teamsDir, withIntermediateDirectories: true)
            try CoreJSON.encode(CatalogEnvelope(kind: .team, definition: team))
                .write(to: teamsDir.appendingPathComponent("\(team.id).json"))
        }

        func waitForWorkerLog(
            needles: [String], timeout: TimeInterval = 20, test: XCTestCase,
            file: StaticString = #filePath, line: UInt = #line
        ) -> String {
            let deadline = Date().addingTimeInterval(timeout)
            var body = ""
            while Date() < deadline {
                body = (try? String(contentsOf: workerLog, encoding: .utf8)) ?? ""
                if needles.allSatisfy({ body.contains($0) }) { return body }
                Thread.sleep(forTimeInterval: 0.1)
            }
            XCTFail("fake worker did not spawn within \(timeout)s — log so far: \(body)", file: file, line: line)
            return body
        }

        /// Best-effort teardown: kill runner trees for this support root, then
        /// reap every marked fake descendant by its unique sleep argv.
        func tearDown(alln: URL, markerSleeps: [String]) {
            _ = try? RunLifecycleTwoProcessTests.runAlln(
                alln, ["kill", "--all", "--all-projects", "--json"], cwd: repo, env: env, timeout: 30
            )
            func pkill(_ pattern: String) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                p.arguments = ["-9", "-f", pattern]
                try? p.run()
                p.waitUntilExit()
            }
            // RLR-S04b §2.4: the fake worker now traps TERM and re-loops its marked
            // sleep, so it survives `alln kill` (that is the point — KillOutcome
            // partial). SIGKILL it by the unique fixture temp path (its argv[0] is
            // `<temp>/fakebin/claude`) FIRST so it stops respawning, then reap any
            // orphaned marker sleeps. SIGKILL is un-ignorable; the temp path is
            // unique to this fixture so no unrelated process is touched.
            pkill(temp.path)
            for marker in markerSleeps { pkill("sleep \(marker)") }
            try? FileManager.default.removeItem(at: temp)
        }
    }

    // MARK: - Harness location

    /// `scripts/rlr_fake_worker.sh`, resolved from this test file's on-disk path
    /// (`…/Packages/AllnighterCore/Tests/AllnighterEngineTests/<file>`).
    private static func fakeWorkerScriptURL() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() } // file → …EngineTests → Tests → AllnighterCore → Packages → repo root
        return root.appendingPathComponent("scripts/rlr_fake_worker.sh")
    }

    /// The `alln` product built next to this test bundle (the test target
    /// depends on `AllnighterCLI`, so `swift test` keeps it fresh).
    private static func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: RunLifecycleTwoProcessTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "alln binary missing at \(binary.path) — build the alln product first"
        )
        return binary
    }

    // MARK: - Liveness probe

    /// Poll `pgrep -f <pattern>` until at least one match appears or the deadline
    /// passes; returns the matched pids (empty ⇒ nothing alive).
    private static func waitForAlive(matching pattern: String, timeout: TimeInterval) -> [Int32] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let pids = pgrep(matching: pattern)
            if !pids.isEmpty { return pids }
            if Date() >= deadline { return [] }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Poll the durable journal for the first run matching `predicate` (or nil at
    /// the deadline). Scans run.json files via a fresh RunStore read each tick.
    private static func waitForRun(
        store: RunStore, where predicate: (TeamRun) -> Bool, timeout: TimeInterval
    ) -> TeamRun? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = store.list().first(where: predicate) { return match }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    /// True once `process` is no longer running (bounded by `timeout`).
    private static func waitForProcessExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !process.isRunning
    }

    /// Launch `alln` and return the still-running handle (no wait) — used to keep a
    /// blocked/holding foreground `alln run` alive while the test drives around it.
    @discardableResult
    private static func spawnAllnDetached(
        _ alln: URL, _ arguments: [String], cwd: URL, env: [String: String]
    ) -> Process {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = env
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        return process
    }

    private static func pgrep(matching pattern: String) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", pattern]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - Process runner (mirrors ConcurrentInvocationTwoProcessTests)

    private struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    private static func startTeam(
        _ alln: URL, prompt: String, cwd: URL, env: [String: String], teamId: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> [String: Any] {
        let result = try runAlln(
            alln,
            ["team", "start", prompt, "--json", "--lane", "code", "--team", teamId, "--effort", "low"],
            cwd: cwd, env: env, timeout: 90
        )
        XCTAssertEqual(result.status, 0, "team start failed: \(result.stderr)", file: file, line: line)
        return try jsonObject(result.stdout)
    }

    private static func jsonObject(_ stdout: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
            "expected one JSON object on stdout, got: \(stdout.prefix(400))"
        )
    }

    private static func runAlln(
        _ alln: URL, _ arguments: [String], cwd: URL, env: [String: String], timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = exited.wait(timeout: .now() + 5)
        }
        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertFalse(timedOut, "alln \(arguments.prefix(2).joined(separator: " ")) did not exit within \(timeout)s\nstdout: \(out.prefix(400))\nstderr: \(err.prefix(400))")
        return ProcessResult(status: process.terminationStatus, stdout: out, stderr: err)
    }
}
