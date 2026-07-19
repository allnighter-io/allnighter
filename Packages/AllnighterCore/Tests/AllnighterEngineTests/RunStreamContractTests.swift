import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S03b — the durable-`seq` stream spine (`docs/phases/rlr/S03_Execution_Plan.md`
/// § S03b, semantics `docs/phases/Run_Lifecycle_Reliability.md` RLR-L7):
///  - `--stream` events carry the durable per-Mac `seq` from `RemoteRunEventJournal`
///    (stamped at append), which survives coordinator restart + reattach;
///  - exactly one terminal per attachment; the first line carries the runId;
///  - a replay attach continues in the one durable seq space;
///  - `alln run --json` is final-only — one object, nothing before it.
final class RunStreamContractTests: XCTestCase {

    // MARK: - In-process harness (mirrors RunAcceptanceBoundaryTests)

    private struct Harness {
        let repo: URL
        let runsDir: URL
        let runStore: RunStore
        let journal: RemoteRunEventJournal
        let service: RunService
    }

    private func makeHarness() throws -> Harness {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-stream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] })
        return Harness(
            repo: repo, runsDir: runsDir, runStore: runStore,
            journal: RemoteRunEventJournal(rootDirectory: runsDir), service: service)
    }

    private let terminal: Set<String> = ["teamRunCompleted", "teamRunFailed", "error"]

    private func parse(_ line: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    // MARK: - Durable seq across a live stream + reattach (RLR-L7)

    /// Route a real `RunService` live run through the durable journal + attachment
    /// exactly as `RunCLI --stream` does: every visible line carries a durable,
    /// strictly-ascending seq, the first line carries the runId, exactly one
    /// terminal is emitted, and a fresh reattach replays the SAME durable seqs
    /// (no reset to 1) marked `replayed`.
    func testStreamSeqIsMonotonicAndDurableAcrossReattach() async throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let attachment = NDJSONStreamProjector.NDJSONAttachment()
        let runId = UUID().uuidString

        // Drain the live stream on a child task while the run executes.
        let consumer = Task { () -> [String] in
            var lines: [String] = []
            for await event in stream {
                let stamped = (try? h.journal.append(event)) ?? event
                if let line = attachment.liveLine(for: stamped) { lines.append(line) }
            }
            if let closing = attachment.closingLine() { lines.append(closing) }
            return lines
        }

        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path),
            origin: .cli, runId: runId, events: continuation)
        guard case .success = result else { return XCTFail("run failed: \(result)") }
        let liveLines = await consumer.value

        let liveObjs = try liveLines.map(parse)
        XCTAssertFalse(liveObjs.isEmpty, "a live stream must emit at least a start + terminal")

        // First line carries the runId (RLR-L7).
        XCTAssertEqual(liveObjs.first?["event"] as? String, "teamRunStarted")
        XCTAssertEqual(liveObjs.first?["teamRunId"] as? String, runId, "the first stream line carries the runId")

        // Durable seq: strictly ascending + unique, never a reset 1..N counter alone
        // (the durable per-Mac seq is the truth).
        let liveSeqs = liveObjs.compactMap { $0["seq"] as? Int }
        XCTAssertEqual(liveSeqs.count, liveObjs.count, "every line carries a seq")
        XCTAssertEqual(liveSeqs, liveSeqs.sorted(), "seq is monotonic")
        XCTAssertEqual(liveSeqs.count, Set(liveSeqs).count, "seq is unique — no duplicates")

        // Exactly one terminal, and it is last (RLR-L7).
        let terminals = liveObjs.filter { terminal.contains($0["event"] as? String ?? "") }
        XCTAssertEqual(terminals.count, 1, "exactly one terminal per attachment")
        XCTAssertTrue(terminal.contains(liveObjs.last?["event"] as? String ?? ""), "terminal is last")

        // Reattach: a fresh attachment replays durable history from seq 0. The
        // replayed visible seqs equal the live ones (durable — not reset to 1),
        // and history is marked replayed.
        let history = try h.journal.replay(after: 0).events
        let reattach = NDJSONStreamProjector.NDJSONAttachment()
        let replayObjs = try reattach.replayLines(history).map(parse)
        let replaySeqs = replayObjs.compactMap { $0["seq"] as? Int }
        XCTAssertEqual(replaySeqs, liveSeqs, "reattach replays the SAME durable seqs — no reset to 1")
        XCTAssertTrue(replayObjs.allSatisfy { $0["replayed"] as? Bool == true }, "replayed history is marked")
        XCTAssertEqual(replayObjs.first?["teamRunId"] as? String, runId, "the first replayed line carries the runId")
    }

    /// The durable `seq` lives in `remote_event_seq.txt` under the journal root, so
    /// a brand-new journal instance (a restarted coordinator) reads the persisted
    /// value and continues from `lastSeq` — no reset, no collision (RLR-L7).
    func testSeqIsDurableAcrossCoordinatorRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-seq-restart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rid = "run_restart"
        func ev(to: RunStatus) -> RunEvent {
            RunEvent(id: UUID().uuidString, seq: 0, ts: Date(), kind: RunEventKind.runStatusChanged,
                     payload: ["runId": .string(rid), "to": .string(to.rawValue)])
        }

        let j1 = RemoteRunEventJournal(rootDirectory: root)
        XCTAssertEqual(try j1.append(ev(to: .running)).seq, 1)
        XCTAssertEqual(try j1.append(ev(to: .running)).seq, 2)

        // "Coordinator restart": a brand-new instance over the same root.
        let j2 = RemoteRunEventJournal(rootDirectory: root)
        XCTAssertEqual(try j2.lastSeq(), 2, "durable seq survives a restart (persisted on disk)")
        XCTAssertEqual(try j2.append(ev(to: .complete)).seq, 3, "seq continues after restart — no reset to 1")

        // Replay after the restart returns the full contiguous run.
        let replay = try j2.replay(after: 0)
        XCTAssertEqual(replay.events.map(\.seq), [1, 2, 3])
        XCTAssertEqual(replay.lastSeq, 3)
    }

    // MARK: - `alln run --json` is final-only (RLR-L7, §1.4)

    /// A real `alln run --json` subprocess writes exactly one JSON object to stdout
    /// and nothing before it — no NDJSON dribble (the `--json`/`--stream` branches
    /// are mutually exclusive). Uses the deterministic fake worker so the run
    /// settles fast with no real model/quota.
    func testJsonIsFinalOnly() throws {
        let alln = try locateAllnBinary()
        let fx = try Fixture.make()
        defer { fx.tearDown() }
        try fx.installCompletingWorker()
        try fx.seedReadyClaude()
        try fx.seedSingleWorkerTeam(id: "custom_stream_json_team")

        // Register the project so `alln run --project` resolves it.
        let add = try runAlln(alln, ["project", "add", fx.repo.path, "--json"], cwd: fx.repo, env: fx.env, timeout: 30)
        XCTAssertEqual(add.status, 0, "project add failed: \(add.stderr)")

        let run = try runAlln(
            alln,
            ["run", "brief json", "--project", fx.repo.path, "--team", "custom_stream_json_team",
             "--effort", "low", "--json"],
            cwd: fx.repo, env: fx.env, timeout: 90)

        let stdout = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(stdout.isEmpty, "`--json` must print one object; stderr: \(run.stderr.prefix(400))")
        // Final-only: the WHOLE stdout parses as exactly one JSON object. Any NDJSON
        // line emitted before the terminal object would break this single-object parse.
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
            "`alln run --json` must emit exactly one JSON object, nothing before it. Got: \(stdout.prefix(400))")
        XCTAssertFalse(obj.isEmpty)
    }

    // MARK: - Subprocess + fixture helpers

    private func locateAllnBinary() throws -> URL {
        let buildDir = Bundle(for: RunStreamContractTests.self).bundleURL.deletingLastPathComponent()
        let binary = buildDir.appendingPathComponent("alln")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path),
                      "alln binary missing at \(binary.path) — build the alln product first")
        return binary
    }

    private struct ProcessResult { var status: Int32; var stdout: String; var stderr: String }

    private func runAlln(
        _ alln: URL, _ arguments: [String], cwd: URL, env: [String: String], timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = alln
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.environment = env
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out; process.standardError = err
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            XCTFail("alln \(arguments.prefix(2).joined(separator: " ")) did not exit within \(timeout)s")
        }
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    /// One hermetic support root + repo + a fake `claude` that EXITS FAST (so a run
    /// settles without a real model), mirroring the RLR two-process fixture shape.
    private struct Fixture {
        let temp: URL
        let support: URL
        let repo: URL
        let fakebin: URL
        let home: URL
        var env: [String: String]

        static func make() throws -> Fixture {
            let fm = FileManager.default
            let temp = fm.temporaryDirectory.appendingPathComponent("stream-json-\(UUID().uuidString)", isDirectory: true)
            let support = temp.appendingPathComponent("support", isDirectory: true)
            let repo = temp.appendingPathComponent("repo", isDirectory: true)
            let fakebin = temp.appendingPathComponent("fakebin", isDirectory: true)
            let home = temp.appendingPathComponent("home", isDirectory: true)
            for dir in [support, repo, fakebin, home] {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let env: [String: String] = [
                "ALLNIGHTER_SUPPORT_DIR": support.path,
                "ALLNIGHTER_SKIP_LOGIN_PATH_BOOTSTRAP": "1",
                "PATH": "\(fakebin.path):/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": home.path,
                "TMPDIR": home.path,
                // Deterministic COMPLETING worker: emit a line, then exit 0 (no hang).
                "RLR_FAKE_EMIT": "Done.",
                "RLR_FAKE_EXIT_CODE": "0",
            ]
            return Fixture(temp: temp, support: support, repo: repo, fakebin: fakebin, home: home, env: env)
        }

        func installCompletingWorker() throws {
            let fm = FileManager.default
            var scriptURL = URL(fileURLWithPath: #filePath)
            for _ in 0..<5 { scriptURL.deleteLastPathComponent() } // …EngineTests → Tests → AllnighterCore → Packages → repo root
            scriptURL.appendPathComponent("scripts/rlr_fake_worker.sh")
            XCTAssertTrue(fm.isExecutableFile(atPath: scriptURL.path), "fake worker missing at \(scriptURL.path)")
            let dest = fakebin.appendingPathComponent("claude")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: scriptURL, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        }

        func seedReadyClaude() throws {
            try SetupStore(fileURL: support.appendingPathComponent("Config/cli_setup.json"))
                .save(.init(
                    records: [ToolProbeRecord(
                        driverId: "claude_code", status: .ready(version: "stream-fake-0.0.1"),
                        invocation: nil, version: "stream-fake-0.0.1", lastProbeAt: Date())],
                    setupCompletedAt: Date()))
        }

        func seedSingleWorkerTeam(id: String) throws {
            let fm = FileManager.default
            let team = TeamPreset(
                id: id, displayName: "Stream JSON Team", lane: .code, outputKind: .plan,
                defaultEffort: .low, isDefaultForLane: false,
                workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"), builtIn: false)
            let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
            try fm.createDirectory(at: teamsDir, withIntermediateDirectories: true)
            try CoreJSON.encode(CatalogEnvelope(kind: .team, definition: team))
                .write(to: teamsDir.appendingPathComponent("\(team.id).json"))
        }

        func tearDown() { try? FileManager.default.removeItem(at: temp) }
    }
}
