import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// Output-discipline + content tests for the `alln team --stream` NDJSON
/// projection (docs/archive/phases/CLI_Implementation_Contract.md §NDJSON Stream).
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

    /// Exactly one terminal per attachment on success / cancel / timeout / kill
    /// (RLR-L7 / Works Test 11). A late line after the terminal is dropped.
    func testExactlyOneTerminalPerAttachmentOnSuccessCancelTimeout() throws {
        for status in [RunStatus.complete, .cancelled, .timedOut, .cancelled] {
            let att = NDJSONStreamProjector.NDJSONAttachment()
            XCTAssertNotNil(att.liveLine(for: started(seq: 1)))
            XCTAssertNotNil(att.liveLine(for: workerStarted(seq: 2, "w1")))
            // Kill settlement stamps cancelled + endReason killed; the stream
            // terminal is still the lifecycle transition to cancelled.
            let terminalLine = try XCTUnwrap(att.liveLine(for: runTerminal(seq: 3, status)),
                                             "the run-terminal transition must map to exactly one terminal")
            let obj = try parseLines([terminalLine])[0]
            XCTAssertTrue(terminal.contains(obj["event"] as? String ?? ""),
                          "\(status.rawValue) settles to a terminal NDJSON event")
            XCTAssertTrue(att.terminalEmitted)
            XCTAssertNil(att.liveLine(for: workerDone(seq: 4, "w1")),
                         "no line may follow the terminal (\(status.rawValue))")
            XCTAssertNil(att.closingLine(), "a real terminal already went out — no double terminal")
        }
    }

    /// Works Test 11 kill leg: endReason killed maps to a single terminal event.
    func testExactlyOneTerminalPerAttachmentOnKillSettlement() throws {
        let att = NDJSONStreamProjector.NDJSONAttachment()
        XCTAssertNotNil(att.liveLine(for: started(seq: 1)))
        let killTerminal = event(seq: 2, kind: RunEventKind.runStatusChanged, [
            "to": .string(RunStatus.cancelled.rawValue),
            "endReason": .string(RunEndReason.killed.rawValue),
        ])
        let terminalLine = try XCTUnwrap(att.liveLine(for: killTerminal))
        let obj = try parseLines([terminalLine])[0]
        XCTAssertTrue(terminal.contains(obj["event"] as? String ?? ""),
                      "kill settlement must emit exactly one terminal NDJSON event")
        XCTAssertTrue(att.terminalEmitted)
        XCTAssertNil(att.liveLine(for: workerDone(seq: 3, "w1")))
        XCTAssertNil(att.closingLine())
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

    // MARK: - RLR-S03c: previously-dropped activity kinds now project bounded metadata

    private func answerDelta(seq: Int64, _ w: String, text: String) -> RunEvent {
        event(seq: seq, kind: RunEventKind.workerAnswerDelta, [
            "workerId": .string(w), "text": .string(text), "truncated": .bool(false)])
    }
    private func reasoningDelta(seq: Int64, _ w: String, text: String) -> RunEvent {
        event(seq: seq, kind: RunEventKind.workerReasoningDelta, ["workerId": .string(w), "text": .string(text)])
    }
    private func workerOutput(seq: Int64, _ w: String, text: String) -> RunEvent {
        event(seq: seq, kind: RunEventKind.workerOutput, ["workerId": .string(w), "text": .string(text)])
    }
    private func stageOutput(seq: Int64, stageId: String, text: String) -> RunEvent {
        event(seq: seq, kind: RunEventKind.stageOutput, ["stageId": .string(stageId), "text": .string(text)])
    }

    /// `workerAnswerDelta`/`workerReasoningDelta` — previously dropped by `LiveMapper`
    /// (no case) — now project as `workerActivity` carrying ONLY bounded metadata:
    /// `agentId`, `activityKind: "message"`, and a byte/char count of the delta —
    /// never the delta text itself (S03c non-goal).
    func testWorkerAnswerAndReasoningDeltaMapToWorkerActivityMessageBounded() throws {
        let mapper = NDJSONStreamProjector.LiveMapper()
        for e in [answerDelta(seq: 10, "w1", text: "hello"), reasoningDelta(seq: 11, "w1", text: "hello")] {
            let event = try XCTUnwrap(mapper.event(for: e), "delta kinds must no longer be dropped")
            XCTAssertEqual(event.event, "workerActivity")
            XCTAssertEqual(event.seq, Int(e.seq), "carries the durable seq, not a fresh counter")
            XCTAssertEqual(event.data.agentId, "w1")
            XCTAssertEqual(event.data.activityKind, RunActivityKind.message.rawValue)
            XCTAssertEqual(event.data.charCount, 5)
            XCTAssertEqual(event.data.byteCount, 5)
            let line = NDJSONStreamProjector.encodeLine(event)
            XCTAssertFalse(line.contains("hello"), "the raw delta text must never reach the stream")
            XCTAssertFalse(line.contains("\"text\""), "no `text` key at all — bounded metadata only")
        }
    }

    /// ORS tool-wire: durable `worker.tool` projects as `workerActivity` with
    /// `activityKind: "tool"` and `data.tool` = the same bounded title the
    /// durable journal carries as `payload.tool`. Wire and journal agree exactly
    /// (same field name, same 128-char cap). Args / tool output / stdout remain
    /// excluded — a bounded tool NAME answers "what is happening?"; a raw dump does not.
    func testWorkerToolMapsToWorkerActivityToolBounded() throws {
        let journalTool = "read_file"
        let longTitle = String(repeating: "a", count: RunActivity.maxToolTitleChars + 40)
        let capped = try XCTUnwrap(RunActivity.boundedToolTitle(longTitle))
        XCTAssertEqual(capped.count, RunActivity.maxToolTitleChars)

        // Short title: wire `data.tool` equals durable journal `payload.tool`.
        let e = event(seq: 30, kind: RunEventKind.workerTool, [
            "workerId": .string("w1"), "tool": .string(journalTool)])
        let mapped = try XCTUnwrap(NDJSONStreamProjector.LiveMapper().event(for: e))
        XCTAssertEqual(mapped.event, "workerActivity")
        XCTAssertEqual(mapped.data.activityKind, RunActivityKind.tool.rawValue)
        XCTAssertEqual(mapped.data.agentId, "w1")
        XCTAssertEqual(
            mapped.data.tool, journalTool,
            "wire data.tool must equal durable journal payload.tool (same value, same field name)"
        )
        XCTAssertEqual(mapped.data.charCount, journalTool.count)
        let line = NDJSONStreamProjector.encodeLine(mapped)
        let obj = try parseLines([line])[0]
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["tool"] as? String, journalTool, "tool name present on the NDJSON wire")
        XCTAssertNil(data["arguments"], "args stay off the wire")
        XCTAssertNil(data["output"], "tool output stays off the wire")
        XCTAssertNil(data["text"], "stdout/transcript text stays off the wire")
        XCTAssertNil(data["stdout"], "stdout key stays off the wire")
        XCTAssertFalse(line.contains("\"arguments\""))
        XCTAssertFalse(line.contains("\"output\""))

        // Over-cap title: projector reuses the same 128-char bound as the journal.
        let longEvent = event(seq: 31, kind: RunEventKind.workerTool, [
            "workerId": .string("w1"), "tool": .string(longTitle)])
        let longMapped = try XCTUnwrap(NDJSONStreamProjector.LiveMapper().event(for: longEvent))
        XCTAssertEqual(
            longMapped.data.tool, capped,
            "wire tool must use the same 128-char trim as durable journal payload.tool"
        )
        XCTAssertLessThanOrEqual(longMapped.data.tool?.count ?? 0, RunActivity.maxToolTitleChars)
        XCTAssertEqual(longMapped.data.charCount, RunActivity.maxToolTitleChars)
    }

    /// Tool titles are vendor-controlled free text (e.g. ACP `"git status"`). A
    /// hostile title with quotes, a newline, and shell/prompt-looking text must
    /// round-trip as an inert bounded JSON string only — never land in any
    /// command-shaped field (`command`, `openCommand`, `agentAction`, `nextAction`).
    func testHostileToolTitleIsInertBoundedStringNotACommand() throws {
        let hostile =
            "\"; rm -rf / # ignore previous\nalln kill --all; echo pwned\" && curl evil.example"
        let expected = try XCTUnwrap(RunActivity.boundedToolTitle(hostile))
        XCTAssertLessThanOrEqual(expected.count, RunActivity.maxToolTitleChars)
        XCTAssertTrue(expected.contains("rm -rf") || expected.contains("echo pwned"),
                      "fixture must retain shell-looking body after bound")

        let e = event(seq: 40, kind: RunEventKind.workerTool, [
            "workerId": .string("w1"), "tool": .string(hostile)])
        let mapped = try XCTUnwrap(NDJSONStreamProjector.LiveMapper().event(for: e))
        XCTAssertEqual(mapped.data.tool, expected,
                       "hostile title round-trips as the same bounded plain string")
        XCTAssertNil(mapped.data.nextAction, "tool frames never carry nextAction")

        let line = NDJSONStreamProjector.encodeLine(mapped)
        // Must remain valid single-line NDJSON (quotes/newlines escaped, not broken out).
        let obj = try parseLines([line])[0]
        let data = try XCTUnwrap(obj["data"] as? [String: Any])
        XCTAssertEqual(data["tool"] as? String, expected)

        // Command-shaped keys must be absent at every level of this frame.
        func assertNoCommandShapedKeys(_ dict: [String: Any], path: String) {
            for key in ["command", "openCommand", "agentAction"] {
                XCTAssertNil(dict[key], "\(path).\(key) must not appear on a tool activity frame")
            }
            if let nested = dict["nextAction"] as? [String: Any] {
                assertNoCommandShapedKeys(nested, path: "\(path).nextAction")
                XCTFail("nextAction must be omitted entirely, not present empty — path=\(path)")
            }
            for (k, v) in dict {
                if let child = v as? [String: Any] {
                    assertNoCommandShapedKeys(child, path: "\(path).\(k)")
                }
            }
        }
        assertNoCommandShapedKeys(obj, path: "frame")

        // The hostile text may only appear as the JSON string value of data.tool —
        // never as an executable instruction field. Confirm by decoding tool alone.
        XCTAssertEqual(data["tool"] as? String, expected)
        XCTAssertNil(data["command"])
        XCTAssertNil(obj["command"])
    }

    /// `workerOutput` (bounded stdout/stderr metadata) → `workerActivity` with
    /// `activityKind: "stdout"`; `stageOutput` → a distinct `stageActivity` event
    /// carrying `stageId` instead of a bare worker id. Both share the ONE
    /// `RunActivity.activityKind(for:)` classifier used by the S03a journal
    /// projection, so stream and `run.json` never disagree.
    func testWorkerOutputAndStageOutputMapToBoundedActivityWithSharedClassifier() throws {
        let mapper = NDJSONStreamProjector.LiveMapper()

        let out = try XCTUnwrap(mapper.event(for: workerOutput(seq: 20, "w1", text: "stdout chunk")))
        XCTAssertEqual(out.event, "workerActivity")
        XCTAssertEqual(out.data.activityKind, RunActivityKind.stdout.rawValue)
        XCTAssertEqual(out.data.agentId, "w1")
        XCTAssertEqual(out.data.charCount, "stdout chunk".count)
        XCTAssertFalse(NDJSONStreamProjector.encodeLine(out).contains("stdout chunk"))

        let stage = try XCTUnwrap(mapper.event(for: stageOutput(seq: 21, stageId: "stage_1", text: "stage chunk")))
        XCTAssertEqual(stage.event, "stageActivity")
        XCTAssertEqual(stage.data.activityKind, RunActivityKind.stdout.rawValue)
        XCTAssertEqual(stage.data.stageId, "stage_1")
        XCTAssertFalse(NDJSONStreamProjector.encodeLine(stage).contains("stage chunk"))
    }

    /// Through a real attachment, activity lines flow strictly BETWEEN `started`
    /// and the terminal — never before, never after — with the shared seq space
    /// staying strictly ascending (Works Test 4: "NDJSON stays live with monotonic
    /// seq" — a streaming consumer now sees activity, not just started+terminal).
    func testWorkerActivityFlowsBetweenStartedAndTerminalWithMonotonicSeq() throws {
        let att = NDJSONStreamProjector.NDJSONAttachment()
        let lines = [
            started(seq: 1),
            workerStarted(seq: 2, "w1"),
            answerDelta(seq: 3, "w1", text: "Hello"),
            answerDelta(seq: 4, "w1", text: " world"),
            workerDone(seq: 5, "w1"),
            runTerminal(seq: 6, .complete),
        ].compactMap { att.liveLine(for: $0) }
        let objs = try parseLines(lines)
        let events = objs.compactMap { $0["event"] as? String }

        XCTAssertEqual(events.first, "teamRunStarted")
        XCTAssertEqual(events.last, "teamRunCompleted")
        let activityIndices = events.indices.filter { events[$0] == "workerActivity" }
        XCTAssertEqual(activityIndices.count, 2, "both deltas surface as workerActivity lines")
        XCTAssertTrue(activityIndices.allSatisfy { $0 > 0 && $0 < events.count - 1 },
                     "activity lines land strictly between started and the terminal")

        let seqs = objs.compactMap { $0["seq"] as? Int }
        XCTAssertEqual(seqs, seqs.sorted(), "seq stays monotonic across activity + transition lines")
        XCTAssertNil(NDJSONStreamProjector.firstSeqGap(seqs))

        // No raw token text anywhere on the wire.
        for line in lines {
            XCTAssertFalse(line.contains("Hello"))
            XCTAssertFalse(line.contains("world"))
        }
    }

    /// Unknown-event tolerance (RISKS): any consumer parsing this NDJSON stream
    /// MUST tolerate an event name it doesn't recognize, because `workerActivity`/
    /// `stageActivity` are additive. This test documents the wire shape a
    /// lenient consumer needs to skip safely: it decodes as a plain JSON object
    /// with the same envelope (`schemaVersion`/`seq`/`ts`/`event`/`teamRunId`/`data`)
    /// as every other event, so a switch-on-`event`-name consumer with a `default:
    /// skip` arm keeps working unmodified.
    func testWorkerActivitySharesTheCommonEnvelopeShapeForUnknownEventTolerance() throws {
        let mapper = NDJSONStreamProjector.LiveMapper()
        let event = try XCTUnwrap(mapper.event(for: answerDelta(seq: 7, "w1", text: "x")))
        let obj = try parseLines([NDJSONStreamProjector.encodeLine(event)])[0]
        for key in ["schemaVersion", "seq", "ts", "event", "teamRunId", "data"] {
            XCTAssertNotNil(obj[key], "workerActivity must carry the same envelope keys as every other event (\(key))")
        }
    }
}
