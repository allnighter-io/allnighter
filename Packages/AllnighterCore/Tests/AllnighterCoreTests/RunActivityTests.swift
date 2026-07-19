import XCTest
@testable import AllnighterCore

/// RLR-S03a (RLR-L6) — the pure activity projection, coalescing recorder, and
/// read-time staleness derivations. Durable-journal wiring is proven in the
/// engine `RunActivityJournalTests`.
final class RunActivityTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ kind: String, _ payload: [String: JSONValue] = [:], at: Date? = nil) -> RunEvent {
        RunEvent(id: UUID().uuidString, seq: 1, ts: at ?? t0, kind: kind, payload: payload)
    }

    // MARK: - activityKind projection: L6 kinds advance, spawn/queued do not

    func testMessageDeltasAreActivity() {
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.workerAnswerDelta)), .message)
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.workerReasoningDelta)), .message)
    }

    func testWorkerAndRunTerminalMapToExit() {
        // Worker statuses use snake_case raw values (`timed_out`).
        for status in ["done", "failed", "timed_out", "cancelled"] {
            XCTAssertEqual(
                RunActivity.activityKind(for: event(RunEventKind.workerStatusChanged, ["to": .string(status)])),
                .exit, "worker→\(status) is exit activity")
        }
        for status in ["done", "failed", "timedOut", "cancelled", "complete", "partial"] {
            XCTAssertEqual(
                RunActivity.activityKind(for: event(RunEventKind.runStatusChanged, ["to": .string(status)])),
                .exit, "run→\(status) is exit activity")
        }
    }

    func testStageTransitionsAreChild() {
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.stageStarted)), .child)
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.stageCompleted)), .child)
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.stageReused)), .child)
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.stageFailed)), .exit)
    }

    func testOutputIsStdout() {
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.workerOutput)), .stdout)
        XCTAssertEqual(RunActivity.activityKind(for: event(RunEventKind.stageOutput)), .stdout)
    }

    /// The RLR-L6 negative proof: spawn / queued / spawningWorker never advance
    /// activity — worker→running and run→(any non-terminal) map to nil.
    func testSpawnAndQueuedTransitionsAreNotActivity() {
        XCTAssertNil(RunActivity.activityKind(for: event(RunEventKind.workerStatusChanged, ["to": .string("running")])),
                     "worker spawn (queued→running) must not advance activity")
        XCTAssertNil(RunActivity.activityKind(for: event(RunEventKind.workerStatusChanged, ["to": .string("queued")])))
        XCTAssertNil(RunActivity.activityKind(for: event(RunEventKind.workerStatusChanged, ["to": .string("skipped")])))
        for status in ["queued", "running", "fanning_out", "answers_in", "planning", "reviewing", "finalizing"] {
            XCTAssertNil(
                RunActivity.activityKind(for: event(RunEventKind.runStatusChanged, ["to": .string(status)])),
                "run→\(status) (spawn/admission) must not advance activity")
        }
        // Missing/garbage `to` never invents activity.
        XCTAssertNil(RunActivity.activityKind(for: event(RunEventKind.workerStatusChanged)))
        XCTAssertNil(RunActivity.activityKind(for: event(RunEventKind.runStatusChanged, ["to": .string("not-a-status")])))
        XCTAssertNil(RunActivity.activityKind(for: event("some.unknown.kind")))
    }

    // MARK: - Coalescing recorder

    func testRecorderFlushesFirstActivityThenCoalescesWithinInterval() {
        let recorder = RunActivityRecorder(coalesceInterval: 1.0)
        // First activity always flushes.
        XCTAssertTrue(recorder.note(runId: "r", kind: .message, at: t0))
        // A chatty burst of the SAME kind within the interval → no further flush.
        var flushes = 0
        for i in 1...20 {
            if recorder.note(runId: "r", kind: .message, at: t0.addingTimeInterval(Double(i) * 0.01)) { flushes += 1 }
        }
        XCTAssertEqual(flushes, 0, "≤1 flush per interval — a token burst must not thrash the journal")
        // In-memory clock still reflects the LAST event.
        XCTAssertEqual(recorder.current(runId: "r")?.at, t0.addingTimeInterval(0.20))
    }

    func testRecorderAlwaysFlushesOnKindChangeAndTerminal() {
        let recorder = RunActivityRecorder(coalesceInterval: 1_000)
        XCTAssertTrue(recorder.note(runId: "r", kind: .message, at: t0))
        // Same kind, same instant → coalesced.
        XCTAssertFalse(recorder.note(runId: "r", kind: .message, at: t0))
        // Kind change → flush even inside the interval.
        XCTAssertTrue(recorder.note(runId: "r", kind: .child, at: t0),
                      "a kind-change always flushes")
        // Terminal exit → flush even inside the interval.
        XCTAssertTrue(recorder.note(runId: "r", kind: .exit, at: t0))
    }

    func testRecorderFlushesAfterIntervalElapses() {
        let recorder = RunActivityRecorder(coalesceInterval: 1.0)
        XCTAssertTrue(recorder.note(runId: "r", kind: .message, at: t0))
        XCTAssertFalse(recorder.note(runId: "r", kind: .message, at: t0.addingTimeInterval(0.5)))
        XCTAssertTrue(recorder.note(runId: "r", kind: .message, at: t0.addingTimeInterval(1.1)),
                      "past the coalesce interval a same-kind event flushes again")
    }

    func testRecorderStampAndForget() {
        let recorder = RunActivityRecorder()
        var run = TeamRun(id: "r", prompt: "p", createdAt: t0)
        recorder.stamp(&run)
        XCTAssertNil(run.lastActivityAt, "no activity yet → stamp writes nothing (spawn-only save)")
        _ = recorder.note(runId: "r", kind: .child, at: t0.addingTimeInterval(3))
        recorder.stamp(&run)
        XCTAssertEqual(run.lastActivityAt, t0.addingTimeInterval(3))
        XCTAssertEqual(run.lastActivityKind, .child)
        recorder.forget(runId: "r")
        XCTAssertNil(recorder.current(runId: "r"))
    }

    // MARK: - Read-time derivations

    func testProgressStaleAbsentBeforeFirstActivityThenDerived() {
        // Absent (nil) before any activity — RLR-L6.
        XCTAssertNil(RunActivity.progressStale(lastActivityAt: nil, now: t0, idleBudget: 30))
        // Fresh activity → not stale.
        XCTAssertEqual(RunActivity.progressStale(lastActivityAt: t0, now: t0.addingTimeInterval(10), idleBudget: 30), false)
        // Past the budget → stale.
        XCTAssertEqual(RunActivity.progressStale(lastActivityAt: t0, now: t0.addingTimeInterval(31), idleBudget: 30), true)
    }

    func testHeartbeatAgeDerivation() {
        XCTAssertNil(RunActivity.heartbeatAgeSeconds(lastActivityAt: nil, now: t0))
        XCTAssertEqual(RunActivity.heartbeatAgeSeconds(lastActivityAt: t0, now: t0.addingTimeInterval(12)), 12)
        // Never negative even if clocks skew.
        XCTAssertEqual(RunActivity.heartbeatAgeSeconds(lastActivityAt: t0.addingTimeInterval(5), now: t0), 0)
    }

    // MARK: - Additive wire: activity fields are optional/omitted when nil

    func testActivityFieldsAreAdditiveOptional() throws {
        let run = TeamRun(id: "r", prompt: "p", status: .queued, createdAt: t0)
        let json = String(decoding: try CoreJSON.encode(run), as: UTF8.self)
        XCTAssertFalse(json.contains("lastActivityAt"),
                       "nil activity is omitted on encode — legacy run.json (no key) decodes to nil")
        XCTAssertFalse(json.contains("lastActivityKind"))
        let decoded = try CoreJSON.decode(TeamRun.self, from: Data(json.utf8))
        XCTAssertNil(decoded.lastActivityAt)
        XCTAssertNil(decoded.lastActivityKind)
    }
}
