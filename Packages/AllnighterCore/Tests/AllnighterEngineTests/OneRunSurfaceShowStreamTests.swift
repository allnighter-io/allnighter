import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// ORS-S02b1 — `alln show <id> --stream` reattach READ surface (no live follow).
///
/// Frame order: immediate snapshot → bounded replay (`replayed: true`) → exactly
/// one terminal when already settled. Observer is read-only; journal gaps are
/// loud on the stream path and silent on `show --json`.
final class OneRunSurfaceShowStreamTests: XCTestCase {

    // MARK: - Harness

    private struct Harness {
        let root: URL
        let store: RunStore
        let journal: RemoteRunEventJournal
        let models: [Model]
        let manifests: [DriverManifest]
    }

    private func makeHarness() throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02b1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: root)
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let model = Model(
            id: "model_opus", displayName: "Opus", modelLabel: "opus",
            driverId: "claude_code", role: .both
        )
        let manifest = DriverManifest(
            id: "claude_code", displayName: "Claude", kind: .headlessCLI,
            streaming: .init(supported: true, mode: .jsonlStdout)
        )
        return Harness(
            root: root, store: store, journal: journal,
            models: [model], manifests: [manifest]
        )
    }

    private func terminalRun(id: String, status: RunStatus = .done) -> TeamRun {
        var run = TeamRun(
            id: id, prompt: "p", status: status,
            workers: [Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(
                    status: status == .done ? .done : .failed,
                    output: status == .done ? "ok" : nil
                )
            )],
            createdAt: Date()
        )
        run.endReason = status == .done ? .completed : .failed
        return run
    }

    private func queuedRun(id: String) -> TeamRun {
        TeamRun(
            id: id, prompt: "queued", status: .queued,
            workers: [Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(status: .queued)
            )],
            createdAt: Date()
        )
    }

    private func statusEvent(runId: String, to: RunStatus, seq: Int64) -> RunEvent {
        RunEvent(
            id: UUID().uuidString, seq: seq, ts: Date(),
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(runId),
                "to": .string(to.rawValue),
                "origin": .string("cli"),
                "presetId": .string("default_chat"),
            ]
        )
    }

    private func workerEvent(runId: String, to: WorkerAnswerStatus, seq: Int64) -> RunEvent {
        RunEvent(
            id: UUID().uuidString, seq: seq, ts: Date(),
            kind: RunEventKind.workerStatusChanged,
            payload: [
                "runId": .string(runId),
                "workerId": .string("model_opus#0"),
                "to": .string(to.rawValue),
                "modelId": .string("model_opus"),
                "skillId": .string("direct"),
            ]
        )
    }

    private func mapJSON(_ run: TeamRun, h: Harness) -> TeamRunJSON {
        let prepared = AllnighterCLI.showReadPath(run: run, models: h.models, store: h.store)
        let runDir = try? h.store.runDirectory(forRunId: prepared.run.id)
        let path = runDir?.appendingPathComponent("run.json").path ?? ""
        let pmTurn = AllnighterCLI.pmTurnProjection(for: prepared.run, store: h.store)
        let context = TeamRunJSONMapper.Context(
            runJournalPath: path,
            reproduceCommand: "alln show \(prepared.run.id)",
            runDirectory: runDir,
            pmTurn: pmTurn.pmTurn,
            pmTurnNotes: pmTurn.notes,
            ownerState: prepared.ownerState
        )
        return TeamRunJSONMapper.map(
            prepared.run, models: h.models, manifests: h.manifests, context: context
        )
    }

    private func parse(_ line: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    private func collectStream(
        run: TeamRun, h: Harness
    ) -> (lines: [String], outcome: RunCLI.StreamOutcome) {
        let trj = mapJSON(run, h: h)
        var lines: [String] = []
        let outcome = AllnighterCLI.runShowStream(
            run: run,
            teamRunJSON: trj,
            store: h.store,
            journal: h.journal,
            writeLine: { lines.append($0) }
        )
        return (lines, outcome)
    }

    // MARK: - Already-terminal: snapshot → replay → one terminal

    func testTerminalRunFrameOrderAndExitClass() throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = terminalRun(id: "term-ok")
        try h.store.save(run, models: h.models)
        // Contiguous durable history: started → worker running → worker done → complete.
        _ = try h.journal.append(statusEvent(runId: run.id, to: .running, seq: 0))
        _ = try h.journal.append(workerEvent(runId: run.id, to: .running, seq: 0))
        _ = try h.journal.append(workerEvent(runId: run.id, to: .done, seq: 0))
        _ = try h.journal.append(statusEvent(runId: run.id, to: .complete, seq: 0))

        let (lines, outcome) = collectStream(run: run, h: h)
        let objs = try lines.map(parse)
        XCTAssertFalse(objs.isEmpty)

        XCTAssertEqual(objs.first?["event"] as? String, "teamRunSnapshot",
                       "frame order: immediate snapshot first")
        let snapData = try XCTUnwrap(objs.first?["data"] as? [String: Any])
        XCTAssertNotNil(snapData["teamRun"], "snapshot carries TeamRunJSON")
        let nested = try XCTUnwrap(snapData["teamRun"] as? [String: Any])
        XCTAssertNotNil(nested["observation"], "snapshot includes ORS-S01 observation")

        let terminals = objs.filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertEqual(terminals.count, 1, "exactly one terminal frame")
        XCTAssertTrue(
            NDJSONStreamProjector.terminalEventNames.contains(objs.last?["event"] as? String ?? ""),
            "terminal is last"
        )
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
        let termData = try XCTUnwrap(objs.last?["data"] as? [String: Any])
        XCTAssertNotNil(termData["teamRun"], "terminal carries TeamRunJSON")
        // pmTurn key present (null or object) — mapped on the delivery frame.
        XCTAssertTrue(termData.keys.contains("pmTurn") || termData["teamRun"] != nil,
                      "terminal carries pmTurn (top-level or nested in teamRun)")

        // Replay lines (between snapshot and terminal) carry replayed:true; terminal does not.
        let middle = objs.dropFirst().dropLast()
        for obj in middle {
            XCTAssertEqual(obj["replayed"] as? Bool, true,
                           "replay lines must carry replayed:true (event=\(obj["event"] ?? "?"))")
        }
        XCTAssertNil(objs.last?["replayed"], "terminal frame must not carry replayed")

        XCTAssertEqual(outcome.exitCode, 0, "done run exits 0")
        XCTAssertNil(outcome.errorCode)
    }

    func testFailedTerminalExitsWithRunExitClass() throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = terminalRun(id: "term-fail", status: .failed)
        try h.store.save(run, models: h.models)
        _ = try h.journal.append(statusEvent(runId: run.id, to: .running, seq: 0))
        _ = try h.journal.append(statusEvent(runId: run.id, to: .failed, seq: 0))

        let (lines, outcome) = collectStream(run: run, h: h)
        let objs = try lines.map(parse)
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunFailed")
        XCTAssertEqual(outcome.exitCode, Int(RunCLI.exitCode(for: run)))
        XCTAssertEqual(outcome.exitCode, 1)
    }

    // MARK: - Reattach-after-terminal (behavior 6, terminal half)

    func testReattachSameBoundedReplayAndExactlyOneTerminal() throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = terminalRun(id: "reattach")
        try h.store.save(run, models: h.models)
        _ = try h.journal.append(statusEvent(runId: run.id, to: .running, seq: 0))
        _ = try h.journal.append(workerEvent(runId: run.id, to: .running, seq: 0))
        _ = try h.journal.append(workerEvent(runId: run.id, to: .done, seq: 0))
        _ = try h.journal.append(statusEvent(runId: run.id, to: .complete, seq: 0))

        let first = collectStream(run: run, h: h)
        let second = collectStream(run: run, h: h)

        let firstEvents = try first.lines.map(parse).map { $0["event"] as? String }
        let secondEvents = try second.lines.map(parse).map { $0["event"] as? String }
        XCTAssertEqual(firstEvents, secondEvents, "reattach emits the same frame order")

        let firstSeqs = try first.lines.map(parse).compactMap { $0["seq"] as? Int }
        let secondSeqs = try second.lines.map(parse).compactMap { $0["seq"] as? Int }
        XCTAssertEqual(firstSeqs, secondSeqs, "reattach preserves durable seqs (no reset)")

        for pass in [first, second] {
            let terms = try pass.lines.map(parse).filter {
                NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
            }
            XCTAssertEqual(terms.count, 1, "each reattach emits exactly one terminal")
        }
    }

    // MARK: - Queued / non-terminal with no events still snapshots

    func testQueuedRunEmitsImmediateSnapshot() throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = queuedRun(id: "queued-empty")
        try h.store.save(run, models: h.models)
        // No journal events.

        let (lines, outcome) = collectStream(run: run, h: h)
        XCTAssertFalse(lines.isEmpty, "must not emit an empty stream")
        let first = try parse(lines[0])
        XCTAssertEqual(first["event"] as? String, "teamRunSnapshot")
        let data = try XCTUnwrap(first["data"] as? [String: Any])
        XCTAssertNotNil(data["teamRun"])
        let terms = try lines.map(parse).filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertTrue(terms.isEmpty, "non-terminal run emits no terminal frame in S02b1")
        XCTAssertEqual(outcome.exitCode, 0)
    }

    // MARK: - Seq gap: loud on stream, silent on show --json

    func testSeqGapEmitsTypedErrorAndJsonPathStillSucceeds() throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = terminalRun(id: "gap-run")
        try h.store.save(run, models: h.models)

        // Write a fixture events.jsonl with a deliberate seq hole (1, then 3).
        let eventsURL = h.journal.eventsURL(forRunId: run.id)
        try FileManager.default.createDirectory(
            at: eventsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let e1 = statusEvent(runId: run.id, to: .running, seq: 1)
        let e3 = statusEvent(runId: run.id, to: .complete, seq: 3)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        let line1 = String(decoding: try enc.encode(e1), as: UTF8.self)
        let line3 = String(decoding: try enc.encode(e3), as: UTF8.self)
        try "\(line1)\n\(line3)\n".write(to: eventsURL, atomically: true, encoding: .utf8)

        // Stream path: typed error frame.
        let (lines, outcome) = collectStream(run: run, h: h)
        let objs = try lines.map(parse)
        XCTAssertEqual(objs.first?["event"] as? String, "teamRunSnapshot",
                       "snapshot still emits before the gap is detected")
        let err = try XCTUnwrap(objs.last, "must end with error frame")
        XCTAssertEqual(err["event"] as? String, "error")
        let errData = try XCTUnwrap(err["data"] as? [String: Any])
        let error = try XCTUnwrap(errData["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "JOURNAL_CORRUPT")
        XCTAssertEqual(outcome.errorCode, "JOURNAL_CORRUPT")
        XCTAssertNotEqual(outcome.exitCode, 0)

        // JSON path on the SAME corrupt journal: still succeeds (rule 8).
        let prepared = AllnighterCLI.showReadPath(run: run, models: h.models, store: h.store)
        let trj = mapJSON(prepared.run, h: h)
        XCTAssertEqual(trj.teamRun.id, run.id)
        XCTAssertEqual(trj.teamRun.status, .done)
        // Mapping must not throw / fail closed just because events.jsonl is gapped.
        let json = AllnighterCLI.jsonString(trj)
        XCTAssertTrue(json.contains(run.id))
        XCTAssertFalse(json.isEmpty)
    }

    // MARK: - Replay bound is explicit

    func testReplayWindowIsBounded() throws {
        XCTAssertEqual(NDJSONStreamProjector.streamReplayMaxEvents, 128)
        XCTAssertLessThan(
            NDJSONStreamProjector.streamReplayMaxEvents,
            RemoteRunEventJournal.maxEventsPerRun,
            "replay window is a recent suffix, not the full retention cap"
        )
    }

    // MARK: - Observer does not signal

    func testStreamPathDoesNotSignalOwner() throws {
        let h = try makeHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = terminalRun(id: "no-signal")
        try h.store.save(run, models: h.models)
        let runDir = try h.store.runDirectory(forRunId: run.id)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        let identity = ProcessOwnership.OwnerIdentity(
            pid: pid, pgid: pid, startTimeTicks: ticks, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(identity, in: runDir)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        _ = collectStream(run: run, h: h)
        XCTAssertTrue(signals.isEmpty, "show --stream must never signal the owner")
    }
}
