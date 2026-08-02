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
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.runStatusChanged))
        XCTAssertTrue(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerStatusChanged))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerAnswerDelta))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerReasoningDelta))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.workerOutput))
        XCTAssertFalse(RemoteRunEventJournal.isDurableSemanticEvent(RunEventKind.stageStarted))
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
