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
        XCTAssertNil(defaultMap.agents.first?.resolvedAgentPromptSnapshot)
        let fullCtx = TeamRunJSONMapper.Context(runJournalPath: "/tmp/run.json", includeWorkerPromptSnapshots: true)
        let fullMap = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: fullCtx)
        XCTAssertEqual(fullMap.agents.first?.resolvedAgentPromptSnapshot, "SNAPSHOT_MARKER")
    }

    func testCompleteRunMapsToDoneWithPlan() throws {
        let run = try Fixtures.run(.runComplete)            // internal status .complete
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())

        XCTAssertEqual(trj.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(trj.schemaVersion, 2)
        XCTAssertEqual(trj.teamRun.status, .done)           // .complete -> done
        XCTAssertEqual(trj.agents.count, run.workers.count)
        XCTAssertEqual(trj.answers.count, run.answers.count)
        // Plan produced → plan-writer invariant holds; markdown moved to answer.
        XCTAssertEqual(trj.plan?.status, .done)
        XCTAssertNotNil(trj.plan?.writerAgentId)
        XCTAssertEqual(trj.plan?.writerAgentId, trj.teamRun.planWriterAgentId)
        XCTAssertNil(trj.plan?.markdown)
        let answer = try XCTUnwrap(trj.answer)
        XCTAssertEqual(answer.source.kind, .plan)
        XCTAssertEqual(answer.markdown, run.plan)
        XCTAssertGreaterThan(trj.usage.cliCalls, 0)
        XCTAssertEqual(trj.nextActions.map(\.kind), [.showArtifact, .showRun, .export])
        XCTAssertEqual(trj.nextActions.first?.command, "alln artifact show \(run.id)")
        // Top-level artifact is the agent-primary finish (not buried nextActions).
        let artifact = try XCTUnwrap(trj.artifact)
        XCTAssertEqual(artifact.openCommand, "alln artifact show \(run.id)")
        XCTAssertNil(artifact.path, "path only when CLI materializes HTML")
        // Catalog-free: no top-level models.
        let data = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(root["models"])
        XCTAssertTrue(root.keys.contains("artifact"))
        let artObj = try XCTUnwrap(root["artifact"] as? [String: Any])
        XCTAssertEqual(artObj["openCommand"] as? String, "alln artifact show \(run.id)")
        XCTAssertEqual(try CoreJSON.decode(TeamRunJSON.self, from: data), trj)
    }

    func testArtifactPathSurfacedWhenContextProvidesIt() throws {
        let run = try Fixtures.run(.runComplete)
        let path = "/tmp/runs/\(run.id)/artifact/index.html"
        let ctx = TeamRunJSONMapper.Context(runJournalPath: "/tmp/run.json", artifactPath: path)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx)
        XCTAssertEqual(trj.artifact?.path, path)
        XCTAssertEqual(trj.artifact?.openCommand, "alln artifact show \(run.id)")
    }

    func testNonTerminalRunSerializesArtifactNull() throws {
        var run = try Fixtures.run(.runComplete)
        run.status = .running
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertNil(trj.artifact)
        let data = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(root.keys.contains("artifact"))
        XCTAssertTrue(root["artifact"] is NSNull)
    }

    func testOneWorkerMovesMarkdownToAnswer() throws {
        let run = terminalRun(
            status: .complete,
            answers: [TeamAnswer(
                memberId: "model_sonnet#0", modelId: "model_sonnet", role: "answer",
                result: WorkerRunResult(status: .done, output: "success"))],
            mutating: false)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertEqual(trj.answer?.markdown, "success")
        XCTAssertEqual(trj.answer?.source.kind, .worker)
        XCTAssertNil(trj.answers.first?.markdown)
        XCTAssertNil(trj.plan)
    }

    func testPartialMultiSeatWithoutSynthesisLeavesAnswerNull() throws {
        let run = try Fixtures.run(.runPartial)             // status .partial, plan failed
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertNil(trj.answer)
        XCTAssertTrue(trj.answers.contains { ($0.markdown ?? "").isEmpty == false })
    }

    func testFailedRunSerializesAnswerNull() throws {
        let run = terminalRun(
            status: .failed,
            answers: [TeamAnswer(
                memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                result: WorkerRunResult(status: .failed))],
            mutating: false)
        let trj = TeamRunJSONMapper.map(run, models: [], manifests: [], context: ctx())
        XCTAssertNil(trj.answer)
        let data = try CoreJSON.encode(trj)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(root.keys.contains("answer"))
        XCTAssertTrue(root["answer"] is NSNull)
    }

    func testPartialRunIsDoneWithNoPlanButFailuresCarryErrors() throws {
        let run = try Fixtures.run(.runPartial)             // status .partial, plan failed
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())

        XCTAssertEqual(trj.teamRun.status, .done)           // partial -> done
        XCTAssertNil(trj.plan)                              // no plan produced -> null
        XCTAssertNil(trj.teamRun.planWriterAgentId)
        // Failed workers are shown failed with an error envelope — never hidden.
        let failed = trj.answers.filter { $0.status == .failed || $0.status == .timedOut }
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
            workers: [Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0)],
            answers: answers,
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
            "model model_grok · lane code · mutating · committed 2c07ad4: 11 files")
    }

    func testOutcomePartialWhenSomeWorkersDone() throws {
        let run = try Fixtures.run(.runPartial)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        let outcome = try XCTUnwrap(trj.outcome)
        XCTAssertEqual(outcome.status, TeamRunJSON.Outcome.Status.partial)
        XCTAssertFalse(outcome.committed)
        XCTAssertTrue(outcome.headline.contains("model"))
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

    // MARK: - SH-S08 observed timing

    func testMapperProjectsQueueTtftDurationAndWallMs() throws {
        let created = Date(timeIntervalSince1970: 1_753_000_000)
        let started = created.addingTimeInterval(1)
        let firstToken = started.addingTimeInterval(0.5)
        let finished = started.addingTimeInterval(4)
        let run = TeamRun(
            id: "timing-one", prompt: "Say success.", status: .complete,
            workers: [Agent(id: "model_sonnet#0", modelId: "model_sonnet", instanceIndex: 0)],
            answers: [
                TeamAnswer(
                    memberId: "model_sonnet#0", modelId: "model_sonnet", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "success",
                        timing: RunTiming(
                            startedAt: started, finishedAt: finished, durationMs: 4000,
                            firstTokenAt: firstToken, ttftMs: 500)),
                    queueMs: 1000)
            ],
            createdAt: created, lane: .code, mutating: true)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        let row = try XCTUnwrap(trj.answers.first)
        XCTAssertEqual(row.queueMs, 1000)
        XCTAssertEqual(row.ttftMs, 500)
        XCTAssertEqual(row.durationMs, 4000)
        XCTAssertEqual(trj.outcome?.timing?.wallMs, 5000)
        XCTAssertTrue(trj.outcome?.headline.contains("queue 1000ms") == true)
        XCTAssertTrue(trj.outcome?.headline.contains("ttft 500ms") == true)
        XCTAssertTrue(trj.outcome?.headline.contains("duration 4000ms") == true)
        XCTAssertTrue(trj.outcome?.headline.contains("wall 5000ms") == true)
        XCTAssertFalse(trj.outcome?.headline.lowercased().contains("overhead") == true)
        XCTAssertFalse(trj.outcome?.headline.lowercased().contains("estimate") == true)
    }

    func testNullTimingWhenDriverDidNotReport() throws {
        let run = terminalRun(
            status: .complete,
            answers: [TeamAnswer(
                memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                result: WorkerRunResult(status: .done, output: "x"))],
            mutating: false)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        let row = try XCTUnwrap(trj.answers.first)
        XCTAssertNil(row.queueMs)
        XCTAssertNil(row.ttftMs)
        XCTAssertNil(row.durationMs)
        XCTAssertNil(trj.outcome?.timing?.wallMs)
        XCTAssertFalse(trj.outcome?.headline.contains("queue") == true)
        XCTAssertFalse(trj.outcome?.headline.contains("wall") == true)
    }

    func testParallelRunHeadlineOmitsTimingBlameSplit() throws {
        let created = Date(timeIntervalSince1970: 1_753_000_100)
        let finished = created.addingTimeInterval(3)
        let run = TeamRun(
            id: "timing-multi", prompt: "p", status: .complete,
            workers: [
                Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0),
                Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0),
            ],
            answers: [
                TeamAnswer(
                    memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "a",
                        timing: RunTiming(startedAt: created, finishedAt: finished, durationMs: 3000)),
                    queueMs: 10),
                TeamAnswer(
                    memberId: "model_opus#0", modelId: "model_opus", role: "answer",
                    result: WorkerRunResult(
                        status: .done, output: "b",
                        timing: RunTiming(startedAt: created, finishedAt: finished, durationMs: 2800)),
                    queueMs: 20),
            ],
            createdAt: created, lane: .code, mutating: false)
        let trj = TeamRunJSONMapper.map(run, models: try bench(), manifests: [], context: ctx())
        XCTAssertEqual(trj.answers.map(\.queueMs), [10, 20])
        XCTAssertEqual(trj.outcome?.timing?.wallMs, 3000)
        let headline = try XCTUnwrap(trj.outcome?.headline)
        XCTAssertFalse(headline.contains("queue"), headline)
        XCTAssertFalse(headline.contains("wall"), headline)
        XCTAssertFalse(headline.lowercased().contains("overhead"), headline)
        XCTAssertFalse(headline.lowercased().contains("estimate"), headline)
    }
}
