import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// The REAL P0 acceptance gate (`docs/phases/Concurrent_Invocation_Isolation.md`
/// § Acceptance proof): two real `alln` CLI subprocesses in two distinct repo
/// roots sharing ONE support root, with deterministic blocking fake workers (a
/// `claude` shell stub on a curated PATH — no real models, no quota).
///
/// Asserts, at the OS level (not in-process like `ConcurrentInvocationIsolationTests`):
/// 1. **Mutation isolation** — a bare `team reconcile` and a `kill --all`
///    launched from project A never reap, kill, stamp, or re-scope project B's
///    live run.
/// 2. **Context isolation** — each run's durable journal, its staged packet's
///    F4 provenance (absolute root + content hash + run id), AND the argv the
///    spawned worker actually receives carry only that project's own brief.
final class ConcurrentInvocationTwoProcessTests: XCTestCase {

    private static let teamId = "custom_code_isolation_gate"

    // MARK: - The gate

    func testTwoRealProcessesMutationAndContextIsolation() throws {
        let alln = try Self.locateAllnBinary()
        let fm = FileManager.default

        // Temp layout. Path SPELLINGS differ across APIs (getcwd returns the
        // kernel-resolved path; NSString canonicalization maps /private/var
        // back to /var), so every root comparison below goes through
        // `ExecutionLane.normalize` — the same canonicalizer the F1/F4 gates use.
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("isolation2proc-\(UUID().uuidString)", isDirectory: true)
        let support = temp.appendingPathComponent("support", isDirectory: true)
        let repoA = temp.appendingPathComponent("repoA", isDirectory: true)
        let repoB = temp.appendingPathComponent("repoB", isDirectory: true)
        let fakebin = temp.appendingPathComponent("fakebin", isDirectory: true)
        let home = temp.appendingPathComponent("home", isDirectory: true)
        let workerLog = temp.appendingPathComponent("fake_worker_args.log")
        for dir in [support, repoA, repoB, fakebin, home] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Cleanup is scoped to THIS temp support root: every spawned process
        // carries ALLNIGHTER_SUPPORT_DIR, so even `--all-projects` can only
        // reach runs of this fixture.
        defer {
            _ = try? Self.runAlln(
                alln, ["kill", "--all", "--all-projects", "--json"],
                cwd: repoA, env: Self.spawnEnv(support: support, fakebin: fakebin, home: home),
                timeout: 30
            )
            // The runner kill above does not reach the fake workers (they are
            // their own group leaders); reap them by the unique marker argv.
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-f", "^sleep 613$"]
            try? pkill.run()
            pkill.waitUntilExit()
            try? fm.removeItem(at: temp)
        }

        // Blocking fake worker: logs the cwd + argv it was invoked with, then
        // blocks. Workers spawn as their OWN process-group leaders (PO-S02),
        // so killing the runner's group does not reach them — the unique sleep
        // duration is a marker the cleanup pkills by exact argv.
        let fakeClaude = fakebin.appendingPathComponent("claude")
        try """
        #!/bin/bash
        if [ "${1:-}" = "--version" ]; then echo "claude-fake 0.0.1"; exit 0; fi
        flat=$(printf '%s' "$*" | tr '\\n' ' ')
        printf 'pwd=%s args=%s\\n' "$PWD" "$flat" >> "\(workerLog.path)"
        exec sleep 613
        """
        .write(to: fakeClaude, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaude.path)

        // Readiness without detection: claude_code reads ready from the seeded
        // setup cache; built-in model_opus (default-enabled) is the only seat.
        try SetupStore(fileURL: support.appendingPathComponent("Config/cli_setup.json"))
            .save(.init(
                records: [ToolProbeRecord(
                    driverId: "claude_code", status: .ready(version: "fake-0.0.1"),
                    invocation: nil, version: "fake-0.0.1", lastProbeAt: Date()
                )],
                setupCompletedAt: Date()
            ))

        // One deterministic single-worker answer team (mirrors the unit gate's
        // preset so resolution is exercised, not ambient built-in team shape).
        let team = TeamPreset(
            id: Self.teamId, displayName: "Isolation Gate", lane: .code, outputKind: .plan,
            defaultEffort: .low, isDefaultForLane: false,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: false
        )
        let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
        try fm.createDirectory(at: teamsDir, withIntermediateDirectories: true)
        try CoreJSON.encode(CatalogEnvelope(kind: .team, definition: team))
            .write(to: teamsDir.appendingPathComponent("\(team.id).json"))

        let env = Self.spawnEnv(support: support, fakebin: fakebin, home: home)
        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs", isDirectory: true))

        // --- Two real invocations, one per project, one shared support root ---
        let startA = try Self.startTeam(alln, prompt: "project A brief", cwd: repoA, env: env)
        let startB = try Self.startTeam(alln, prompt: "project B brief", cwd: repoB, env: env)
        let runA = try XCTUnwrap(startA["runId"] as? String, "team start A must return a runId")
        let runB = try XCTUnwrap(startB["runId"] as? String, "team start B must return a runId")
        XCTAssertNotEqual(runA, runB)

        // Context isolation, durable layer: each journal minted by its own
        // invocation carries only its own prompt + root.
        let journalA = try XCTUnwrap(store.loadRaw(runId: runA))
        let journalB = try XCTUnwrap(store.loadRaw(runId: runB))
        XCTAssertEqual(journalA.prompt, "project A brief")
        XCTAssertEqual(ExecutionLane.normalize(journalA.repoRoot), ExecutionLane.normalize(repoA.path))
        XCTAssertEqual(journalB.prompt, "project B brief")
        XCTAssertEqual(ExecutionLane.normalize(journalB.repoRoot), ExecutionLane.normalize(repoB.path))
        XCTAssertFalse(journalA.status.isTerminal, "blocking fake worker: A is live")
        XCTAssertFalse(journalB.status.isTerminal, "blocking fake worker: B is live")

        // Context isolation, F4 provenance layer: each staged packet's stamped
        // absolute root + content hash authenticate against its own request.
        for (runId, brief, root) in [(runA, "project A brief", repoA), (runB, "project B brief", repoB)] {
            let packetURL = support
                .appendingPathComponent("Runs/run_\(runId)", isDirectory: true)
                .appendingPathComponent(ProcessOwnership.runnerRequestFileName)
            let packet = try CoreJSON.decode(AsyncTeamRunnerRequest.self, from: Data(contentsOf: packetURL))
            XCTAssertEqual(packet.provenance.runId, runId)
            XCTAssertEqual(packet.request.question, brief)
            XCTAssertEqual(ExecutionLane.normalize(packet.provenance.repoRoot), ExecutionLane.normalize(root.path))
            XCTAssertTrue(
                packet.provenance.authenticates(
                    question: packet.request.question,
                    context: packet.request.context,
                    threadId: packet.request.threadId
                ),
                "staged packet hash must recompute over its own delivered bytes"
            )
        }

        // Context isolation, OS layer: the worker PROCESS each project spawned
        // received argv containing only its own brief (cwd proves which run).
        let log = self.waitForWorkerLog(at: workerLog, needles: ["project A brief", "project B brief"])
        let invocations = log.split(separator: "\n").compactMap(Self.parseWorkerLogLine)
        let rootOfA = ExecutionLane.normalize(repoA.path)
        let rootOfB = ExecutionLane.normalize(repoB.path)
        let aInvocations = invocations.filter { $0.pwd == rootOfA }
        let bInvocations = invocations.filter { $0.pwd == rootOfB }
        XCTAssertFalse(aInvocations.isEmpty, "project A's worker must have been invoked")
        XCTAssertFalse(bInvocations.isEmpty, "project B's worker must have been invoked")
        XCTAssertTrue(aInvocations.allSatisfy { $0.args.contains("project A brief") })
        XCTAssertTrue(bInvocations.allSatisfy { $0.args.contains("project B brief") })
        XCTAssertFalse(aInvocations.contains { $0.args.contains("project B brief") }, "A's worker must never see B's brief")
        XCTAssertFalse(bInvocations.contains { $0.args.contains("project A brief") }, "B's worker must never see A's brief")

        // Snapshot B before A's cleanup storm.
        let bBefore = try XCTUnwrap(store.loadRaw(runId: runB))

        // --- Mutation isolation: project A's aggregate cleanup storm ---

        // Bare `team reconcile` from A reaps nothing and leaves B's live run alone.
        let reconcile = try Self.runAlln(alln, ["team", "reconcile", "--json"], cwd: repoA, env: env, timeout: 30)
        XCTAssertEqual(reconcile.status, 0, "reconcile failed: \(reconcile.stderr)")
        let reconcileJSON = try Self.jsonObject(reconcile.stdout)
        XCTAssertEqual(reconcileJSON["reapedCount"] as? Int, 0, "A has no dead runs; B's live run must not reap")
        XCTAssertFalse(try XCTUnwrap(store.loadRaw(runId: runB)).status.isTerminal,
                       "A's bare reconcile must not reap B's live run")
        XCTAssertFalse(store.wouldReconcile(runId: runB), "B's owner is genuinely alive")

        // `kill --all` from A kills A's run only — never B's.
        let kill = try Self.runAlln(alln, ["kill", "--all", "--json"], cwd: repoA, env: env, timeout: 30)
        XCTAssertEqual(kill.status, 0, "kill --all failed: \(kill.stderr)")
        let killJSON = try Self.jsonObject(kill.stdout)
        let killedIds = (killJSON["killed"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        XCTAssertEqual(Set(killedIds), [runA], "A's kill --all must kill exactly A's run")
        XCTAssertEqual(try XCTUnwrap(store.loadRaw(runId: runA)).endReason, .killed)

        // B was not reaped, not killed, not stamped, not re-scoped.
        let bAfter = try XCTUnwrap(store.loadRaw(runId: runB))
        XCTAssertEqual(bAfter.id, bBefore.id)
        XCTAssertEqual(bAfter.createdAt, bBefore.createdAt)
        XCTAssertFalse(bAfter.status.isTerminal, "A's kill --all must not reap or kill B's live run")
        XCTAssertNil(bAfter.endReason, "A's storm must not stamp an endReason on B")
        XCTAssertEqual(ExecutionLane.normalize(bAfter.repoRoot), ExecutionLane.normalize(repoB.path))
        XCTAssertEqual(bAfter.prompt, "project B brief")
        XCTAssertTrue(
            bAfter.workerAnswers.allSatisfy { $0.result.status != .cancelled },
            "A's kill --all must not cancel B's workers"
        )
    }

    /// F5b Works Test: two real `alln team start` subprocesses, same key +
    /// payload, one support root — both responses share one run id, one run
    /// directory, and one worker invocation; same-key/different-payload refuses.
    func testTwoRealProcessesSameKeyIdempotencySingleFlight() throws {
        let alln = try Self.locateAllnBinary()
        let fm = FileManager.default
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("idempotency2proc-\(UUID().uuidString)", isDirectory: true)
        let support = temp.appendingPathComponent("support", isDirectory: true)
        let repo = temp.appendingPathComponent("repo", isDirectory: true)
        let fakebin = temp.appendingPathComponent("fakebin", isDirectory: true)
        let home = temp.appendingPathComponent("home", isDirectory: true)
        let workerLog = temp.appendingPathComponent("fake_worker_args.log")
        for dir in [support, repo, fakebin, home] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer {
            _ = try? Self.runAlln(
                alln, ["kill", "--all", "--all-projects", "--json"],
                cwd: repo, env: Self.spawnEnv(support: support, fakebin: fakebin, home: home),
                timeout: 30
            )
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-f", "^sleep 617$"]
            try? pkill.run()
            pkill.waitUntilExit()
            try? fm.removeItem(at: temp)
        }

        let fakeClaude = fakebin.appendingPathComponent("claude")
        try """
        #!/bin/bash
        if [ "${1:-}" = "--version" ]; then echo "claude-fake 0.0.1"; exit 0; fi
        flat=$(printf '%s' "$*" | tr '\\n' ' ')
        printf 'pwd=%s args=%s\\n' "$PWD" "$flat" >> "\(workerLog.path)"
        exec sleep 617
        """
        .write(to: fakeClaude, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaude.path)

        try SetupStore(fileURL: support.appendingPathComponent("Config/cli_setup.json"))
            .save(.init(
                records: [ToolProbeRecord(
                    driverId: "claude_code", status: .ready(version: "fake-0.0.1"),
                    invocation: nil, version: "fake-0.0.1", lastProbeAt: Date()
                )],
                setupCompletedAt: Date()
            ))

        let team = TeamPreset(
            id: Self.teamId, displayName: "Isolation Gate", lane: .code, outputKind: .plan,
            defaultEffort: .low, isDefaultForLane: false,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: false
        )
        let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
        try fm.createDirectory(at: teamsDir, withIntermediateDirectories: true)
        try CoreJSON.encode(CatalogEnvelope(kind: .team, definition: team))
            .write(to: teamsDir.appendingPathComponent("\(team.id).json"))

        let env = Self.spawnEnv(support: support, fakebin: fakebin, home: home)
        let key = "f5b-same-key-\(UUID().uuidString)"
        let prompt = "f5b single-flight brief"

        let outcomesBox = ConcurrentOutcomeBox<(status: Int32, stdout: String, stderr: String)>()
        let group = DispatchGroup()
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let result = try Self.runAlln(
                        alln,
                        [
                            "team", "start", prompt, "--json",
                            "--lane", "code", "--team", Self.teamId, "--effort", "low",
                            "--idempotency-key", key,
                        ],
                        cwd: repo, env: env, timeout: 90
                    )
                    outcomesBox.append((result.status, result.stdout, result.stderr))
                } catch {
                    outcomesBox.append((-1, "", "\(error)"))
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 120), .success, "concurrent starts timed out")

        let outcomes = outcomesBox.snapshot()
        XCTAssertEqual(outcomes.count, 2)
        var runIds: [String] = []
        for outcome in outcomes {
            XCTAssertEqual(outcome.status, 0, "start failed: \(outcome.stderr)\n\(outcome.stdout)")
            let json = try Self.jsonObject(outcome.stdout)
            runIds.append(try XCTUnwrap(json["runId"] as? String))
        }
        XCTAssertEqual(Set(runIds).count, 1, "same key must resolve to one run id: \(runIds)")
        let runId = try XCTUnwrap(runIds.first)

        let runsRoot = support.appendingPathComponent("Runs", isDirectory: true)
        let runDirs = (try? fm.contentsOfDirectory(atPath: runsRoot.path))?
            .filter { $0.hasPrefix("run_") } ?? []
        XCTAssertEqual(runDirs, ["run_\(runId)"], "exactly one run directory for \(runId)")

        _ = waitForWorkerLog(at: workerLog, needles: [prompt])
        let log = (try? String(contentsOf: workerLog, encoding: .utf8)) ?? ""
        let invocations = log.split(separator: "\n").filter { $0.contains(prompt) }
        XCTAssertEqual(invocations.count, 1, "exactly one worker invocation: \(log)")

        // Same key, different payload → typed refusal.
        let conflict = try Self.runAlln(
            alln,
            [
                "team", "start", "different payload", "--json",
                "--lane", "code", "--team", Self.teamId, "--effort", "low",
                "--idempotency-key", key,
            ],
            cwd: repo, env: env, timeout: 90
        )
        XCTAssertNotEqual(conflict.status, 0, "different payload must refuse")
        XCTAssertTrue(
            conflict.stdout.contains("IDEMPOTENCY_CONFLICT")
                || conflict.stderr.contains("IDEMPOTENCY_CONFLICT")
                || conflict.stdout.contains("IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD")
                || conflict.stderr.contains("IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD"),
            "expected typed conflict, got stdout=\(conflict.stdout) stderr=\(conflict.stderr)"
        )
    }

    // MARK: - Fixture plumbing

    /// One fake-worker invocation record from the log, with the cwd run
    /// through the product's root normalizer so path-spelling differences
    /// (getcwd vs NSString canonicalization) cannot flake the attribution.
    private static func parseWorkerLogLine(_ line: Substring) -> (pwd: String?, args: String)? {
        guard line.hasPrefix("pwd="), let separator = line.range(of: " args=") else { return nil }
        let pwd = String(line[line.index(line.startIndex, offsetBy: 4)..<separator.lowerBound])
        return (ExecutionLane.normalize(pwd), String(line[separator.upperBound...]))
    }

    /// The `alln` product built next to this test bundle (the test target
    /// depends on the `AllnighterCLI` target, so `swift test` keeps it fresh).
    private static func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: ConcurrentInvocationTwoProcessTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "alln binary missing at \(binary.path) — build the alln product first"
        )
        return binary
    }

    /// Hermetic child environment: the temp support root, the fake-bin PATH,
    /// and no login-shell PATH bootstrap (which would drop the fake worker).
    private static func spawnEnv(support: URL, fakebin: URL, home: URL) -> [String: String] {
        [
            "ALLNIGHTER_SUPPORT_DIR": support.path,
            "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
            "PATH": "\(fakebin.path):/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home.path,
            "TMPDIR": home.path,
        ]
    }

    /// `alln team start` (blocks on the runner-ready handshake) → parsed JSON.
    private static func startTeam(
        _ alln: URL, prompt: String, cwd: URL, env: [String: String], file: StaticString = #filePath, line: UInt = #line
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

    /// Polls until the fake-worker log records every brief (workers spawn
    /// right after the accepted handshake) or the deadline passes.
    private func waitForWorkerLog(
        at url: URL, needles: [String], timeout: TimeInterval = 20,
        file: StaticString = #filePath, line: UInt = #line
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var body = ""
        while Date() < deadline {
            body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if needles.allSatisfy({ body.contains($0) }) { return body }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // Instance-method position so this XCTFail binds to the test case.
        XCTFail("fake workers did not all fire within \(timeout)s — log so far: \(body)", file: file, line: line)
        return body
    }

    // MARK: - Process runner

    private struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Runs `alln` to exit with a hard timeout. Outputs are tiny (one JSON
    /// envelope); the detached runner's own stdout/stderr go to run-dir files,
    /// never these pipes, so they close when the direct child exits.
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

private final class ConcurrentOutcomeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [T] = []
    func append(_ value: T) {
        lock.lock(); defer { lock.unlock() }
        values.append(value)
    }
    func snapshot() -> [T] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
}
