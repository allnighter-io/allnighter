import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RLR-S03a (RLR-L6) — durable activity projection onto `run.json`, coalesced
/// writes, `heartbeat.json` retired as truth, and read surfaces (`ps`) sourced
/// from the journal. The pure projection/recorder/derivation logic is covered
/// by `RunActivityTests`; this exercises the on-disk wiring.
final class RunActivityJournalTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempStore() throws -> (URL, RunStore) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlr-activity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, RunStore(rootDirectory: dir))
    }

    private func nonTerminalRun(id: String = "run-1") -> TeamRun {
        TeamRun(id: id, prompt: "p", status: .running, createdAt: t0, repoRoot: "/tmp/repo")
    }

    private func event(_ kind: String, _ payload: [String: JSONValue] = [:], at: Date) -> RunEvent {
        RunEvent(id: UUID().uuidString, seq: 1, ts: at, kind: kind, payload: payload)
    }

    // MARK: - Activity advances only on post-spawn L6 events (the acceptance)

    func testActivityAdvancesOnFirstMessageNotOnSpawn() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(nonTerminalRun(), models: [])
        let recorder = RunActivityRecorder()

        // Spawn/admission events do NOT advance durable activity (RLR-L6).
        RunActivityJournalProjection.observe(
            event(RunEventKind.runStatusChanged, ["to": .string("running")], at: t0.addingTimeInterval(1)),
            runId: "run-1", store: store, recorder: recorder)
        RunActivityJournalProjection.observe(
            event(RunEventKind.workerStatusChanged, ["to": .string("running")], at: t0.addingTimeInterval(2)),
            runId: "run-1", store: store, recorder: recorder)
        XCTAssertNil(store.loadRaw(runId: "run-1")?.lastActivityAt,
                     "spawn alone must not advance lastActivityAt (nil before first activity)")

        // First post-spawn message advances it durably.
        RunActivityJournalProjection.observe(
            event(RunEventKind.workerAnswerDelta, at: t0.addingTimeInterval(3)),
            runId: "run-1", store: store, recorder: recorder)
        let run = try XCTUnwrap(store.loadRaw(runId: "run-1"))
        XCTAssertEqual(run.lastActivityAt, t0.addingTimeInterval(3))
        XCTAssertEqual(run.lastActivityKind, .message)
    }

    func testStreamingWritesCoalesceToOnePerInterval() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(nonTerminalRun(), models: [])
        let recorder = RunActivityRecorder(coalesceInterval: 1.0)

        // A chatty burst of message deltas inside one interval.
        for i in 0..<10 {
            RunActivityJournalProjection.observe(
                event(RunEventKind.workerAnswerDelta, at: t0.addingTimeInterval(Double(i) * 0.05)),
                runId: "run-1", store: store, recorder: recorder)
        }
        // Only the FIRST flushed → durable clock is the first ts (≤1 write / interval).
        // (`run.json` dates floor to whole seconds; t0 and the offsets below are
        // chosen on whole-second boundaries so the assertion is exact.)
        XCTAssertEqual(store.loadRaw(runId: "run-1")?.lastActivityAt, t0,
                       "coalesced: the journal holds the first-of-interval activity, not every token")
        // In-memory clock still reflects the last token.
        XCTAssertEqual(recorder.current(runId: "run-1")?.at, t0.addingTimeInterval(0.45))

        // Past the interval, the next delta flushes again (whole-second ts).
        RunActivityJournalProjection.observe(
            event(RunEventKind.workerAnswerDelta, at: t0.addingTimeInterval(2)),
            runId: "run-1", store: store, recorder: recorder)
        XCTAssertEqual(store.loadRaw(runId: "run-1")?.lastActivityAt, t0.addingTimeInterval(2))
    }

    /// Transition kinds ride the coordinator's persist stamp; the standalone
    /// projection deliberately does NOT write `run.json` for them (so an `.exit`
    /// can never resurrect a terminal run out of band).
    func testTransitionKindsDoNotWriteStandaloneAndRidePersistStamp() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(nonTerminalRun(), models: [])
        let recorder = RunActivityRecorder()

        RunActivityJournalProjection.observe(
            event(RunEventKind.stageStarted, at: t0.addingTimeInterval(4)),
            runId: "run-1", store: store, recorder: recorder)
        XCTAssertNil(store.loadRaw(runId: "run-1")?.lastActivityAt,
                     "child transitions do not standalone-write; they ride the persist stamp")
        // But the in-memory clock advanced, so the next persist stamps it.
        var run = try XCTUnwrap(store.loadRaw(runId: "run-1"))
        recorder.stamp(&run)
        XCTAssertEqual(run.lastActivityAt, t0.addingTimeInterval(4))
        XCTAssertEqual(run.lastActivityKind, .child)
    }

    func testStampActivityNeverResurrectsTerminalRun() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var terminal = nonTerminalRun()
        terminal.status = .done
        terminal.endReason = .completed
        try store.save(terminal, models: [])

        store.stampActivity(runId: "run-1", at: t0.addingTimeInterval(9), kind: .message)
        let run = try XCTUnwrap(store.loadRaw(runId: "run-1"))
        XCTAssertEqual(run.status, .done, "a late activity flush must not reopen a terminal run")
        XCTAssertNil(run.lastActivityAt, "terminal run gains no activity stamp")
    }

    // MARK: - heartbeat.json retired as truth

    /// Regression against the incident signature: a per-save floor touch no
    /// longer advances `heartbeat.json` (`touchedAt` frozen while `sequence` at 0
    /// was the lie). `RunStore.save` must not touch the heartbeat floor.
    func testSaveDoesNotAdvanceHeartbeatFloor() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let run = nonTerminalRun()
        try store.save(run, models: [])
        let runDir = try store.runDirectory(forRunId: "run-1")

        // Seed a frozen heartbeat as the incident had it.
        let frozen = ProcessOwnership.ProgressHeartbeat(
            sequence: 0, phase: "accepted", lastProgressAt: t0, touchedAt: t0)
        try CoreJSON.encode(frozen).write(to: ProcessOwnership.heartbeatURL(in: runDir), options: .atomic)

        // Re-save the (still non-terminal) run several times.
        for _ in 0..<3 { try store.save(run, models: []) }

        let after = try XCTUnwrap(ProcessOwnership.readProgressHeartbeat(in: runDir))
        XCTAssertEqual(after.touchedAt, t0, "RunStore.save must not advance the heartbeat floor (timer retired)")
        XCTAssertEqual(after.sequence, 0)
    }

    /// `ps` sources last-activity from `run.json`, never `heartbeat.json`.
    func testPsSourcesActivityFromRunJsonNotHeartbeat() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let activityAt = t0.addingTimeInterval(50)
        var run = nonTerminalRun()
        run.lastActivityAt = activityAt
        run.lastActivityKind = .message
        try store.save(run, models: [])
        let runDir = try store.runDirectory(forRunId: "run-1")
        // A lying, frozen heartbeat at a DIFFERENT time — must be ignored.
        let lie = ProcessOwnership.ProgressHeartbeat(
            sequence: 0, phase: "accepted", lastProgressAt: t0, touchedAt: t0)
        try CoreJSON.encode(lie).write(to: ProcessOwnership.heartbeatURL(in: runDir), options: .atomic)

        let now = activityAt.addingTimeInterval(10)
        let surface = ProcessOwnershipSurface(
            runStore: store,
            relayStore: RelayStateStore(rootDirectory: dir.appendingPathComponent("relays")),
            lanesRoot: dir.appendingPathComponent("lanes"),
            now: { now })
        let row = try XCTUnwrap(surface.list().processes.first { $0.id == "run-1" })
        XCTAssertEqual(row.lastProgressAt, activityAt, "ps reads run.json.lastActivityAt, not the frozen heartbeat")
        XCTAssertEqual(row.lastActivityKind, "message")
        XCTAssertEqual(row.heartbeatAgeSeconds, 10)
        XCTAssertEqual(row.progressStale, false, "fresh activity within the idle budget")
    }

    func testPsProgressStaleAbsentBeforeActivityAndOnTerminal() throws {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Non-terminal, no activity yet → progressStale absent (nil).
        try store.save(nonTerminalRun(id: "run-fresh"), models: [])
        // Terminal with activity → derivations suppressed.
        var done = nonTerminalRun(id: "run-done")
        done.lastActivityAt = t0
        done.status = .done
        done.endReason = .completed
        try store.save(done, models: [])

        let now = t0.addingTimeInterval(10_000)
        let surface = ProcessOwnershipSurface(
            runStore: store,
            relayStore: RelayStateStore(rootDirectory: dir.appendingPathComponent("relays")),
            lanesRoot: dir.appendingPathComponent("lanes"),
            now: { now })
        // The terminal "run-done" row is history (CLP-S03 hides identity-dead
        // terminal rows from the default floor); opt in so its derivation is
        // still checkable here.
        let rows = Dictionary(uniqueKeysWithValues: surface.list(includeHistory: true).processes.map { ($0.id, $0) })
        XCTAssertNil(try XCTUnwrap(rows["run-fresh"]).progressStale,
                     "no activity yet → progressStale absent (RLR-L6)")
        XCTAssertNil(try XCTUnwrap(rows["run-done"]).progressStale,
                     "terminal runs surface no staleness derivation")
    }
}
