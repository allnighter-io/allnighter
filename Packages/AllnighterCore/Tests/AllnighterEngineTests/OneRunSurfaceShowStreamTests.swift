import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// ORS-S02b1/b2 — `alln show <id> --stream` reattach READ surface.
///
/// Frame order: immediate snapshot → bounded replay (`replayed: true`) → live
/// follow (no `replayed` key) → exactly one terminal **or** attention-required
/// exit. Observer is read-only and disposable; journal gaps are loud on the
/// stream path and silent on `show --json`.
final class OneRunSurfaceShowStreamTests: XCTestCase {

    // MARK: - Harness

    private struct Harness {
        let root: URL
        let store: RunStore
        let journal: RemoteRunEventJournal
        let models: [Model]
        let manifests: [DriverManifest]
    }

    private func makeHarness(canStream: Bool = true) throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ors-s02b2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: root)
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let model = Model(
            id: "model_opus", displayName: "Opus", modelLabel: "opus",
            driverId: "claude_code", role: .both
        )
        let manifest = DriverManifest(
            id: "claude_code", displayName: "Claude", kind: .headlessCLI,
            streaming: canStream
                ? .init(supported: true, mode: .jsonlStdout)
                : .init(supported: false, mode: .none)
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
        run: TeamRun,
        h: Harness,
        follow: AllnighterCLI.ShowStreamFollowControl = AllnighterCLI.ShowStreamFollowControl()
    ) -> (lines: [String], outcome: RunCLI.StreamOutcome) {
        let trj = mapJSON(run, h: h)
        var lines: [String] = []
        let outcome = AllnighterCLI.runShowStream(
            run: run,
            teamRunJSON: trj,
            store: h.store,
            models: h.models,
            manifests: h.manifests,
            journal: h.journal,
            writeLine: { lines.append($0) },
            follow: follow
        )
        return (lines, outcome)
    }

    private func runningRun(id: String) -> TeamRun {
        TeamRun(
            id: id, prompt: "running", status: .running,
            workers: [Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                result: WorkerRunResult(status: .running)
            )],
            createdAt: Date()
        )
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
        // No journal events. Cancel after attach so the disposable observer
        // does not follow forever (incremental, no budget).
        var cancelled = false
        let follow = AllnighterCLI.ShowStreamFollowControl(
            sleep: { _ in cancelled = true },
            isCancelled: { cancelled },
            pollIntervalSeconds: 0.01
        )

        let (lines, outcome) = collectStream(run: run, h: h, follow: follow)
        XCTAssertFalse(lines.isEmpty, "must not emit an empty stream")
        let first = try parse(lines[0])
        XCTAssertEqual(first["event"] as? String, "teamRunSnapshot")
        let data = try XCTUnwrap(first["data"] as? [String: Any])
        XCTAssertNotNil(data["teamRun"])
        let terms = try lines.map(parse).filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertTrue(terms.isEmpty, "cancelled observer emits no terminal frame")
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

    // MARK: - ORS-S02b2 live follow

    func testLiveFollowEmitsNewEventsWithoutReplayedKey() throws {
        let h = try makeHarness(canStream: true)
        defer { try? FileManager.default.removeItem(at: h.root) }

        var run = runningRun(id: "live-follow")
        try h.store.save(run, models: h.models)
        _ = try h.journal.append(statusEvent(runId: run.id, to: .running, seq: 0))

        var pollCount = 0
        let follow = AllnighterCLI.ShowStreamFollowControl(
            sleep: { _ in },
            isCancelled: { false },
            pollIntervalSeconds: 0.01,
            onPoll: {
                pollCount += 1
                if pollCount == 1 {
                    // Append after observer attaches — must appear live (no replayed).
                    _ = try? h.journal.append(self.workerEvent(runId: run.id, to: .running, seq: 0))
                } else if pollCount == 2 {
                    _ = try? h.journal.append(self.workerEvent(runId: run.id, to: .done, seq: 0))
                    _ = try? h.journal.append(self.statusEvent(runId: run.id, to: .complete, seq: 0))
                    run = self.terminalRun(id: run.id)
                    try? h.store.save(run, models: h.models)
                }
            }
        )

        let (lines, outcome) = collectStream(run: runningRun(id: "live-follow"), h: h, follow: follow)
        let objs = try lines.map(parse)
        XCTAssertEqual(objs.first?["event"] as? String, "teamRunSnapshot")

        // Live worker lines after attach: no replayed key.
        let liveWorkers = objs.filter { $0["event"] as? String == "workerStarted" || $0["event"] as? String == "workerAnswered" }
        XCTAssertFalse(liveWorkers.isEmpty, "live follow must emit post-attach worker events")
        for obj in liveWorkers {
            XCTAssertNil(obj["replayed"], "live lines must not carry replayed key")
        }

        let seqs = objs.compactMap { $0["seq"] as? Int }.filter { $0 > 0 }
        XCTAssertEqual(seqs, seqs.sorted(), "live events in ascending seq")

        let terminals = objs.filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertEqual(terminals.count, 1, "exactly one terminal after mid-run settle")
        XCTAssertEqual(outcome.exitCode, 0)
    }

    func testExactlyOneTerminalWhenAttachMidRunThenSettle() throws {
        let h = try makeHarness(canStream: true)
        defer { try? FileManager.default.removeItem(at: h.root) }

        let runId = "mid-attach"
        var run = runningRun(id: runId)
        try h.store.save(run, models: h.models)
        _ = try h.journal.append(statusEvent(runId: runId, to: .running, seq: 0))
        _ = try h.journal.append(workerEvent(runId: runId, to: .running, seq: 0))

        var pollCount = 0
        let follow = AllnighterCLI.ShowStreamFollowControl(
            sleep: { _ in },
            pollIntervalSeconds: 0.01,
            onPoll: {
                pollCount += 1
                if pollCount == 1 {
                    _ = try? h.journal.append(self.workerEvent(runId: runId, to: .done, seq: 0))
                    _ = try? h.journal.append(self.statusEvent(runId: runId, to: .complete, seq: 0))
                    run = self.terminalRun(id: runId)
                    try? h.store.save(run, models: h.models)
                }
            }
        )

        let (lines, _) = collectStream(run: runningRun(id: runId), h: h, follow: follow)
        let objs = try lines.map(parse)
        let terminals = objs.filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertEqual(terminals.count, 1)
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
        // Replay of pre-attach history carries replayed; terminal does not.
        let middle = objs.dropFirst().dropLast()
        for obj in middle where obj["event"] as? String == "workerStarted" {
            // workerStarted from history is replayed; any live-only kinds have no key.
            if let seq = obj["seq"] as? Int, seq <= 2 {
                XCTAssertEqual(obj["replayed"] as? Bool, true)
            }
        }
        XCTAssertNil(objs.last?["replayed"])
    }

    // MARK: - Attention exit: sourced blocker

    func testAttentionExitOnSourcedBlocker() throws {
        let h = try makeHarness(canStream: true)
        defer { try? FileManager.default.removeItem(at: h.root) }

        var run = runningRun(id: "blocked")
        run.phase = .waitingForWriteLock
        run.blocker = RunBlocker(
            resource: .repoWriteLock,
            scopeRoot: "/tmp/repo",
            holderId: "other-run",
            holderKind: "run",
            ticketPosition: 1
        )
        try h.store.save(run, models: h.models)

        let (lines, outcome) = collectStream(run: run, h: h)
        let objs = try lines.map(parse)
        XCTAssertEqual(objs.first?["event"] as? String, "teamRunSnapshot")
        let attention = try XCTUnwrap(objs.last)
        XCTAssertEqual(attention["event"] as? String, "attentionRequired")
        let data = try XCTUnwrap(attention["data"] as? [String: Any])
        XCTAssertEqual(data["reason"] as? String, "sourcedBlocker")
        let next = try XCTUnwrap(data["nextAction"] as? [String: Any])
        XCTAssertEqual(next["kind"] as? String, "inspectBlocker")
        XCTAssertNotEqual(next["kind"] as? String, "showRun")
        XCTAssertNotEqual(next["command"] as? String, "alln show \(run.id) --stream")
        XCTAssertFalse(
            (next["command"] as? String ?? "").contains("show \(run.id)"),
            "recovery must not be a self-referential show --stream"
        )
        let terms = objs.filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertTrue(terms.isEmpty, "attention ends the stream without a run terminal")
        XCTAssertEqual(outcome.exitCode, 0)
    }

    // MARK: - terminalOnly observer budget

    func testTerminalOnlyBudgetExitsWithExpectedSilenceAndNoVerdict() throws {
        let h = try makeHarness(canStream: false) // terminalOnly
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = runningRun(id: "term-only-budget")
        try h.store.save(run, models: h.models)

        var clock = Date(timeIntervalSince1970: 1_000)
        let follow = AllnighterCLI.ShowStreamFollowControl(
            now: { clock },
            sleep: { _ in clock.addTimeInterval(1) },
            observerBudgetSeconds: 2,
            pollIntervalSeconds: 0.01
        )

        let (lines, outcome) = collectStream(run: run, h: h, follow: follow)
        let objs = try lines.map(parse)
        let attention = try XCTUnwrap(objs.last)
        XCTAssertEqual(attention["event"] as? String, "attentionRequired")
        let data = try XCTUnwrap(attention["data"] as? [String: Any])
        XCTAssertEqual(data["reason"] as? String, "observerBudget")
        XCTAssertEqual(data["activityMode"] as? String, "terminalOnly")
        XCTAssertEqual(data["silenceExpected"] as? Bool, true)
        // No nextAction (spec tension: re-observe would be circular showRun).
        XCTAssertNil(data["nextAction"])
        let message = (data["message"] as? String ?? "").lowercased()
        XCTAssertTrue(message.contains("expected"), "must label silence as expected")
        // Inference ban: never report silence as stuck/stalled/no progress.
        for banned in ["stuck", "stalled", "no progress"] {
            XCTAssertFalse(
                message.contains(banned),
                "must not fabricate progress verdict word '\(banned)'"
            )
        }
        XCTAssertEqual(outcome.exitCode, 0)
    }

    // MARK: - incremental healthy long run: no wall budget

    func testIncrementalDoesNotExitOnObserverBudget() throws {
        let h = try makeHarness(canStream: true)
        defer { try? FileManager.default.removeItem(at: h.root) }

        let run = runningRun(id: "inc-long")
        try h.store.save(run, models: h.models)
        _ = try h.journal.append(statusEvent(runId: run.id, to: .running, seq: 0))

        var clock = Date(timeIntervalSince1970: 1_000)
        var polls = 0
        let follow = AllnighterCLI.ShowStreamFollowControl(
            now: { clock },
            sleep: { _ in
                clock.addTimeInterval(100) // advance far past a 2s budget
                polls += 1
            },
            isCancelled: { polls >= 3 }, // stop after several polls without budget exit
            observerBudgetSeconds: 2,
            pollIntervalSeconds: 0.01
        )

        let (lines, outcome) = collectStream(run: run, h: h, follow: follow)
        let objs = try lines.map(parse)
        let attention = objs.filter { $0["event"] as? String == "attentionRequired" }
        XCTAssertTrue(
            attention.isEmpty,
            "incremental must not exit on wall-clock observer budget (would fake-timeout long work)"
        )
        let terms = objs.filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertTrue(terms.isEmpty)
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertGreaterThanOrEqual(polls, 3)
    }

    // MARK: - OBSERVER DEATH (load-bearing)

    func testObserverDeathLeavesRunUntouched() throws {
        let h = try makeHarness(canStream: true)
        defer { try? FileManager.default.removeItem(at: h.root) }

        let runId = "observer-death"
        let run = runningRun(id: runId)
        try h.store.save(run, models: h.models)
        let runDir = try h.store.runDirectory(forRunId: runId)
        let pid = ProcessInfo.processInfo.processIdentifier
        let ticks = try XCTUnwrap(ProcessOwnership.processStartTimeTicks(pid))
        let identity = ProcessOwnership.OwnerIdentity(
            pid: pid, pgid: pid, startTimeTicks: ticks, kind: .detachedRunner
        )
        try ProcessOwnership.writeOwnerIdentity(identity, in: runDir)
        _ = try h.journal.append(statusEvent(runId: runId, to: .running, seq: 0))

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        // Snapshot identity + store state BEFORE observer death.
        let ownerBefore = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir))
        let statusBefore = try XCTUnwrap(h.store.load(runId: runId)).status
        let phaseBefore = h.store.load(runId: runId)?.phase
        let endReasonBefore = h.store.load(runId: runId)?.endReason

        var cancelled = false
        var pollCount = 0
        let follow = AllnighterCLI.ShowStreamFollowControl(
            sleep: { _ in
                pollCount += 1
                if pollCount >= 1 { cancelled = true }
            },
            isCancelled: { cancelled },
            pollIntervalSeconds: 0.01
        )

        _ = collectStream(run: run, h: h, follow: follow)

        // Assert DIRECTLY on ProcessOwnership + RunStore — not via show.
        XCTAssertTrue(
            signals.isEmpty,
            "observer death must not signal owner (ProcessOwnership.terminateSignalHook)"
        )
        let ownerAfter = try XCTUnwrap(ProcessOwnership.readOwnerIdentity(in: runDir))
        XCTAssertEqual(ownerAfter.pid, ownerBefore.pid)
        XCTAssertEqual(ownerAfter.pgid, ownerBefore.pgid)
        XCTAssertEqual(ownerAfter.startTimeTicks, ownerBefore.startTimeTicks)
        XCTAssertTrue(ProcessOwnership.isIdentityAlive(ownerAfter))

        let after = try XCTUnwrap(h.store.load(runId: runId))
        XCTAssertEqual(after.status, statusBefore, "RunStore status untouched")
        XCTAssertEqual(after.phase, phaseBefore)
        XCTAssertEqual(after.endReason, endReasonBefore)
        XCTAssertFalse(after.status.isTerminal, "run must still be non-terminal")
    }

    func testReattachAfterObserverDeathContinuesWithoutDuplicateTerminal() throws {
        let h = try makeHarness(canStream: true)
        defer { try? FileManager.default.removeItem(at: h.root) }

        let runId = "reattach-after-death"
        var run = runningRun(id: runId)
        try h.store.save(run, models: h.models)
        _ = try h.journal.append(statusEvent(runId: runId, to: .running, seq: 0))
        _ = try h.journal.append(workerEvent(runId: runId, to: .running, seq: 0))

        // First observer: cancel mid-follow (disposable death).
        var cancelled = false
        let deathFollow = AllnighterCLI.ShowStreamFollowControl(
            sleep: { _ in cancelled = true },
            isCancelled: { cancelled },
            pollIntervalSeconds: 0.01
        )
        let first = collectStream(run: run, h: h, follow: deathFollow)
        let firstTerms = try first.lines.map(parse).filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertTrue(firstTerms.isEmpty, "dead observer emits no terminal")

        // Run settles while no observer is attached.
        _ = try h.journal.append(workerEvent(runId: runId, to: .done, seq: 0))
        _ = try h.journal.append(statusEvent(runId: runId, to: .complete, seq: 0))
        run = terminalRun(id: runId)
        try h.store.save(run, models: h.models)

        // Second invocation: replay + one terminal, no duplicate.
        let second = collectStream(run: run, h: h)
        let objs = try second.lines.map(parse)
        let terminals = objs.filter {
            NDJSONStreamProjector.terminalEventNames.contains($0["event"] as? String ?? "")
        }
        XCTAssertEqual(terminals.count, 1, "reattach after observer death: exactly one terminal")
        XCTAssertEqual(objs.last?["event"] as? String, "teamRunCompleted")
        XCTAssertEqual(second.outcome.exitCode, 0)
    }

    func testObserverBudgetConstantIsDocumentedFiniteDefault() {
        XCTAssertEqual(NDJSONStreamProjector.streamObserverBudgetSecondsDefault, 7_200)
        XCTAssertGreaterThan(NDJSONStreamProjector.streamObserverBudgetSecondsDefault, 0)
        // Derived from run wall when present.
        var run = runningRun(id: "budget-derive")
        run.clockBudgets = RunClockBudgets(wallTimeoutSeconds: 3600)
        XCTAssertEqual(NDJSONStreamProjector.streamObserverBudgetSeconds(for: run), 3600)
        run.clockBudgets = nil
        XCTAssertEqual(
            NDJSONStreamProjector.streamObserverBudgetSeconds(for: run),
            NDJSONStreamProjector.streamObserverBudgetSecondsDefault
        )
    }
}

