import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// F-S00 Works Test (WT-FLOOR02 + worker visibility): the Floor projects over a
/// persisted TeamRun — one worker lane per worker (including failures), the run's
/// family/mutating are surfaced, a failed worker stays visible, and the
/// projection round-trips through CoreJSON.
final class FloorProjectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func signalRun(status: RunStatus = .complete) -> TeamRun {
        let workers = [
            Agent(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
                   skillId: "signal_source_reader", skillName: "Source Reader", purpose: .answer),
            Agent(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
                   skillId: "signal_skeptic", skillName: "Signal Skeptic", purpose: .review),
            Agent(id: "model_opus#1", modelId: "model_opus", instanceIndex: 1,
                   skillId: "insight_writer", skillName: "Insight Writer", purpose: .plan)
        ]
        let answers = [
            TeamAnswer(memberId: "model_grok#0", modelId: "model_grok", role: "answer",
                      result: WorkerRunResult(status: .done, output: String(repeating: "x", count: 400),
                                              timing: RunTiming(startedAt: now, finishedAt: now, durationMs: 1200))),
            TeamAnswer(memberId: "model_opus#0", modelId: "model_opus", role: "review",
                      result: WorkerRunResult(status: .failed, errorReason: "auth expired",
                                              timing: RunTiming(startedAt: now, finishedAt: now))),
            TeamAnswer(memberId: "model_opus#1", modelId: "model_opus", role: "plan",
                      result: WorkerRunResult(status: .done, output: "synthesized",
                                              timing: RunTiming(startedAt: now, finishedAt: now)))
        ]
        let plan = StageOutput(id: "stage_plan", purpose: .plan, status: .done,
                               payload: .plan(markdown: "# Insight\nNo move today."))
        return TeamRun(
            id: "run_floor1", prompt: "interpret this post", status: status, origin: .cli,
            originAgent: "claude-code", presetId: "signal_outside",
            workers: workers, workerAnswers: answers, stages: [plan], createdAt: now,
            lane: .signal, effort: .med, teamDisplayName: "Outside Signal",
            outputKind: .insight, mutating: false, warnings: ["one-model self-fusion"])
    }

    func testWorkerLaneCountEqualsWorkerCount() {
        let floor = FloorProjector.project(signalRun())
        XCTAssertEqual(floor.workerLanes.count, 3)
        XCTAssertEqual(Set(floor.workerLanes.map(\.workerId)),
                       ["model_grok#0", "model_opus#0", "model_opus#1"])
    }

    func testRunCarriesFamilyPostureMutating() {
        let floor = FloorProjector.project(signalRun(), reproduceCommand: "alln run ...")
        XCTAssertEqual(floor.run.family, "signal")
        XCTAssertFalse(floor.run.mutating)
        XCTAssertEqual(floor.run.status, .done)
        XCTAssertEqual(floor.run.reproduceCommand, "alln run ...")
        XCTAssertEqual(floor.team.outputKind, "insight")
        XCTAssertEqual(floor.team.leadWorkerId, "model_opus#1")   // the .plan worker is the lead
        XCTAssertEqual(floor.team.modelCount, 2)                   // grok + opus
    }

    func testFailedWorkerStaysVisible() {
        let floor = FloorProjector.project(signalRun())
        let failedLane = floor.workerLanes.first { $0.workerId == "model_opus#0" }
        XCTAssertEqual(failedLane?.status, "failed")
        XCTAssertEqual(failedLane?.error, "auth expired")
        // And it surfaces as a sourced error envelope.
        XCTAssertTrue(floor.errors.contains { $0.code == "AGENT_FAILED" && $0.workerId == "model_opus#0" })
    }

    func testReturnIsTypedInsightWithSummary() {
        let floor = FloorProjector.project(signalRun())
        XCTAssertEqual(floor.floorReturn?.kind, .insight)
        XCTAssertEqual(floor.floorReturn?.producedByAgentId, "model_opus#1")
        XCTAssertEqual(floor.floorReturn?.summaryMarkdown, "# Insight\nNo move today.")
        // The done worker's lane carries a scan excerpt (truncated), not the full answer.
        let reader = floor.workerLanes.first { $0.workerId == "model_grok#0" }
        XCTAssertEqual(reader?.summary?.hasSuffix("…"), true)
    }

    func testRoundTripsThroughCoreJSON() throws {
        let floor = FloorProjector.project(signalRun(), runJournalPath: "/runs/run_floor1/run.json")
        let data = try CoreJSON.encode(floor)
        let back = try CoreJSON.decode(FloorRun.self, from: data)
        XCTAssertEqual(back, floor)
    }

    func testActiveRunProjectsAsRunning() {
        let floor = FloorProjector.project(signalRun(status: .planning))
        XCTAssertEqual(floor.run.status, .running)
    }

    func testSignalRunHasRoutingActionsOnly() {
        let floor = FloorProjector.project(signalRun())
        let kinds = Set(floor.nextActions.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.copyReturn, .savePending, .sendTeam, .draftCopy,
                                            .createCodeProposal, .createDesignBrief, .monitorExternally,
                                            .ignore, .showRun, .showHistory]))
        XCTAssertTrue(floor.nextActions.allSatisfy { !$0.mutating })
    }

    func testMutatingRunDoesNotProjectSecondGate() {
        var run = signalRun()
        run.mutating = true
        let floor = FloorProjector.project(run)
        XCTAssertEqual(floor.run.mutating, true)
    }

    func testTimelineIsDerivedAndSorted() {
        let floor = FloorProjector.project(signalRun())
        let kinds = floor.timeline.map(\.kind)
        XCTAssertEqual(floor.timeline.first?.kind, .runQueued)
        XCTAssertTrue(kinds.contains(.runStarted))
        XCTAssertTrue(kinds.contains(.workerReturned))
        XCTAssertTrue(kinds.contains(.workerFailed))   // model_opus#0 failed
        XCTAssertTrue(kinds.contains(.runFinished))
        // The plan stage in the fixture has no timestamps → no synthesis events.
        XCTAssertFalse(kinds.contains(.synthesisStarted))
        // Sorted chronologically.
        XCTAssertEqual(floor.timeline, floor.timeline.sorted { $0.at < $1.at })
    }

    func testTimelineNeverInventsMissingTimestamps() {
        // WT-FLOOR04: a worker with a start but no finish yields workerStarted only.
        var run = signalRun(status: .planning)
        run.workerAnswers = [TeamAnswer(memberId: "w#0", modelId: "m", role: "answer",
                                        result: WorkerRunResult(status: .running, timing: RunTiming(startedAt: now)))]
        run.workers = [Agent(id: "w#0", modelId: "m", instanceIndex: 0, purpose: .answer)]
        run.stages = []
        let floor = FloorProjector.project(run)
        let kinds = floor.timeline.map(\.kind)
        XCTAssertTrue(kinds.contains(.workerStarted))
        XCTAssertFalse(kinds.contains(.workerReturned))
        XCTAssertFalse(kinds.contains(.runFinished))   // not terminal
    }

    func testReturnLinksToItsStageArtifact() {
        // F-S02: the typed return points at the output stage and its artifact ref.
        let floor = FloorProjector.project(signalRun())
        XCTAssertEqual(floor.floorReturn?.stageId, "stage_plan")
        XCTAssertEqual(floor.floorReturn?.artifactRefs.contains {
            $0.kind == .stageOutput && $0.relativePath == "stages/stage_plan.plan.md"
        }, true)
        XCTAssertTrue(floor.artifacts.contains { $0.kind == .stageOutput && $0.stageId == "stage_plan" })
    }
}
