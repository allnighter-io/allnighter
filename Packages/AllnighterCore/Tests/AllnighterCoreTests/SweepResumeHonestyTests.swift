import XCTest
@testable import AllnighterCore
import AgentOSTeam

/// OCL-S08 Works Test D: N targets, kill mid-sweep, resume; every target ends
/// `done | failed | not-attempted`, never skipped-and-reported-done.
final class SweepResumeHonestyTests: XCTestCase {
    func testWorksTestDKillThenResumeDoesNotRedoOrSkip() async throws {
        let store = MemorySweepStore()
        let engine = SweepEngine(store: store, now: { Date(timeIntervalSince1970: 1) })
        let targets = (0..<5).map { "t\($0)" }
        let created = try engine.create(
            order: "does this file still agree with Product_Vocabulary.md?",
            targetIds: targets,
            projectRoot: "/tmp/sweep-root",
            sweepId: "sweep_d"
        )
        XCTAssertEqual(created.targets.map(\.outcome), Array(repeating: SweepTargetOutcome.notAttempted, count: 5))
        XCTAssertFalse(SweepHonesty.canReportComplete(created))
        XCTAssertEqual(SweepJSON.project(created).complete, false)

        let executor = KillAfterExecutor(succeedUntil: 2)
        let interrupted = try await engine.advance(id: "sweep_d", executor: executor)
        XCTAssertEqual(interrupted.status, .interrupted)
        XCTAssertEqual(interrupted.targets.map(\.outcome), [
            .done, .done, .notAttempted, .notAttempted, .notAttempted,
        ])
        XCTAssertEqual(executor.attempted, ["t0", "t1"])
        XCTAssertFalse(SweepHonesty.canReportComplete(interrupted))
        XCTAssertEqual(SweepJSON.project(interrupted).complete, false)
        XCTAssertEqual(SweepJSON.project(interrupted).status, "interrupted")
        XCTAssertNotNil(interrupted.artifactPath)
        XCTAssertTrue(SweepArtifact.markdown(SweepArtifact.project(interrupted)).contains("not-attempted"))

        executor.succeedUntil = 99
        let resumed = try await engine.advance(id: "sweep_d", executor: executor)
        XCTAssertEqual(resumed.status, .complete)
        XCTAssertTrue(SweepHonesty.canReportComplete(resumed))
        XCTAssertEqual(resumed.targets.map(\.outcome), Array(repeating: SweepTargetOutcome.done, count: 5))
        XCTAssertEqual(executor.attempted, ["t0", "t1", "t2", "t3", "t4"])
        XCTAssertEqual(SweepJSON.project(resumed).complete, true)
        XCTAssertNil(SweepJSON.project(resumed).nextAction)
        for target in resumed.targets {
            XCTAssertTrue(
                SweepTargetOutcome.allCases.contains(target.outcome)
            )
            XCTAssertNotEqual(target.outcome.rawValue, "skipped")
        }
    }

    func testFailedTargetIsNotRedoneAndUnattemptedNeverReadsDone() async throws {
        let store = MemorySweepStore()
        let engine = SweepEngine(store: store)
        _ = try engine.create(
            order: "flag tautological tests",
            targetIds: ["a", "b", "c"],
            projectRoot: "/tmp/root",
            sweepId: "sweep_fail"
        )
        let executor = KillAfterExecutor(succeedUntil: 2, fail: ["b"])
        let interrupted = try await engine.advance(id: "sweep_fail", executor: executor)
        XCTAssertEqual(interrupted.targets.map(\.outcome), [.done, .failed, .notAttempted])

        executor.succeedUntil = 99
        let resumed = try await engine.advance(id: "sweep_fail", executor: executor)
        XCTAssertEqual(resumed.targets.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(resumed.targets.map(\.outcome), [.done, .failed, .done])
        XCTAssertEqual(executor.attempted, ["a", "b", "c"])
        XCTAssertTrue(SweepHonesty.canReportComplete(resumed))
    }

    func testHonestyRefusesCompleteWhileTargetsRemain() throws {
        let state = SweepState(
            id: "s",
            order: "o",
            projectRoot: "/tmp",
            targets: [
                SweepTargetRecord(id: "a", outcome: .done),
                SweepTargetRecord(id: "b", outcome: .notAttempted),
            ],
            status: .complete,
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertFalse(SweepHonesty.canReportComplete(state))
        XCTAssertThrowsError(try SweepHonesty.requireComplete(state)) { error in
            XCTAssertEqual((error as? SweepError)?.errorCode, "SWEEP_INCOMPLETE")
        }
        XCTAssertEqual(SweepJSON.project(state).complete, false)
    }

    func testReconcileKillLeavesInFlightNotAttempted() throws {
        let store = MemorySweepStore()
        let engine = SweepEngine(store: store)
        var state = try engine.create(
            order: "o",
            targetIds: ["a", "b", "c"],
            projectRoot: "/tmp",
            sweepId: "kill"
        )
        state.targets[0].outcome = .done
        try store.save(state)
        let reconciled = try engine.reconcileKill(state)
        XCTAssertEqual(reconciled.status, .interrupted)
        XCTAssertEqual(reconciled.targets.map(\.outcome), [.done, .notAttempted, .notAttempted])
        XCTAssertFalse(SweepHonesty.canReportComplete(reconciled))
    }

    func testDuplicateAndEmptyTargetListsFailClosed() {
        XCTAssertThrowsError(try SweepTargetList.parse(repeated: [])) { error in
            XCTAssertEqual((error as? SweepError)?.errorCode, "SWEEP_NO_TARGETS")
        }
        XCTAssertThrowsError(try SweepTargetList.parse(repeated: ["a", "a"])) { error in
            XCTAssertEqual((error as? SweepError)?.errorCode, "SWEEP_DUPLICATE_TARGETS")
        }
        XCTAssertEqual(
            try SweepTargetList.parse(csv: "x, y", fileLines: ["# comment", "z", ""]),
            ["x", "y", "z"]
        )
    }

    func testRunOutcomeNeverMapsSkipOrInterruptToDone() {
        let skipped = TeamRun(
            id: "r1",
            prompt: "p",
            status: .complete,
            workers: [Agent(id: "w#0", modelId: "m", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "w#0",
                modelId: "m",
                role: "answer",
                result: WorkerRunResult(status: .skipped, output: "claimed done")
            )],
            createdAt: Date()
        )
        XCTAssertEqual(
            SweepRunOutcome.map(skipped),
            .failed(runId: "r1", reason: "no worker attempted the target")
        )

        let interrupted = TeamRun(
            id: "r2",
            prompt: "p",
            status: .interrupted,
            createdAt: Date()
        )
        XCTAssertEqual(SweepRunOutcome.map(interrupted), .notFinished(runId: "r2"))

        let running = TeamRun(
            id: "r3",
            prompt: "p",
            status: .running,
            createdAt: Date()
        )
        XCTAssertEqual(SweepRunOutcome.map(running), .notFinished(runId: "r3"))

        let done = TeamRun(
            id: "r4",
            prompt: "p",
            status: .done,
            workers: [Agent(id: "w#0", modelId: "m", instanceIndex: 0)],
            answers: [TeamAnswer(
                memberId: "w#0",
                modelId: "m",
                role: "answer",
                result: WorkerRunResult(status: .done, output: "ok")
            )],
            createdAt: Date()
        )
        XCTAssertEqual(SweepRunOutcome.map(done), .done(runId: "r4"))
    }
}

private final class MemorySweepStore: SweepPersisting, @unchecked Sendable {
    private var lock = NSLock()
    private var states: [String: SweepState] = [:]
    private var artifacts: [String: String] = [:]

    func save(_ state: SweepState) throws {
        lock.lock(); defer { lock.unlock() }
        states[state.id] = state
    }

    func load(id: String) throws -> SweepState? {
        lock.lock(); defer { lock.unlock() }
        return states[id]
    }

    func writeArtifact(_ state: SweepState, json: Data, markdown: String) throws -> String {
        let path = "/memory/sweeps/\(state.id)/artifact.json"
        lock.lock(); defer { lock.unlock() }
        artifacts[state.id] = String(decoding: json, as: UTF8.self) + markdown
        return path
    }
}

private final class KillAfterExecutor: SweepTargetExecuting, @unchecked Sendable {
    var attempted: [String] = []
    var succeedUntil: Int
    var fail: Set<String>

    init(succeedUntil: Int, fail: Set<String> = []) {
        self.succeedUntil = succeedUntil
        self.fail = fail
    }

    func attempt(order: String, targetId: String) async throws -> SweepAttempt {
        if attempted.count >= succeedUntil {
            throw SweepInterrupt()
        }
        attempted.append(targetId)
        if fail.contains(targetId) {
            return .failed(runId: "run-\(targetId)", reason: "injected fail")
        }
        return .done(runId: "run-\(targetId)")
    }
}
