import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// ORS-S02a1 — always-on bounded event record on every run path.
///
/// Proof obligation: a launch with **no** `--stream` flag anywhere must produce
/// a replayable durable event sequence. This suite drives the same code path
/// the detached `--no-wait` child runs after flag strip — `RunService.run`
/// with no events continuation (the blocking non-stream entry) — rather than
/// spawning a real detached child inside the unit test.
final class OneRunSurfaceEventJournalTests: XCTestCase {

    // MARK: - Harness

    private struct Harness {
        let repo: URL
        let runsDir: URL
        let runStore: RunStore
        let journal: RemoteRunEventJournal
        let service: RunService
    }

    private func makeHarness(
        eventJournal: RemoteRunEventJournal? = nil,
        dribbleAnswerDeltas: Bool = false
    ) throws -> Harness {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02a1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let journal = eventJournal ?? RemoteRunEventJournal(rootDirectory: runsDir)

        var manifest = TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")
        let commandRunner: any CommandRunner
        if dribbleAnswerDeltas {
            manifest.streaming = .init(
                supported: true, mode: .jsonlStdout,
                args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
                partialOutput: true, finalAnswerSource: .parserAccumulator
            )
            let ndjson = """
            {"type":"text","data":"Hello"}
            {"type":"text","data":" world"}
            {"type":"end","stopReason":"EndTurn"}

            """
            commandRunner = DribblingORSCommandRunner([
                .started(startedAt: Date()),
                .stdout(Data(ndjson.utf8)),
                .completed(CommandResult(stdout: ndjson, exitCode: 0)),
            ])
        } else {
            commandRunner = MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)])
        }

        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"])
        )
        let probe = ToolProbeRecord(
            driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] },
            eventJournal: journal
        )
        return Harness(repo: repo, runsDir: runsDir, runStore: runStore, journal: journal, service: service)
    }

    // MARK: - Proof: blocking non-stream path records durable history

    /// Drives the shared blocking entry the `--no-wait` detached child runs
    /// (`RunService.run` with no `events:` continuation and no stream flag).
    /// A test that launched with `--stream` or called the journal directly would
    /// not satisfy the packet's proof obligation.
    func testNoStreamBlockingRunProducesReplayableDurableSequence() async throws {
        let h = try makeHarness(dribbleAnswerDeltas: true)
        defer { try? FileManager.default.removeItem(at: h.repo) }

        let runId = UUID().uuidString
        // No events continuation — equivalent to CLI `--json` / detached child
        // after `--no-wait` strips the flag. Not a stream launch.
        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path),
            origin: .cli,
            runId: runId
        )
        guard case .success(let run) = result else {
            return XCTFail("run must settle: \(result)")
        }
        XCTAssertTrue(run.status.isTerminal, "run must reach a terminal status")

        let replay = try h.journal.replay(after: 0)
        let forRun = try h.journal.events(forRunId: runId)
        XCTAssertFalse(forRun.isEmpty, "durable events.jsonl must exist for a --no-wait-equivalent run")
        XCTAssertFalse(replay.events.isEmpty, "replay(after: 0) must return a non-empty sequence")

        // Monotonic seq on the durable history.
        let seqs = forRun.map(\.seq)
        XCTAssertEqual(seqs, seqs.sorted(), "durable seq is monotonic")
        XCTAssertEqual(seqs.count, Set(seqs).count, "durable seq is unique")

        XCTAssertTrue(
            forRun.contains { $0.kind == RunEventKind.runStatusChanged },
            "must contain at least one run.status_changed"
        )
        let terminalKinds = forRun.filter { $0.kind == RunEventKind.runStatusChanged }
        XCTAssertTrue(
            terminalKinds.contains { event in
                if case .string(let to)? = event.payload["to"] {
                    return [
                        RunStatus.complete.rawValue,
                        RunStatus.done.rawValue,
                        RunStatus.partial.rawValue,
                        RunStatus.failed.rawValue,
                        RunStatus.cancelled.rawValue,
                        RunStatus.timedOut.rawValue,
                    ].contains(to)
                }
                return false
            },
            "must contain terminal settlement via run.status_changed"
        )

        // Rule 2 — not a transcript.
        let banned: Set<String> = [
            RunEventKind.workerAnswerDelta,
            RunEventKind.workerReasoningDelta,
            RunEventKind.workerOutput,
        ]
        let bannedHits = forRun.filter { banned.contains($0.kind) }
        XCTAssertTrue(
            bannedHits.isEmpty,
            "durable journal must not hold transcript kinds; got \(bannedHits.map(\.kind))"
        )

        // On-disk file exists under the internal run directory (not a public contract).
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: h.journal.eventsURL(forRunId: runId).path),
            "events.jsonl must land under run_<id>/ as internal storage"
        )
    }

    // MARK: - Degrade, never block (rule 8)

    /// Journal root is unwritable: the run still settles and RunStore still loads.
    func testUnwritableJournalDoesNotFailOrHideSettledRun() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02a1-degrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        let runStore = RunStore(rootDirectory: runsDir)

        // Separate journal root so RunStore can still write run.json while
        // every journal append fails closed.
        let journalDir = repo.appendingPathComponent("journal_ro", isDirectory: true)
        try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
        // Make the journal directory unwritable for this process.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: journalDir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: journalDir.path
            )
        }

        let journal = RemoteRunEventJournal(rootDirectory: journalDir)
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_cursor_composer_25"])
        )
        let probe = ToolProbeRecord(
            driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] },
            eventJournal: journal
        )

        let runId = UUID().uuidString
        let result = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path),
            origin: .cli,
            runId: runId
        )
        guard case .success(let run) = result else {
            return XCTFail("broken journal must not fail the run: \(result)")
        }
        XCTAssertTrue(run.status.isTerminal, "run must still settle when journal I/O fails")

        // Run truth lives in RunStore — snapshot still loads.
        let loaded = runStore.load(runId: runId) ?? runStore.loadRaw(runId: runId)
        XCTAssertEqual(loaded?.id, runId, "settled run snapshot must still load from RunStore")
        XCTAssertTrue(loaded?.status.isTerminal == true)
    }

    // MARK: - Retention bound (rule 4)

    func testRetentionBoundRefusesFurtherDurableLines() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02a1-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let journal = RemoteRunEventJournal(rootDirectory: root)
        let runId = "cap-run"
        // Fill to the count cap with minimal status lines.
        for i in 0..<RemoteRunEventJournal.maxEventsPerRun {
            _ = try journal.append(RunEvent(
                id: "evt_\(i)",
                seq: 0,
                ts: Date(),
                kind: RunEventKind.runStatusChanged,
                payload: [
                    "runId": .string(runId),
                    "to": .string(RunStatus.running.rawValue),
                ]
            ))
        }
        XCTAssertEqual(try journal.events(forRunId: runId).count, RemoteRunEventJournal.maxEventsPerRun)

        XCTAssertThrowsError(
            try journal.append(RunEvent(
                id: "evt_overflow",
                seq: 0,
                ts: Date(),
                kind: RunEventKind.runStatusChanged,
                payload: [
                    "runId": .string(runId),
                    "to": .string(RunStatus.complete.rawValue),
                ]
            ))
        ) { error in
            XCTAssertEqual(
                error as? RemoteRunEventJournalError,
                .retentionBoundExceeded(runId: runId)
            )
        }
        // Cap held — no extra durable line.
        XCTAssertEqual(try journal.events(forRunId: runId).count, RemoteRunEventJournal.maxEventsPerRun)
    }

    func testDurableKindFilter() {
        // Durable: status transitions + stage lifecycle + bounded tool (ORS-S02a1/a2).
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.runStatusChanged))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerStatusChanged))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerTool))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.stageStarted))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.stageCompleted))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.stageFailed))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.stageReused))
        // Live-only transcript — would fail if the filter is widened later.
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerAnswerDelta))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerReasoningDelta))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerOutput))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.stageOutput))
    }

    // MARK: - ORS-S02a2: durable worker.tool on incremental / silence on terminalOnly

    /// `--no-wait` equivalent (no `events:` continuation) on an incremental warm
    /// driver that reports tool activity must land durable `worker.tool` lines
    /// replayable after reattach. Proves the Works Test step-4 path without a
    /// `--stream` launch.
    func testNoWaitIncrementalProducesDurableWorkerTool() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02a2-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let journal = RemoteRunEventJournal(rootDirectory: runsDir)
        let warmPool = WarmWorkerPool()

        let threadId = "ors-tool-thread"
        let modelId = "model_cursor_composer_25"
        let driverId = "cursor_agent"
        let root = RunWriteLock.normalize(repo.path) ?? repo.path

        // Pre-seed warm worker so RunService reuses it (never spawns real ACP).
        let key = ExternalWorkerSession.Key(
            threadId: threadId, sourceId: driverId, modelId: modelId, repoRoot: root)
        let scripted = ScriptedToolWarmDriver(events: [
            .toolActivity("read_file"),
            .toolActivity("git status"),
            // Deliberately large "args-looking" title must still be title-only
            // after bound (never stored as raw stdout/args).
            .toolActivity("read_file"),
            .answerDelta("Done via tools."),
        ])
        _ = try await warmPool.worker(for: key) { key in
            WarmWorker(key: key, driver: scripted, cwd: root)
        }

        var manifest = TestSupport.headlessManifest(id: driverId, command: "cursor")
        // Incremental: canStream true — activityMode + tool emission gate.
        manifest.streaming = .init(
            supported: true, mode: .jsonlStdout,
            args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
            partialOutput: true, finalAnswerSource: .parserAccumulator
        )
        let model = Model(
            id: modelId, displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: driverId, role: .both
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: [modelId])
        )
        let probe = ToolProbeRecord(
            driverId: driverId, status: .ready(version: "1.0"), lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            runStore: runStore,
            // Cold fallback must never fire for this proof; fail loudly if it does.
            commandRunner: MockCommandRunner(scripts: [:]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] },
            warmPool: warmPool,
            eventJournal: journal
        )

        let runId = UUID().uuidString
        // No events continuation — the detached --no-wait child path.
        let result = await service.run(
            RunRequest(
                message: "Use tools then say done",
                repoRoot: repo.path,
                threadId: threadId,
                pinnedModelId: modelId
            ),
            origin: .cli,
            runId: runId
        )
        guard case .success(let run) = result else {
            return XCTFail("run must settle: \(result)")
        }
        XCTAssertTrue(run.status.isTerminal)

        let forRun = try journal.events(forRunId: runId)
        let toolEvents = forRun.filter { $0.kind == RunEventKind.workerTool }
        XCTAssertFalse(
            toolEvents.isEmpty,
            "incremental no-wait run must durable-record worker.tool; kinds=\(forRun.map(\.kind))"
        )
        XCTAssertEqual(RunEventKind.workerTool, "worker.tool")

        // Bounded payload: tool title/name only — no args, stdout, or file bodies.
        for event in toolEvents {
            XCTAssertEqual(Set(event.payload.keys), Set(["runId", "workerId", "tool"]),
                           "worker.tool payload keys must be exactly runId/workerId/tool")
            guard case .string(let tool)? = event.payload["tool"] else {
                return XCTFail("tool payload must be a string title")
            }
            XCTAssertFalse(tool.isEmpty)
            XCTAssertLessThanOrEqual(tool.count, 128)
            // Explicit exclusions — would pass a weaker "kind present" assertion.
            XCTAssertFalse(tool.contains("arguments"))
            XCTAssertFalse(tool.contains("stdout"))
            XCTAssertNil(event.payload["arguments"])
            XCTAssertNil(event.payload["text"])
            XCTAssertNil(event.payload["output"])
            XCTAssertNil(event.payload["content"])
        }
        XCTAssertTrue(toolEvents.contains {
            if case .string(let t)? = $0.payload["tool"] { return t == "read_file" }
            return false
        })
        XCTAssertTrue(toolEvents.contains {
            if case .string(let t)? = $0.payload["tool"] { return t == "git status" }
            return false
        })

        // Transcript kinds still banned from durable journal.
        let banned: Set<String> = [
            RunEventKind.workerAnswerDelta,
            RunEventKind.workerReasoningDelta,
            RunEventKind.workerOutput,
        ]
        XCTAssertTrue(forRun.filter { banned.contains($0.kind) }.isEmpty)

        // Reattach: replay returns the same tool events (seq-monotonic history).
        let replay = try journal.replay(after: 0)
        let replayedTools = replay.events.filter { event in
            guard event.kind == RunEventKind.workerTool,
                  case .string(let id)? = event.payload["runId"] else { return false }
            return id == runId
        }
        XCTAssertEqual(replayedTools.count, toolEvents.count)
    }

    /// Production cold path for `alln run --model model_grok --no-wait`:
    /// no `threadId` → warm ACP gate closed → `DefaultWorkerRunner` +
    /// `StreamParserFactory` for driver id `grok` (streaming-json).
    /// Fixture is the **real** grok wire shape (`type=tool_call` + title), not a
    /// pre-seeded ACP stub. Fails if the production parser stops mapping tool_call
    /// → `WorkerStreamEvent.toolActivity` (the ORS-S02a2 live miss).
    func testNoWaitColdGrokStreamingJsonProducesDurableWorkerTool() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02a2-cold-grok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let journal = RemoteRunEventJournal(rootDirectory: runsDir)

        // Production model_grok → driver id "grok" (catalog), canStream true.
        var manifest = TestSupport.headlessManifest(id: "grok", command: "grok")
        manifest.streaming = .init(
            supported: true, mode: .jsonlStdout,
            args: ["-p", "{{prompt}}", "--output-format", "streaming-json"],
            partialOutput: true,
            answerDeltaPaths: ["$.data"],
            finalAnswerSource: .parserAccumulator
        )
        // Real grok streaming-json lines (captured from `grok --output-format streaming-json`).
        // tool_call carries title; tool_call_update must not fabricate a second activity.
        let ndjson = """
        {"type":"thought","data":"Reading the file."}
        {"type":"tool_call","toolCallId":"call-1","title":"read_file","kind":"read","status":"pending","toolName":"read_file","rawInput":{"target_file":"AGENTS.md","limit":3},"content":[],"locations":[]}
        {"type":"tool_call_update","toolCallId":"call-1","status":null,"content":[],"rawOutput":null,"locations":[{"path":"AGENTS.md"}]}
        {"type":"tool_call","toolCallId":"call-2","title":"run_terminal_command","kind":"execute","status":"pending","toolName":"run_terminal_command","rawInput":{"command":"git status"},"content":[],"locations":[]}
        {"type":"text","data":"Done via tools."}
        {"type":"end","stopReason":"end_turn","sessionId":"gs-cold-1"}

        """
        // StreamingCommandRunner with live stdout chunks — the cold production path.
        // (CommandRunnerAsStreaming would discard parser tool events in the
        // degraded-stream finalAnswer replay.)
        let commandRunner = DribblingORSCommandRunner([
            .started(startedAt: Date()),
            .stdout(Data(ndjson.utf8)),
            .completed(CommandResult(stdout: ndjson, exitCode: 0)),
        ])

        let model = Model(
            id: "model_grok", displayName: "Grok 4.5",
            modelLabel: "grok-4.5", driverId: "grok", role: .both
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: ["model_grok"])
        )
        let probe = ToolProbeRecord(
            driverId: "grok", status: .ready(version: "1.0"), lastProbeAt: .distantPast
        )
        // Fresh warm pool + no threadId on the request → cannot enter warm ACP.
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            runStore: runStore,
            commandRunner: commandRunner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] },
            warmPool: WarmWorkerPool(),
            eventJournal: journal
        )

        let runId = UUID().uuidString
        // No threadId: production CLI --no-wait path (warm ACP gate requires threadId).
        let result = await service.run(
            RunRequest(
                message: "Use tools then say done",
                repoRoot: repo.path,
                pinnedModelId: "model_grok"
            ),
            origin: .cli,
            runId: runId
        )
        guard case .success(let run) = result else {
            return XCTFail("cold grok run must settle: \(result)")
        }
        XCTAssertTrue(run.status.isTerminal)
        // Prove cold stream path was used (raw stdout chunks), not warm ACP.
        XCTAssertGreaterThan(
            run.answers.first?.result.timing.rawStdoutChunkCount ?? 0, 0,
            "must take cold DefaultWorkerRunner path (raw stdout), not warm ACP"
        )

        let forRun = try journal.events(forRunId: runId)
        let toolEvents = forRun.filter { $0.kind == RunEventKind.workerTool }
        XCTAssertFalse(
            toolEvents.isEmpty,
            "cold grok streaming-json must durable-record worker.tool; kinds=\(forRun.map(\.kind))"
        )
        let titles = toolEvents.compactMap { event -> String? in
            if case .string(let t)? = event.payload["tool"] { return t }
            return nil
        }
        XCTAssertTrue(titles.contains("read_file"), "expected read_file from wire title; got \(titles)")
        XCTAssertTrue(titles.contains("run_terminal_command"),
                      "expected run_terminal_command from wire title; got \(titles)")
        for event in toolEvents {
            XCTAssertEqual(Set(event.payload.keys), Set(["runId", "workerId", "tool"]))
            guard case .string(let tool)? = event.payload["tool"] else {
                return XCTFail("tool must be string")
            }
            XCTAssertFalse(tool.contains("rawInput"))
            XCTAssertFalse(tool.contains("AGENTS.md"))
            XCTAssertFalse(tool.contains("git status"))
        }

        // Incremental observation (canStream) — same gate as the live miss.
        let json = TeamRunJSONMapper.map(
            run, models: [model], manifests: [manifest],
            context: .init(reproduceCommand: "alln show \(runId)")
        )
        XCTAssertEqual(json.observation.activityMode, .incremental)
    }

    /// terminalOnly driver: no tool events, healthy expected silence (inference ban).
    func testTerminalOnlyProducesNoToolEventsAndReportsHealthy() async throws {
        let h = try makeHarness(dribbleAnswerDeltas: false)
        defer { try? FileManager.default.removeItem(at: h.repo) }

        // Default headlessManifest has no streaming → canStream false → terminalOnly.
        let runId = UUID().uuidString
        let result = await h.service.run(
            RunRequest(message: "Say done", repoRoot: h.repo.path),
            origin: .cli,
            runId: runId
        )
        guard case .success(let run) = result else {
            return XCTFail("terminalOnly run must settle: \(result)")
        }
        XCTAssertTrue(run.status.isTerminal)

        let forRun = try h.journal.events(forRunId: runId)
        let toolHits = forRun.filter { $0.kind == RunEventKind.workerTool }
        XCTAssertTrue(
            toolHits.isEmpty,
            "terminalOnly must not fabricate worker.tool; got \(toolHits.count)"
        )

        // Observation reports terminalOnly (expected silence), not a defect.
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both
        )
        let manifest = TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")
        XCTAssertFalse(manifest.canStream, "harness terminalOnly premise")
        let json = TeamRunJSONMapper.map(
            run, models: [model], manifests: [manifest],
            context: .init(reproduceCommand: "alln show \(runId)")
        )
        XCTAssertEqual(json.observation.activityMode, .terminalOnly)
        XCTAssertTrue(run.status.isTerminal, "still healthy/settled")
    }

    /// Tool-heavy burst past the retention cap: run still settles, RunStore holds
    /// terminal truth, journal stays ≤ cap, show projection does not fail.
    func testToolBurstPastRetentionCapStillSettles() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02a2-cap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let runsDir = repo.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsDir)
        let journal = RemoteRunEventJournal(rootDirectory: runsDir)
        let warmPool = WarmWorkerPool()

        let threadId = "ors-tool-cap"
        let modelId = "model_cursor_composer_25"
        let driverId = "cursor_agent"
        let root = RunWriteLock.normalize(repo.path) ?? repo.path
        let overflow = RemoteRunEventJournal.maxEventsPerRun + 40

        let toolEvents: [ACPTurnEvent] =
            (0..<overflow).map { .toolActivity("tool_\($0)") } + [.answerDelta("Settled after tools.")]
        let key = ExternalWorkerSession.Key(
            threadId: threadId, sourceId: driverId, modelId: modelId, repoRoot: root)
        _ = try await warmPool.worker(for: key) { key in
            WarmWorker(key: key, driver: ScriptedToolWarmDriver(events: toolEvents), cwd: root)
        }

        var manifest = TestSupport.headlessManifest(id: driverId, command: "cursor")
        manifest.streaming = .init(
            supported: true, mode: .jsonlStdout,
            args: ["-p", "{{prompt}}"], partialOutput: true, finalAnswerSource: .parserAccumulator
        )
        let model = Model(
            id: modelId, displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: driverId, role: .both
        )
        let settings = DefaultModelSettings(
            defaultTier: .frontier, allowHealthySubstitutions: true,
            tiers: TierMembership(frontier: [modelId])
        )
        let probe = ToolProbeRecord(
            driverId: driverId, status: .ready(version: "1.0"), lastProbeAt: .distantPast
        )
        let service = RunService(
            models: [model],
            registry: DriverRegistry([manifest]),
            runStore: runStore,
            commandRunner: MockCommandRunner(scripts: [:]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] },
            warmPool: warmPool,
            eventJournal: journal
        )

        let runId = UUID().uuidString
        let result = await service.run(
            RunRequest(
                message: "tool heavy",
                repoRoot: repo.path,
                threadId: threadId,
                pinnedModelId: modelId
            ),
            origin: .cli,
            runId: runId
        )
        guard case .success(let run) = result else {
            return XCTFail("cap must not fail the run: \(result)")
        }
        XCTAssertTrue(run.status.isTerminal, "run settles even when journal is full")

        let durable = try journal.events(forRunId: runId)
        XCTAssertLessThanOrEqual(
            durable.count, RemoteRunEventJournal.maxEventsPerRun,
            "journal must refuse past the count cap (degrade, never grow unbounded)"
        )
        // At least some tool lines landed before the cap.
        XCTAssertTrue(durable.contains { $0.kind == RunEventKind.workerTool })

        // Terminal truth lives in RunStore — not the (possibly truncated) journal.
        let loaded = runStore.load(runId: runId) ?? runStore.loadRaw(runId: runId)
        XCTAssertEqual(loaded?.id, runId)
        XCTAssertTrue(loaded?.status.isTerminal == true)

        // show --json projection must not fail because history truncated.
        let json = TeamRunJSONMapper.map(
            loaded ?? run, models: [model], manifests: [manifest],
            context: .init(reproduceCommand: "alln show \(runId)")
        )
        XCTAssertEqual(json.teamRun.id, runId)
        XCTAssertEqual(json.observation.activityMode, .incremental)
    }
}

// Local double of the stream-contract dribbler so this ORS suite does not
// depend on a private type in another test file.
private final class DribblingORSCommandRunner: CommandRunner, StreamingCommandRunner, @unchecked Sendable {
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

/// Scripted warm ACP driver for ORS-S02a2 — yields fixed tool + answer events
/// without spawning a real agent process.
private final class ScriptedToolWarmDriver: WarmSessionDriver, @unchecked Sendable {
    private let events: [ACPTurnEvent]
    init(events: [ACPTurnEvent]) { self.events = events }

    func start(cwd: String) async throws {}
    func prompt(_ text: String) async -> AsyncThrowingStream<ACPTurnEvent, Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
    func shutdown() async {}
    var vendorSessionId: String? { get async { "ors-s02a2-session" } }
}
