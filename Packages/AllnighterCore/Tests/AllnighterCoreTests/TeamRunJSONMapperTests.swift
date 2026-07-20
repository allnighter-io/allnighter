import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// Proves the internal `TeamRun` → public `TeamRunJSON` projection (CLI M1 step 5
/// breaking re-cut). Fixture-only; no live runs.
final class TeamRunJSONMapperTests: XCTestCase {
    private func ctx() -> TeamRunJSONMapper.Context { .init(runJournalPath: "/tmp/run.json") }
    private func bench() throws -> [Model] { try Fixtures.models() }

    func testWorkerPromptSnapshotsOmittedByDefaultIncludedWhenFull() throws {
        var run = try Fixtures.run(.runComplete)
        run.workers[0].resolvedWorkerPromptSnapshot = "SNAPSHOT_MARKER"
        let defaultMap = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertNil(defaultMap.workers.first?.resolvedWorkerPromptSnapshot)
        let fullCtx = TeamRunJSONMapper.Context(runJournalPath: "/tmp/run.json", includeWorkerPromptSnapshots: true)
        let fullMap = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: fullCtx)
        XCTAssertEqual(fullMap.workers.first?.resolvedWorkerPromptSnapshot, "SNAPSHOT_MARKER")
    }

    func testCompleteRunMapsToDoneWithPlan() throws {
        let run = try Fixtures.run(.runComplete)            // internal status .complete
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())

        XCTAssertEqual(trj.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(trj.teamRun.status, .done)           // .complete -> done
        XCTAssertEqual(trj.workers.count, run.workers.count)
        XCTAssertEqual(trj.workerAnswers.count, run.workerAnswers.count)
        // Plan produced → plan-writer invariant holds.
        XCTAssertEqual(trj.plan?.status, .done)
        XCTAssertNotNil(trj.plan?.writerWorkerId)
        XCTAssertEqual(trj.plan?.writerWorkerId, trj.teamRun.planWriterWorkerId)
        XCTAssertGreaterThan(trj.usage.cliCalls, 0)
        XCTAssertEqual(trj.nextActions.map(\.kind), [.showRun, .export])
        // The projection is a valid TeamRunJSON (round-trips).
        let data = try CoreJSON.encode(trj)
        XCTAssertEqual(try CoreJSON.decode(TeamRunJSON.self, from: data), trj)
    }

    func testPartialRunIsDoneWithNoPlanButFailuresCarryErrors() throws {
        let run = try Fixtures.run(.runPartial)             // status .partial, plan failed
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())

        XCTAssertEqual(trj.teamRun.status, .done)           // partial -> done
        XCTAssertNil(trj.plan)                              // no plan produced -> null
        XCTAssertNil(trj.teamRun.planWriterWorkerId)
        // Failed workers are shown failed with an error envelope — never hidden.
        let failed = trj.workerAnswers.filter { $0.status == .failed || $0.status == .timedOut }
        XCTAssertFalse(failed.isEmpty)
        XCTAssertTrue(failed.allSatisfy { $0.error != nil })
        // The plan failure is still visible as a stage.
        XCTAssertTrue(trj.stages.contains { $0.purpose == .plan && $0.status == .failed })
    }

    func testInflightRunMapsToRunning() throws {
        let run = try Fixtures.run(.runInflight)            // status .fanningOut
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertEqual(trj.teamRun.status, .running)
    }

    func testVendorBackoffAndAttemptsProjectOntoPublicContract() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let reset = now.addingTimeInterval(600)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .messageFallback,
            rawSnippet: "session limit",
            observedAt: now,
            observedResetAt: reset,
            retryAfterSeconds: 600,
            wakeAfter: reset
        )
        var run = TeamRun(
            id: "parked",
            prompt: "p",
            status: .queued,
            phase: .waitingForVendor,
            createdAt: now,
            blocker: RunBlocker(
                resource: .vendorBackoff,
                quotaScope: "claude_code/default",
                wakeAfter: reset,
                capacityObservation: observation
            ),
            attempts: [
                RunAttempt(
                    attemptNumber: 1,
                    requestedSourceId: "claude_code",
                    resolvedSourceId: "claude_code",
                    startedAt: now,
                    endedAt: now,
                    capacityObservation: observation,
                    terminalStatus: .failed,
                    reason: "capacity"
                ),
            ]
        )
        run.workers = []

        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: ctx())
        XCTAssertEqual(trj.teamRun.blocker?.resource, "vendorBackoff")
        XCTAssertNil(trj.teamRun.blocker?.scopeRoot)
        XCTAssertEqual(trj.teamRun.blocker?.quotaScope, "claude_code/default")
        XCTAssertEqual(trj.teamRun.blocker?.capacityObservation?.kind, "accountRateLimit")
        XCTAssertEqual(trj.teamRun.attempts.first?.attemptNumber, 1)
        XCTAssertEqual(trj.teamRun.attempts.first?.terminalStatus, .failed)
    }

    func testLegacyPublicRunInfoWithoutAttemptsDecodesEmpty() throws {
        let trj = TeamRunJSONMapper.map(
            try Fixtures.run(.runInflight),
            models: try bench(),
            manifests: [],
            context: ctx()
        )
        let encoded = try CoreJSON.encode(trj)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var run = try XCTUnwrap(root["teamRun"] as? [String: Any])
        run.removeValue(forKey: "attempts")
        root["teamRun"] = run
        let legacy = try JSONSerialization.data(withJSONObject: root)

        XCTAssertEqual(
            try CoreJSON.decode(TeamRunJSON.self, from: legacy).teamRun.attempts,
            []
        )
    }

    func testRunStatusMappingIsClosed() {
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.complete), .done)
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.partial), .done)
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.draft), .queued)
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.fanningOut), .running)
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.planning), .running)
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.failed), .failed)
        XCTAssertEqual(TeamRunJSONMapper.mapRun(.cancelled), .cancelled)
        XCTAssertEqual(TeamRunJSONMapper.mapOrigin(.http), .localApi)
        XCTAssertEqual(TeamRunJSONMapper.mapOrigin(.ios), .ios)
    }

    // MARK: - FR5 outcome (mechanical, never a correctness verdict)

    private func terminalRun(
        status: RunStatus, answers: [TeamAnswer], mutating: Bool = true,
        repoDelta: RepoDelta? = nil, lane: WorkLane = .code
    ) -> TeamRun {
        TeamRun(
            id: "outcome-\(status.rawValue)", prompt: "p", status: status,
            workers: [Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0)],
            workerAnswers: answers,
            createdAt: Date(), lane: lane, mutating: mutating, repoDelta: repoDelta)
    }

    func testOutcomeCompletedWhenAllWorkersDone() throws {
        let delta = RepoDelta(
            changed: true, baseline: "aaa", head: "2c07ad43", commits: [], filesChanged: 11, files: [])
        let run = terminalRun(
            status: .complete,
            answers: [TeamAnswer(
                memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                result: WorkerRunResult(status: .done, output: "Done."))],
            repoDelta: delta)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        let outcome = try XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.status, TeamRunJSON.Outcome.Status.completed)
        XCTAssertTrue(outcome.committed)
        XCTAssertEqual(
            outcome.headline,
            "worker model_grok · lane code · mutating · committed 2c07ad4: 11 files")
    }

    func testOutcomePartialWhenSomeWorkersDone() throws {
        let run = try Fixtures.run(.runPartial)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        let outcome = try XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.status, TeamRunJSON.Outcome.Status.partial)
        XCTAssertFalse(outcome.committed)
        XCTAssertTrue(outcome.headline.contains("worker"))
    }

    func testOutcomeFailedWhenNoWorkersDone() throws {
        let run = terminalRun(
            status: .failed,
            answers: [
                TeamAnswer(memberId: "model_grok#0", modelId: "model_grok", role: "answer", result: WorkerRunResult(status: .failed)),
                TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "answer", result: WorkerRunResult(status: .failed)),
            ],
            mutating: false)
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: ctx())
        let outcome = try XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.status, TeamRunJSON.Outcome.Status.failed)
        XCTAssertFalse(outcome.committed)
    }

    func testOutcomeTimedOutWhenNoWorkersDoneAndAtLeastOneTimedOut() throws {
        let run = terminalRun(
            status: .failed,
            answers: [TeamAnswer(
                memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                result: WorkerRunResult(status: .timedOut))])
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: ctx())
        let outcome = try XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.status, TeamRunJSON.Outcome.Status.timedOut)
        XCTAssertFalse(outcome.committed)
    }

    func testInflightRunOmitsOutcome() throws {
        let run = try Fixtures.run(.runInflight)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertNil(trj.outcome)
    }
}
