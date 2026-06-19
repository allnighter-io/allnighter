import XCTest
@testable import AllnighterCore

/// WT-ETS03 dispatch path: project mutating dispatch runs the source gate before
/// dirty-state and per-Project worker readiness.
final class ProjectMutatingDispatchGateTests: XCTestCase {

    private func project() -> Project {
        Project(
            id: "prj_1", displayName: "Demo", localRootPath: "/tmp/demo", normalizedRootPath: "/tmp/demo",
            kind: .gitRepo, createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1))
    }

    private func proposal(teamId: String? = "code_codex_implementation") -> ProjectProposal {
        ProjectProposal(
            id: "prop_1", projectId: "prj_1", threadId: "t", createdFromTurnId: "mgr_1",
            kind: .execute_slice, title: "Ship", whyNow: "now", userGoal: "ship",
            scope: "Sources/Foo.swift", likelyFilesOrAreas: ["Sources/Foo.swift"],
            suggestedLane: .code, suggestedTeamId: teamId,
            createdAt: Date(timeIntervalSince1970: 2), updatedAt: Date(timeIntervalSince1970: 2))
    }

    private func dispatchOrder(
        teamId: String? = "code_codex_implementation",
        targetSourceId: String? = "codex"
    ) -> WorkOrder {
        WorkOrder(
            id: "wo_1", proposalId: "prop_1", projectId: "prj_1", title: "Ship",
            lane: .code, mode: .dispatch,
            targetSourceId: targetSourceId, executionTeamId: teamId,
            promptBody: "go", expectedReturn: "diff",
            proofCommands: ["swift test"], proofWaiver: nil,
            baseGitHead: "abc", localRootPathSnapshot: "/tmp/demo",
            createdAt: Date())
    }

    private func codex() -> Model {
        Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .answerer)
    }

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    func testMixedExecutionTeamBlocksBeforeDirtyAndReadinessGates() {
        var mixed = dispatchOrder(teamId: "custom_mixed")
        mixed.executionTeamId = "custom_mixed"
        let team = TeamPreset(
            id: "custom_mixed", displayName: "Mixed", lane: .code, outputKind: .plan,
            posture: .execute, mutating: true,
            workerSpecs: [
                TeamWorkerSpec(id: "a", skillId: "first_principles_builder", purpose: .answer, preferredModelId: "model_opus"),
                TeamWorkerSpec(id: "b", skillId: "code_maintainer", purpose: .answer, preferredModelId: "model_chatgpt"),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus"))
        let gate = ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: mixed,
            project: project(),
            proposal: proposal(teamId: "custom_mixed"),
            observedRootState: .available,
            dirtyFiles: ["Sources/Foo.swift"],
            dirtyAcknowledged: false,
            workerReadiness: [],
            readyModels: [opus(), codex()],
            teams: [team])
        guard case .blockedSourceGate(let blocker) = gate else {
            return XCTFail("expected source gate block, got \(gate)")
        }
        XCTAssertEqual(blocker.code, ExecutionTeamSourceGate.mixedSourcesCode)
    }

    func testSingleSourceExecutionTeamPassesToReadinessGate() {
        let gate = ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: dispatchOrder(),
            project: project(),
            proposal: proposal(),
            observedRootState: .available,
            dirtyFiles: [],
            dirtyAcknowledged: false,
            workerReadiness: [
                ProjectWorkerReadiness(projectId: "prj_1", sourceId: "codex", status: .ready,
                                       checkedAt: Date(), probeKind: .silent)
            ],
            readyModels: [codex()],
            teams: BuiltInTeams.all)
        guard case .allowed(let scope, let warnings) = gate else {
            return XCTFail("expected allowed, got \(gate)")
        }
        XCTAssertEqual(scope.projectId, "prj_1")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testWorkerNotReadyBlocksAfterSourceGatePasses() {
        let gate = ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: dispatchOrder(),
            project: project(),
            proposal: proposal(),
            observedRootState: .available,
            dirtyFiles: [],
            dirtyAcknowledged: false,
            workerReadiness: [
                ProjectWorkerReadiness(projectId: "prj_1", sourceId: "codex", status: .authRequired,
                                       checkedAt: Date(), probeKind: .silent)
            ],
            readyModels: [codex()],
            teams: BuiltInTeams.all)
        guard case .blockedWorkerNotReady(let sourceId) = gate else {
            return XCTFail("expected worker not ready, got \(gate)")
        }
        XCTAssertEqual(sourceId, "codex")
        XCTAssertEqual(gate.primaryErrorCode, "WORKER_NOT_READY_IN_PROJECT")
    }

    func testRevealModeWorkOrderIsNotDispatchable() {
        var reveal = dispatchOrder()
        reveal.mode = .reveal
        let gate = ProjectMutatingDispatchEvaluator.evaluate(
            workOrder: reveal,
            project: project(),
            proposal: proposal(),
            observedRootState: .available,
            dirtyFiles: [],
            dirtyAcknowledged: false,
            workerReadiness: [],
            readyModels: [codex()])
        XCTAssertEqual(gate, .blockedNotDispatchMode)
    }

    func testPendingExecuteWithMixedWorkersIsSourceGateBlocked() {
        let now = Date()
        let item = PendingItem(
            id: "pending_1", title: "Execute", kind: .dispatch, status: .pending,
            createdAt: now, updatedAt: now,
            prompt: "go",
            target: PendingTarget(preferredWorkerIds: ["model_opus", "model_chatgpt"]),
            policy: PendingPolicy(),
            execution: PendingExecution(intent: .execute))
        let blocker = PendingMutatingSourceGate.evaluate(item: item, readyModels: [opus(), codex()])
        XCTAssertEqual(blocker?.code, ExecutionTeamSourceGate.mixedSourcesCode)
    }
}
