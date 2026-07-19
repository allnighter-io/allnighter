import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// Output-discipline + content tests for the `alln team --stream` NDJSON
/// projection (docs/phases/CLI_Implementation_Contract.md §NDJSON Stream).
/// Fixture-only; no live runs.
final class NDJSONStreamProjectorTests: XCTestCase {
    private let terminal: Set<String> = ["teamRunCompleted", "teamRunFailed", "error"]

    /// Each NDJSON line must parse independently as one JSON object, be a single
    /// line, and carry no ANSI. Returns the parsed objects in order.
    private func parseLines(_ lines: [String]) throws -> [[String: Any]] {
        try lines.map { line in
            XCTAssertFalse(line.contains("\n"), "NDJSON line must be single-line")
            XCTAssertFalse(line.contains("\u{1B}"), "no ANSI in machine output")
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try XCTUnwrap(obj as? [String: Any], "each line must be one JSON object")
        }
    }

    func testCompleteRunStreamShapeAndOrder() throws {
        let run = try Fixtures.run(.runComplete)
        let objs = try parseLines(NDJSONStreamProjector.lines(for: run))
        XCTAssertFalse(objs.isEmpty)

        // seq is monotonic 1..N.
        XCTAssertEqual(objs.compactMap { $0["seq"] as? Int }, Array(1...objs.count))
        // Begins with teamRunStarted, ends with a terminal event.
        XCTAssertEqual(objs.first?["event"] as? String, "teamRunStarted")
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
        XCTAssertTrue(terminal.contains(objs.last?["event"] as? String ?? ""))

        let events = objs.compactMap { $0["event"] as? String }
        XCTAssertTrue(events.contains("workerStarted"))
        XCTAssertTrue(events.contains("workerAnswered"))
        XCTAssertTrue(events.contains("planWritten"))   // run_complete has a done plan
        // Every line is stamped with the run id and schemaVersion.
        XCTAssertTrue(objs.allSatisfy { $0["teamRunId"] as? String == run.id })
        XCTAssertTrue(objs.allSatisfy { $0["schemaVersion"] as? Int == 1 })
    }

    func testPartialRunSurfacesWorkerFailuresAndNoPlanWritten() throws {
        let run = try Fixtures.run(.runPartial)
        let objs = try parseLines(NDJSONStreamProjector.lines(for: run))
        let events = objs.compactMap { $0["event"] as? String }

        // Failed workers are visible as workerFailed, each carrying an error.
        XCTAssertTrue(events.contains("workerFailed"))
        let failures = objs.filter { $0["event"] as? String == "workerFailed" }
        XCTAssertTrue(failures.allSatisfy { ($0["data"] as? [String: Any])?["error"] != nil })

        // Plan failed → planStarted but never planWritten.
        XCTAssertTrue(events.contains("planStarted"))
        XCTAssertFalse(events.contains("planWritten"))
        // Partial still terminates as completed (partial -> done).
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
    }

    func testEverySeqIsUniqueAndTerminalIsLastOnly() throws {
        for fixture in [Fixtures.Name.runComplete, .runPartial, .runInflight] {
            let run = try Fixtures.run(fixture)
            let objs = try parseLines(NDJSONStreamProjector.lines(for: run))
            let seqs = objs.compactMap { $0["seq"] as? Int }
            XCTAssertEqual(seqs.count, Set(seqs).count, "seq must be unique in \(fixture.rawValue)")
            let terminals = objs.filter { terminal.contains($0["event"] as? String ?? "") }
            XCTAssertEqual(terminals.count, 1, "exactly one terminal event in \(fixture.rawValue)")
            XCTAssertTrue(terminal.contains(objs.last?["event"] as? String ?? ""), "terminal must be last in \(fixture.rawValue)")
        }
    }

    // MARK: - RLR-S03b: durable seq carry-through, exactly-one-terminal, replay, gaps

    private let runId = "run_s03b"

    private func event(seq: Int64, kind: String, _ payload: [String: JSONValue]) -> RunEvent {
        var p = payload
        p["runId"] = .string(runId)
        return RunEvent(id: UUID().uuidString, seq: seq, ts: Date(), kind: kind, payload: p)
    }

    private func started(seq: Int64) -> RunEvent {
        event(seq: seq, kind: RunEventKind.runStatusChanged, [
            "to": .string(RunStatus.running.rawValue), "origin": .string("cli"), "presetId": .string("p")])
    }
    private func workerStarted(seq: Int64, _ w: String) -> RunEvent {
        event(seq: seq, kind: RunEventKind.workerStatusChanged, [
            "workerId": .string(w), "to": .string(WorkerAnswerStatus.running.rawValue)])
    }
    private func workerDone(seq: Int64, _ w: String) -> RunEvent {
        event(seq: seq, kind: RunEventKind.workerStatusChanged, [
            "workerId": .string(w), "to": .string(WorkerAnswerStatus.done.rawValue)])
    }
    private func runTerminal(seq: Int64, _ status: RunStatus) -> RunEvent {
        event(seq: seq, kind: RunEventKind.runStatusChanged, ["to": .string(status.rawValue)])
    }

    /// The mapper carries through the event's durable per-Mac seq rather than
    /// minting a fresh 1..N counter (RLR-L7).
    func testLiveMapperCarriesThroughDurableSeq() throws {
        let mapper = NDJSONStreamProjector.LiveMapper()
        let e = try XCTUnwrap(mapper.event(for: started(seq: 42)))
        XCTAssertEqual(e.seq, 42, "the visible seq is the durable event seq, not a reset counter")
        XCTAssertEqual(e.teamRunId, runId, "first event carries the runId")
        XCTAssertNil(e.replayed, "a live line carries no replayed marker")
    }

    /// Exactly one terminal per attachment on success / cancel / timeout, and any
    /// line after the terminal is dropped (RLR-L7). Kill is out of scope (S04).
    func testExactlyOneTerminalPerAttachmentOnSuccessCancelTimeout() throws {
        for status in [RunStatus.complete, .cancelled, .timedOut] {
            let att = NDJSONStreamProjector.NDJSONAttachment()
            XCTAssertNotNil(att.liveLine(for: started(seq: 1)))
            XCTAssertNotNil(att.liveLine(for: workerStarted(seq: 2, "w1")))
            let terminalLine = try XCTUnwrap(att.liveLine(for: runTerminal(seq: 3, status)),
                                             "the run-terminal transition must map to exactly one terminal")
            let obj = try parseLines([terminalLine])[0]
            XCTAssertTrue(terminal.contains(obj["event"] as? String ?? ""),
                          "\(status.rawValue) settles to a terminal NDJSON event")
            XCTAssertTrue(att.terminalEmitted)
            // A late worker event after the terminal is dropped — no post-terminal line.
            XCTAssertNil(att.liveLine(for: workerDone(seq: 4, "w1")),
                         "no line may follow the terminal (\(status.rawValue))")
            // closingLine must NOT emit a second terminal.
            XCTAssertNil(att.closingLine(), "a real terminal already went out — no double terminal")
        }
    }

    /// An attachment that closes before a terminal arrived synthesizes exactly one
    /// (ack-and-close: the ack IS the terminal, RLR-L7).
    func testAttachmentSynthesizesExactlyOneTerminalOnClose() throws {
        let att = NDJSONStreamProjector.NDJSONAttachment()
        XCTAssertNotNil(att.liveLine(for: started(seq: 1)))
        XCTAssertFalse(att.terminalEmitted)
        let closing = try XCTUnwrap(att.closingLine(), "close must synthesize the missing terminal")
        let obj = try parseLines([closing])[0]
        XCTAssertTrue(terminal.contains(obj["event"] as? String ?? ""))
        XCTAssertEqual(obj["teamRunId"] as? String, runId, "the synthesized terminal carries the runId")
        XCTAssertTrue(att.terminalEmitted)
        XCTAssertNil(att.closingLine(), "closing twice must not emit a second terminal")
    }

    /// Replay history is marked `replayed:true` and shares one durable seq space
    /// with the live tail; the whole run of seqs strictly ascends (RLR-L7).
    func testReplayAttachMarksHistoryReplayedThenLiveTailsInOneSeqSpace() throws {
        let att = NDJSONStreamProjector.NDJSONAttachment()
        let history = [started(seq: 1), workerStarted(seq: 2, "w1")]
        let replayObjs = try parseLines(att.replayLines(history))
        XCTAssertEqual(replayObjs.count, 2)
        XCTAssertTrue(replayObjs.allSatisfy { $0["replayed"] as? Bool == true }, "history lines are marked replayed")
        XCTAssertEqual(replayObjs.first?["teamRunId"] as? String, runId, "first (replayed) line carries the runId")

        let liveLines = [att.liveLine(for: workerDone(seq: 3, "w1")),
                         att.liveLine(for: runTerminal(seq: 4, .complete))].compactMap { $0 }
        let liveObjs = try parseLines(liveLines)
        XCTAssertTrue(liveObjs.allSatisfy { ($0["replayed"] as? Bool) != true }, "live tail lines are not replayed")

        let seqs = (replayObjs + liveObjs).compactMap { $0["seq"] as? Int }
        XCTAssertEqual(seqs, [1, 2, 3, 4], "history + live tail form one contiguous durable seq space")
        XCTAssertNil(NDJSONStreamProjector.firstSeqGap(seqs))
    }

    /// A missing event is detectable as a seq gap in the consumer's shared seq
    /// space (RLR-L7 gap detection).
    func testGapDetectableWhenEventMissing() throws {
        // Five mapping events; drop the middle one (seq 3) as if it were lost.
        let all = [started(seq: 1), workerStarted(seq: 2, "w1"), workerDone(seq: 3, "w1"),
                   workerStarted(seq: 4, "w2"), runTerminal(seq: 5, .complete)]
        let delivered = all.filter { $0.seq != 3 }
        let att = NDJSONStreamProjector.NDJSONAttachment()
        let objs = try parseLines(delivered.compactMap { att.liveLine(for: $0) })
        let seqs = objs.compactMap { $0["seq"] as? Int }
        XCTAssertEqual(seqs, [1, 2, 4, 5])
        let gap = try XCTUnwrap(NDJSONStreamProjector.firstSeqGap(seqs), "a missing event must surface as a gap")
        XCTAssertEqual(gap.expected, 3)
        XCTAssertEqual(gap.actual, 4)
        // A contiguous run has no gap.
        XCTAssertNil(NDJSONStreamProjector.firstSeqGap([1, 2, 3, 4, 5]))
    }
}
