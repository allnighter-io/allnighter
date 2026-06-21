import XCTest
@testable import AllnighterCore

/// WT-ETS01–05: execution team source gate (`Execution_Team_Source_Gate.md`).
final class ExecutionTeamSourceGateTests: XCTestCase {

    private func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    private func codex() -> Model {
        Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .answerer)
    }

    private func mixedReviewTeam() -> TeamPreset {
        TeamPreset(
            id: "custom_mixed_review", displayName: "Mixed Review", lane: .code, outputKind: .plan,
            mutating: false,
            workerSpecs: [
                TeamWorkerSpec(id: "a", skillId: "first_principles_builder", purpose: .answer, preferredModelId: "model_opus"),
                TeamWorkerSpec(id: "b", skillId: "code_maintainer", purpose: .answer, preferredModelId: "model_chatgpt"),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus"))
    }

    private func mixedExecutionTeam() -> TeamPreset {
        var team = mixedReviewTeam()
        team.mutating = true
        return team
    }

    private func singleSourceExecutionTeam() -> TeamPreset {
        TeamPreset(
            id: "custom_codex_execute", displayName: "Codex Execute", lane: .code, outputKind: .plan,
            mutating: true, executionSourceId: "codex",
            workerSpecs: [
                TeamWorkerSpec(id: "a", skillId: "first_principles_builder", purpose: .answer, preferredModelId: "model_chatgpt", fallbackPolicy: .exactOnly),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_chatgpt", fallbackPolicy: .exactOnly))
    }

    // MARK: - WT-ETS01

    func testMixedSourceJudgmentTeamPassesSourceGate() {
        let bench = [opus(), codex()]
        let preflight = TeamPreflight.preflight(
            teams: [mixedReviewTeam()], lane: .code, teamId: "custom_mixed_review",
            type: nil, effort: .med, readyModels: bench)
        XCTAssertTrue(preflight.canStart)
        XCTAssertEqual(preflight.sourceGateStatus, "pass")
        XCTAssertEqual(preflight.executionSourcePolicy, "mixedAllowed")
        XCTAssertEqual(Set(preflight.resolvedSourceIds), ["claude_code", "codex"])
        XCTAssertNil(preflight.sourceGateBlocker)
    }

    // MARK: - WT-ETS02

    func testMixedSourceExecutionTeamIsBlocked() {
        let bench = [opus(), codex()]
        let preflight = TeamPreflight.preflight(
            teams: [mixedExecutionTeam()], lane: .code, teamId: "custom_mixed_review",
            type: nil, effort: .med, readyModels: bench)
        XCTAssertFalse(preflight.canStart)
        XCTAssertEqual(preflight.sourceGateStatus, "blocked")
        XCTAssertEqual(preflight.sourceGateBlocker?.code, ExecutionTeamSourceGate.mixedSourcesCode)
        XCTAssertEqual(Set(preflight.sourceGateBlocker?.resolvedSourceIds ?? []), ["claude_code", "codex"])
        XCTAssertTrue(preflight.sourceGateBlocker?.message.contains("claude_code") ?? false
                      || preflight.sourceGateBlocker?.message.contains("Codex") ?? false)
        XCTAssertTrue(preflight.repairOptions.contains { $0.kind == "switchNonMutating" })
        XCTAssertTrue(preflight.repairOptions.contains { $0.kind == "pickOneSource" })
    }

    func testCatalogSaveBlocksMixedExecutionTeam() {
        var custom = mixedExecutionTeam()
        custom.id = "custom_code_mixed_exec"
        custom.builtIn = false
        XCTAssertThrowsError(try TeamCatalog.saveCustom(custom)) { error in
            guard case CatalogError.teamInvalid(let message) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(message.contains("exactly one worker"))
        }
    }

    // MARK: - WT-ETS03

    func testSingleSourceExecutionTeamPassesSourceGate() {
        let bench = [codex()]
        let preflight = TeamPreflight.preflight(
            teams: [singleSourceExecutionTeam()], lane: .code, teamId: "custom_codex_execute",
            type: nil, effort: .med, readyModels: bench)
        XCTAssertTrue(preflight.canStart)
        XCTAssertEqual(preflight.sourceGateStatus, "pass")
        XCTAssertEqual(preflight.executionSourceId, "codex")
        XCTAssertEqual(preflight.executionSourcePolicy, "singleSourceRequired")
    }

    func testBuiltInExecutionTeamsAreSourceScoped() {
        for id in ["default_chat", "execution_playbook"] {
            guard let team = BuiltInTeams.team(id) else { return XCTFail("missing \(id)") }
            XCTAssertTrue(team.mutating)
            XCTAssertNotNil(team.executionSourceId)
            let bench = ModelCatalog.list().map {
                Model(id: $0.id, displayName: $0.displayName, modelLabel: $0.modelLabel,
                      driverId: $0.driverId, role: $0.role, enabled: true)
            }
            let gate = ExecutionTeamSourceGate.evaluate(
                resolved: TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .med, readyModels: bench),
                models: bench)
            XCTAssertEqual(gate.sourceGateStatus, .pass, id)
            XCTAssertEqual(gate.executionSourceId, team.executionSourceId)
        }
    }

    // MARK: - WT-ETS05

    func testPreflightBlockerMatchesPureEvaluator() {
        let bench = [opus(), codex()]
        let team = mixedExecutionTeam()
        let resolved = TeamResolver.resolve(team: team, requestLane: .code, requestEffort: .med, readyModels: bench)
        let gate = ExecutionTeamSourceGate.evaluate(resolved: resolved, models: bench)
        let preflight = TeamPreflight.preflight(
            teams: [team], lane: .code, teamId: team.id, type: nil, effort: .med, readyModels: bench)
        XCTAssertEqual(preflight.sourceGateBlocker?.code, gate.sourceGateBlocker?.code)
        XCTAssertEqual(preflight.resolvedSourceIds, gate.resolvedSourceIds)
        XCTAssertEqual(preflight.sourceGateStatus, gate.sourceGateStatus.rawValue)
    }
}
