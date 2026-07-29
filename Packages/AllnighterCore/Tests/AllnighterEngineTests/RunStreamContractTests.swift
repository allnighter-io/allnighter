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
/// A scripted runner conforming to BOTH `CommandRunner` and `StreamingCommandRunner`
/// so `RunService` picks it up directly (`commandRunner as? StreamingCommandRunner`)
/// instead of wrapping a plain `CommandRunner` in `CommandRunnerAsStreaming` (which
/// would collapse to a single terminal chunk, never dribbling deltas). Replays a
/// fixed `CommandEvent` sequence — the same "fake CLI" shape `WorkerInvokeStreamingTests`
/// uses directly against `DefaultWorkerRunner`, here routed through the full
/// `RunService` so the live NDJSON stream sees real `workerAnswerDelta` events.
private final class DribblingCommandRunner: CommandRunner, StreamingCommandRunner, @unchecked Sendable {
    private let events: [CommandEvent]
    init(_ events: [CommandEvent]) { self.events = events }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        for event in events { if case .completed(let result) = event { return result } }
        return CommandResult(stdout: "", exitCode: 0)
    }

    func runStreaming(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) -> AsyncThrowingStream<CommandEvent, Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

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
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"]))
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

    // MARK: - RLR-S03c: activity flows live between started and terminal

    /// A real `RunService` cold streaming run (a driver marked `streaming.supported`,
    /// a scripted `StreamingCommandRunner` dribbling two answer-delta chunks) routed
    /// through the durable journal + `NDJSONAttachment` exactly as `RunCLI --stream`
    /// does. Proves Works Test 4's "NDJSON stays live with monotonic seq": a
    /// streaming consumer sees `workerActivity` lines land strictly between
    /// `teamRunStarted`/`workerStarted` and the terminal — not just start+terminal —
    /// and none of them carry the raw delta text (S03c non-goal).
    ///
    /// Uses an explicit custom mutating single-worker team (preferring `model_grok`
    /// directly for both rows) rather than the built-in default team — the built-in
    /// `default_chat`/"Direct" team's Lead hard-prefers `model_cursor_composer_25`
    /// with a `sameSource` fallback that only matches a `cursor_agent`-driver model,
    /// which is a PRE-EXISTING failure unrelated to S03c (reproduces today on clean
    /// HEAD via `RunIdleTimeoutTests.testRunServiceDefaultLeavesTimeoutNilForManifestBudget`
    /// with only a grok model on the bench); an explicit preset sidesteps it.
    func testWorkerActivityFlowsLiveBetweenStartedAndTerminalWithNoRawText() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-stream-activity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        var manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        manifest.streaming = .init(supported: true, mode: .jsonlStdout,
                                    args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
                                    partialOutput: true, finalAnswerSource: .parserAccumulator)
        let model = Model(id: "model_grok", displayName: "Grok", modelLabel: "grok", driverId: "grok", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true, tiers: TierMembership(frontier: ["model_grok"]))
        let probe = ToolProbeRecord(driverId: "grok", status: .ready(version: "1.0"), lastProbeAt: .distantPast)

        let team = TeamPreset(
            id: "custom_stream_activity_team", displayName: "Stream Activity Team", lane: .code,
            outputKind: .plan, mutating: true, defaultEffort: .low, isDefaultForLane: false,
            workerSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer, preferredModelId: "model_grok")],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_grok"),
            builtIn: false)

        // Two chunks so the worker "dribbles" its answer, like a real token stream.
        let ndjson = """
        {"type":"text","data":"Hello"}
        {"type":"text","data":" world"}
        {"type":"end","stopReason":"EndTurn"}

        """
        let streamingRunner = DribblingCommandRunner([
            .started(startedAt: Date()),
            .stdout(Data(ndjson.utf8)),
            .completed(CommandResult(stdout: ndjson, exitCode: 0)),
        ])

        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            teams: [team],
            runStore: RunStore(rootDirectory: runsDir),
            commandRunner: streamingRunner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] })
        let journal = RemoteRunEventJournal(rootDirectory: runsDir)

        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let attachment = NDJSONStreamProjector.NDJSONAttachment()
        let consumer = Task { () -> [String] in
            var lines: [String] = []
            for await event in stream {
                let stamped = (try? journal.append(event)) ?? event
                if let line = attachment.liveLine(for: stamped) { lines.append(line) }
            }
            if let closing = attachment.closingLine() { lines.append(closing) }
            return lines
        }

        let result = await service.run(
            RunRequest(message: "hi", repoRoot: repo.path, presetId: team.id),
            origin: .cli, events: continuation)
        guard case .success = result else { return XCTFail("run failed: \(result)") }
        let lines = await consumer.value

        let objs = try lines.map(parse)
        let events = objs.compactMap { $0["event"] as? String }
        XCTAssertEqual(events.first, "teamRunStarted")
        XCTAssertTrue(terminal.contains(events.last ?? ""), "attachment ends terminal")

        let activityIndices = events.indices.filter { events[$0] == "workerActivity" }
        XCTAssertFalse(activityIndices.isEmpty, "the dribbled deltas must surface as ≥1 workerActivity line")
        XCTAssertTrue(activityIndices.allSatisfy { $0 > 0 && $0 < events.count - 1 },
                     "activity lines land strictly between started and the terminal, never at either end")

        // Bounded metadata only — every workerActivity line carries an activityKind
        // and no raw payload text anywhere on the wire.
        for obj in objs where obj["event"] as? String == "workerActivity" {
            let data = obj["data"] as? [String: Any]
            XCTAssertNotNil(data?["activityKind"], "workerActivity must carry its activityKind")
            XCTAssertNil(data?["text"], "no raw text key on the wire")
        }
        for line in lines {
            XCTAssertFalse(line.contains("Hello"), "no raw delta text in any NDJSON line")
            XCTAssertFalse(line.contains("world"), "no raw delta text in any NDJSON line")
        }

        // Seq stays monotonic across activity + transition lines (RLR-L7 + Works Test 4).
        let seqs = objs.compactMap { $0["seq"] as? Int }
        XCTAssertEqual(seqs, seqs.sorted(), "seq is monotonic across activity lines")
        XCTAssertNil(NDJSONStreamProjector.firstSeqGap(seqs))
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
                workerSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"), builtIn: false)
            let teamsDir = support.appendingPathComponent("Catalogs/teams", isDirectory: true)
            try fm.createDirectory(at: teamsDir, withIntermediateDirectories: true)
            try CoreJSON.encode(CatalogEnvelope(kind: .team, definition: team))
                .write(to: teamsDir.appendingPathComponent("\(team.id).json"))
        }

        func tearDown() { try? FileManager.default.removeItem(at: temp) }
    }
}
