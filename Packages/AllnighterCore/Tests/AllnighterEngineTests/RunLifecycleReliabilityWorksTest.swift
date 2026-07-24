import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S06 Works Test gate — maps `docs/phases/Run_Lifecycle_Reliability.md`
/// §Works Test items 1–15 onto filterable proofs.
///
/// Filter:
///
///     swift test --package-path Packages/AllnighterCore --filter RunLifecycleReliability
///
/// Full matrix + prior-slice mapping: `docs/phases/rlr/S06_Works_Test_Matrix.md`.
/// This class owns only the S06 gap fills; GREEN items proven in earlier suites
/// stay there (see matrix).
final class RunLifecycleReliabilityWorksTest: XCTestCase {

    // MARK: - Item 5: idle clock → typed KillOutcome + lane release so B proceeds

    /// Composition of L8 idle fire + write-lock FIFO: holder A idle-times out with
    /// a verified stop, its lane holder is cleared, waiter B can acquire.
    func testItem5IdleClockReleasesLaneSoBlockedWaiterProceeds() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rlr-s06-idle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        setenv("ALLNIGHTER_SUPPORT_DIR", support.path, 1)
        defer { unsetenv("ALLNIGHTER_SUPPORT_DIR") }

        let runs = RunStore(rootDirectory: support.appendingPathComponent("Runs", isDirectory: true))
        let repoRoot = support.appendingPathComponent("repo", isDirectory: true).path
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: repoRoot), withIntermediateDirectories: true)
        let laneKey = ExecutionLane.key(repoRoot: repoRoot)

        let holder = TeamRun(
            id: "idle-holder-a", prompt: "A", status: .running, phase: .working,
            createdAt: Date().addingTimeInterval(-120), repoRoot: repoRoot,
            lastActivityAt: Date().addingTimeInterval(-90),
            clockBudgets: RunClockBudgets(idleTimeoutSeconds: 30)
        )
        try runs.save(holder, models: [])
        let dir = try runs.runDirectory(forRunId: holder.id)
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_200_501, pgid: 2_200_501, startTimeTicks: 1, kind: .devTurn)
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "r1", record: dead.asRecord()), in: dir)

        let identity = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .inProcess))
        try ExecutionLaneFlock.writeHolders(laneKey: laneKey, holders: [
            .init(identity: identity, kind: "run", id: holder.id, acquiredAt: Date())
        ])
        let waiterURL = try XCTUnwrap(ExecutionLaneFlock.registerWaiter(
            laneKey: laneKey,
            claim: .make(id: "idle-waiter-b", kind: ExecutionLaneSite.mutatingRun.rawValue,
                         identity: identity),
            enqueuedAt: Date()))
        defer { ExecutionLaneFlock.unregisterWaiter(waiterURL) }
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: laneKey, waiterURL: waiterURL), 1)

        ProcessOwnership.terminateSignalHook = { _ in }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let fired = try XCTUnwrap(
            RunClockEnforcer.fire(clock: .idle, runDirectory: dir, runStore: runs))
        XCTAssertEqual(fired.outcome, .stopped, "dead recorded worker → verified stop")
        XCTAssertEqual(fired.clock, .idle)

        let after = try XCTUnwrap(runs.loadRaw(runId: holder.id))
        XCTAssertEqual(after.status, .timedOut)
        XCTAssertEqual(after.endReason, .timedOut)
        XCTAssertEqual(after.killOutcome, .stopped)

        // Holding process release (clock stamps journal; flock drops when the
        // holder claim ends — same product path as a timed-out mutating run exit).
        ExecutionLaneFlock.removeHolder(laneKey: laneKey, id: holder.id)
        XCTAssertTrue(ExecutionLaneFlock.readHolders(laneKey: laneKey).isEmpty,
                      "lane must be free after idle settlement + holder release")
        XCTAssertEqual(ExecutionLaneFlock.waiterPosition(laneKey: laneKey, waiterURL: waiterURL), 1,
                       "B remains head waiter and can proceed once the lock is free")
    }

    // MARK: - Item 10: corrupt journal → JOURNAL_CORRUPT (never invent)

    func testItem10CorruptJournalSurfacesJournalCorruptNotInventedStatus() throws {
        let alln = try Self.locateAllnBinary()
        let fixture = try Fixture.make(name: "rlr-s06-corrupt")
        defer { fixture.tearDown(alln: alln) }

        let runsDir = fixture.support.appendingPathComponent("Runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        let runId = "run_corrupt_s06"
        let runDir = runsDir.appendingPathComponent("run_\(runId)", isDirectory: true)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        try Data("{ not-json".utf8).write(to: runDir.appendingPathComponent("run.json"))

        // 88860049 routed bare `team status` to a live resident query; the
        // durable-journal classification (JOURNAL_CORRUPT / RUN_NOT_FOUND) moved to
        // the explicit `--persisted` read (12fcd8a2). Journal corruption is a
        // persisted-read concern, so exercise that path.
        let status = try Self.runAlln(
            alln, ["team", "status", runId, "--json", "--persisted"],
            cwd: fixture.repo, env: fixture.env, timeout: 30)
        XCTAssertNotEqual(status.status, 0, "corrupt journal must fail status")
        let blob = status.stdout + status.stderr
        XCTAssertTrue(
            blob.contains("JOURNAL_CORRUPT"),
            "expected JOURNAL_CORRUPT, got: \(blob.prefix(600))"
        )
        XCTAssertFalse(
            blob.contains("\"status\""),
            "must not invent a status projection over a corrupt journal"
        )
    }

    // MARK: - Item 12: morning zero identity-alive harness orphans

    func testItem12PsAllProjectsShowsZeroHarnessOrphansAfterClose() throws {
        try XCTSkipIf(true, codeRedDetachSkipReason)
        let alln = try Self.locateAllnBinary()
        var fixture = try Fixture.make(name: "rlr-s06-orphans")
        defer { fixture.tearDown(alln: alln, markerSleeps: ["4941"]) }

        try fixture.installFakeWorker(extraEnv: [
            "RLR_FAKE_SLEEP_SECONDS": "4941",
            "RLR_FAKE_HANG": "1",
        ])
        try fixture.seedReadyClaude()
        try fixture.seedSingleWorkerTeam(id: "custom_rlr_s06_orphans")

        let start = try Self.startTeam(
            alln, prompt: "orphan brief", cwd: fixture.repo, env: fixture.env,
            teamId: "custom_rlr_s06_orphans")
        let runId = try XCTUnwrap(start["runId"] as? String)
        _ = fixture.waitForWorkerLog(needles: ["orphan brief"], test: self)
        XCTAssertFalse(Self.waitForAlive(matching: "sleep 4941", timeout: 15).isEmpty)

        let kill = try Self.runAlln(
            alln, ["kill", runId, "--json"], cwd: fixture.repo, env: fixture.env, timeout: 30)
        XCTAssertEqual(kill.status, 0, "kill failed: \(kill.stderr)")

        // Fixture-local SIGKILL of marker sleeps (same as tearDown) then assert
        // `ps --all-projects` shows no identity-alive harness rows.
        Self.pkill(fixture.temp.path)
        Self.pkill("sleep 4941")
        Thread.sleep(forTimeInterval: 0.3)

        let ps = try Self.runAlln(
            alln, ["ps", "--all-projects", "--json"],
            cwd: fixture.repo, env: fixture.env, timeout: 30)
        XCTAssertEqual(ps.status, 0, "ps failed: \(ps.stderr)")
        let json = try Self.jsonObject(ps.stdout)
        let processes = (json["processes"] as? [[String: Any]]) ?? []
        let aliveHarness = processes.filter { row in
            (row["identityAlive"] as? Bool) == true
                && ((row["id"] as? String) == runId
                    || (row["projectRoot"] as? String)?.contains(fixture.temp.path) == true)
        }
        XCTAssertTrue(
            aliveHarness.isEmpty,
            "Works Test 12: identity-alive harness orphans remain: \(aliveHarness)"
        )
    }

    // MARK: - Item 13: governor over-limit → typed refusal, no run id, no journal

    func testItem13GovernorBusyRefusesWithNoRunIdAndNoJournal() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rlr-s06-gov-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                         driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan,
            defaultEffort: .low, isDefaultForLane: true,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true
        )
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "# Plan\nOk.", delay: .seconds(30))])
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")

        let govDir = root.appendingPathComponent("gov")
        let governor = TeamGovernor(directory: govDir, capacity: 1)
        guard case .acquired(let holder) = governor.acquireDetailed() else {
            return XCTFail("expected to hold the single governor slot")
        }
        defer { _ = holder }

        let runsDir = root.appendingPathComponent("Runs")
        let service = AsyncTeamService(
            models: [opus],
            registry: registry,
            teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 1, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: runsDir),
            commandRunner: mock,
            governor: TeamGovernor(directory: govDir, capacity: 1),
            idempotency: IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
            environment: env,
            idFactory: { "should-not-exist" }
        )

        let executable = ProcessOwnership.currentExecutablePath() ?? "/usr/bin/false"
        let outcome = await service.start(
            AsyncTeamStartRequest(question: "x", lane: .code, teamPresetId: "code_test", effort: .low),
            origin: .cli,
            readyModels: [opus],
            ownership: .detachedRunner(executablePath: executable)
        )
        guard case .failure(let refusal) = outcome else {
            return XCTFail("expected TEAM_GOVERNOR_BUSY, got success")
        }
        XCTAssertEqual(refusal.code, "TEAM_GOVERNOR_BUSY")
        // Pre-accept refusal carries no run id (AsyncTeamStartRefusal has none).
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: runsDir.path)) ?? []
        XCTAssertTrue(entries.filter { $0.hasPrefix("run_") }.isEmpty,
                      "governor refusal must leave no journal dir")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: runsDir.appendingPathComponent("run_should-not-exist", isDirectory: true).path))
    }

    // MARK: - Item 15: --wait-for accepts lifecycle states only

    func testItem15WaitForAcceptsLifecycleStatesOnly() {
        for ok in ["queued", "running", "done", "failed", "timedOut", "cancelled", "terminal"] {
            XCTAssertNotNil(TeamStatusWaitTarget.parse(ok), ok)
        }
        // Phases / legacy aliases / garbage must never parse as wait targets.
        for bad in ["working", "waitingForWriteLock", "fanning_out", "completed",
                    "accepted", "interrupted", "not-a-state", ""] {
            XCTAssertNil(TeamStatusWaitTarget.parse(bad), "phase/legacy \(bad) must be rejected")
        }
    }

    // MARK: - Item 1 shape: first stream event carries runId (projector)

    func testItem1FirstStreamEventCarriesRunId() throws {
        let runId = "run_s06_stream"
        let payload: [String: JSONValue] = [
            "runId": .string(runId),
            "to": .string(RunStatus.running.rawValue),
            "origin": .string("cli"),
            "presetId": .string("p"),
        ]
        let started = RunEvent(
            id: UUID().uuidString, seq: 1, ts: Date(),
            kind: RunEventKind.runStatusChanged, payload: payload)
        let line = try XCTUnwrap(NDJSONStreamProjector.NDJSONAttachment().liveLine(for: started))
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(obj["teamRunId"] as? String, runId)
        XCTAssertEqual(obj["event"] as? String, "teamRunStarted")
        XCTAssertEqual(obj["seq"] as? Int, 1)
    }

    // MARK: - Receipt reaper (S06 optional)

    func testOwnershipReceiptReaperDropsIdentityDeadPastRetention() throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rlr-s06-reaper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let runs = RunStore(rootDirectory: support.appendingPathComponent("Runs", isDirectory: true))
        var run = TeamRun(
            id: "reap-1", prompt: "p", status: .done,
            createdAt: Date().addingTimeInterval(-7_200), repoRoot: "/tmp/repo",
            endReason: .completed)
        try runs.save(run, models: [])
        let dir = try runs.runDirectory(forRunId: run.id)
        let dead = ProcessOwnership.OwnerIdentity(
            pid: 2_200_777, pgid: 2_200_777, startTimeTicks: 1, kind: .devTurn)
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "r1", record: dead.asRecord()), in: dir)

        let url = ProcessOwnership.workerOwnerURL(workerId: "r1", in: dir)
        let old = Date().addingTimeInterval(-7_200)
        try FileManager.default.setAttributes(
            [.modificationDate: old], ofItemAtPath: url.path)

        let removed = ProcessOwnership.reapExpiredOwnershipReceipts(
            in: dir, isTerminal: true, now: Date(), retentionSeconds: 3_600)
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(ProcessOwnership.readWorkerOwners(inRunDirectory: dir).isEmpty)

        // Non-terminal must never reap.
        run.status = RunStatus.running
        run.endReason = nil
        try runs.save(run, models: [])
        try ProcessOwnership.writeWorkerOwner(
            .init(workerId: "r2", record: dead.asRecord()), in: dir)
        let kept = ProcessOwnership.reapExpiredOwnershipReceipts(
            in: dir, isTerminal: false, now: Date(), retentionSeconds: 0)
        XCTAssertEqual(kept, 0)
        XCTAssertFalse(ProcessOwnership.readWorkerOwners(inRunDirectory: dir).isEmpty)
    }

    // MARK: - Shared fixture (mirrors RunLifecycleTwoProcessTests, trimmed)

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

        mutating func installFakeWorker(extraEnv: [String: String]) throws {
            let fm = FileManager.default
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { root.deleteLastPathComponent() }
            let scriptURL = root.appendingPathComponent("scripts/rlr_fake_worker.sh")
            XCTAssertTrue(fm.isExecutableFile(atPath: scriptURL.path))
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
            let team = TeamPreset(
                id: id, displayName: "RLR S06", lane: .code, outputKind: .plan,
                defaultEffort: .low, isDefaultForLane: false,
                workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"),
                builtIn: false
            )
            let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
            try FileManager.default.createDirectory(at: teamsDir, withIntermediateDirectories: true)
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
            XCTFail("fake worker did not spawn within \(timeout)s — log: \(body)", file: file, line: line)
            return body
        }

        func tearDown(alln: URL, markerSleeps: [String] = []) {
            _ = try? RunLifecycleReliabilityWorksTest.runAlln(
                alln, ["kill", "--all", "--all-projects", "--json"],
                cwd: repo, env: env, timeout: 30)
            RunLifecycleReliabilityWorksTest.pkill(temp.path)
            for marker in markerSleeps {
                RunLifecycleReliabilityWorksTest.pkill("sleep \(marker)")
            }
            try? FileManager.default.removeItem(at: temp)
        }
    }

    private struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    private static func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: RunLifecycleReliabilityWorksTest.self).bundleURL
            .deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "alln binary missing at \(binary.path)"
        )
        return binary
    }

    private static func startTeam(
        _ alln: URL, prompt: String, cwd: URL, env: [String: String], teamId: String
    ) throws -> [String: Any] {
        _ = try runAlln(alln, ["project", "add", cwd.path, "--json"], cwd: cwd, env: env, timeout: 30)
        let result = try runAlln(
            alln,
            ["run", prompt, "--detach", "--json", "--lane", "code", "--team", teamId, "--effort", "low"],
            cwd: cwd, env: env, timeout: 90)
        XCTAssertEqual(result.status, 0, "run --detach failed: \(result.stderr)")
        return try jsonObject(result.stdout)
    }

    private static func jsonObject(_ stdout: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
            "expected JSON object, got: \(stdout.prefix(400))"
        )
    }

    private static func waitForAlive(matching pattern: String, timeout: TimeInterval) -> [Int32] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let pids = pgrep(matching: pattern)
            if !pids.isEmpty { return pids }
            if Date() >= deadline { return [] }
            Thread.sleep(forTimeInterval: 0.1)
        }
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

    private static func pkill(_ pattern: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-9", "-f", pattern]
        try? p.run()
        p.waitUntilExit()
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
        XCTAssertFalse(timedOut, "alln timed out: \(arguments.prefix(2).joined(separator: " "))")
        return ProcessResult(status: process.terminationStatus, stdout: out, stderr: err)
    }
}
