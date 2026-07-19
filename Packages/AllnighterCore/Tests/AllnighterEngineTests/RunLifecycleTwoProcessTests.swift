import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S00 **red** two-process reproduction (`docs/phases/Run_Lifecycle_Reliability.md`
/// § Trusted workflow slice / Works Test / slice RLR-S00). Extends the
/// `ConcurrentInvocationTwoProcessTests` fixture shape: two real `alln`
/// subprocesses over one support root with the deterministic fake worker CLI
/// (`scripts/rlr_fake_worker.sh` installed as a `claude` stub on a curated PATH
/// — no real model, no quota).
///
/// These tests assert the **behaviour the spec demands** (RLR-L1/L3/L5/L6) and
/// are therefore EXPECTED RED against today's code. They are gated behind
/// `RLR_RED=1` so the default suite stays green (they XCTSkip otherwise).
///
/// Run them red:
///
///     RLR_RED=1 swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
///
/// Signature (a) — `testStatusPolledFromSecondProcessDisagreesWithDurableJournalDuringHang`:
///   a second process polling `team status` reports the run as not-yet-started
///   (`accepted`) — and the durable journal carries `fanning_out` for a single
///   worker — while a live worker child exists. RLR-L1 (one durable truth) and
///   RLR-L3 (no `fanning_out` for one-worker execution) both demand otherwise.
///
/// Signature (b) — `testKillStampsTerminalKilledWhileLiveWorkerSurvives`:
///   `alln kill <id>` signals only the recorded coordinator owner, the worker
///   (its own process-group leader, pgid never recorded) survives, yet the
///   journal is stamped terminal `endReason: killed` — the "terminal lie".
///   RLR-L5 requires a non-verified stop to leave the lifecycle non-terminal
///   (KillOutcome `partial`/`refused`), never a `killed` stamp over live work.
final class RunLifecycleTwoProcessTests: XCTestCase {

    private static let teamId = "custom_rlr_lifecycle_gate"

    // MARK: - Signature (a): status ≠ journal during the hang

    func testStatusPolledFromSecondProcessDisagreesWithDurableJournalDuringHang() throws {
        try Self.requireRedGate()
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
        try Self.requireRedGate()
        let alln = try Self.locateAllnBinary()

        var fixture = try Fixture.make(name: "rlr-kill2proc")
        defer { fixture.tearDown(alln: alln, markerSleeps: ["4933", "4934"]) }

        // Worker ignores SIGTERM and spawns a setsid grandchild that escapes any
        // process-group kill — belt-and-suspenders around the core fact that the
        // worker is its own group leader whose pgid is never recorded, so the
        // recorded-owner kill can never reach it.
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

        // The worker (and its grandchild) survive the kill — the recorded-owner
        // signal never reached them. This is the "kill did not reap a live
        // worker" leg; if it is empty the signature is NOT present (report it).
        let survivors = Self.waitForAlive(matching: "sleep 4933", timeout: 5)
            + Self.waitForAlive(matching: "sleep 4934", timeout: 5)
        XCTAssertFalse(
            survivors.isEmpty,
            "could NOT reproduce (b): kill reaped the worker tree (no survivors) — the terminal stamp would be honest"
        )

        // --- Spec-correct assertion (RED today) -------------------------------
        // RLR-L5: an operator kill that does not reach verified stop must leave
        // the lifecycle non-terminal (KillOutcome partial/refused) — it must NOT
        // stamp endReason=killed while a live worker survives.
        let journal = try XCTUnwrap(store.loadRaw(runId: runId), "journal must round-trip")
        XCTAssertNotEqual(
            journal.endReason, .killed,
            """
            RLR-L5 terminal lie: journal stamped endReason=killed \
            (status=\(journal.status.rawValue)) while worker/grandchild survivors \(survivors) are alive. \
            A non-verified stop must stay non-terminal (KillOutcome partial/refused), not `killed`.
            """
        )
        XCTAssertFalse(
            journal.status.isTerminal,
            "RLR-L5: lifecycle must not be terminal (status=\(journal.status.rawValue)) while live survivors \(survivors) remain"
        )
    }

    // MARK: - Red gate

    /// Default CI stays green: skip unless the operator opts into the red
    /// reproduction with `RLR_RED=1`.
    private static func requireRedGate() throws {
        guard ProcessInfo.processInfo.environment["RLR_RED"] == "1" else {
            throw XCTSkip("set RLR_RED=1 to run the RLR-S00 red field-signature reproductions")
        }
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
            // SIGKILL (not TERM): the fake worker may `trap '' TERM`, and its
            // setsid grandchild escapes the run's process group — only an
            // un-ignorable signal by unique argv guarantees no harness orphans.
            for marker in markerSleeps {
                let pkill = Process()
                pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                pkill.arguments = ["-9", "-f", "sleep \(marker)"]
                try? pkill.run()
                pkill.waitUntilExit()
            }
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
