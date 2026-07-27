import XCTest
@testable import AllnighterCore

final class AgentBootstrapTests: XCTestCase {

    private func opus() -> Model { Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus", driverId: "claude_code", role: .both) }
    private let teams = BuiltInTeams.all

    // MARK: - readiness

    func testReadyBenchCanStartTeams() {
        let v = AgentReadiness.evaluate(teams: teams, readyModels: [opus()])
        XCTAssertTrue(v.canStartTeamRun)
        XCTAssertTrue(v.readyTeams.contains { $0.team == "code_bug_hunt" })
        XCTAssertNil(v.blockedReason)
        XCTAssertEqual(v.nextAction.kind, "startTeamRun")
        XCTAssertEqual(v.nextAction.command, "alln run \"<message>\" --team <team-id> --detach --json")
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: v.nextAction.command), "run")
    }

    func testEmptyBenchBlocksWithSourceAction() {
        let v = AgentReadiness.evaluate(teams: teams, readyModels: [])
        XCTAssertFalse(v.canStartTeamRun)
        XCTAssertTrue(v.readyTeams.isEmpty)
        XCTAssertEqual(v.nextAction.kind, "installOrAuthSource")
        XCTAssertEqual(v.nextAction.command, "alln doctor --json")
        XCTAssertTrue(v.blockedReason?.contains("No ready model") ?? false)
    }

    // MARK: - preflight

    /// Max roster is 8 answer/review + writer = 9.
    /// Retargeted to `code_bug_hunt_max` so the Product_Vocabulary depth rename does not change
    /// the bare-`code_bug_hunt` 4-seat default path.
    func testPreflightBugHuntHighOnOneModel() {
        let r = TeamPreflight.preflight(teams: teams, lane: .code, teamId: "code_bug_hunt_max",
                                        type: nil, effort: .high, readyModels: [opus()])
        XCTAssertTrue(r.canStart)
        XCTAssertEqual(r.teamPresetId, "code_bug_hunt_max")
        XCTAssertEqual(r.effort, "high")
        XCTAssertEqual(r.outputKind, "bugPacket")
        XCTAssertEqual(r.readyWorkers.count, 9) // 8 answer/review + writer
        XCTAssertTrue(r.selfFusion.enabled)
        XCTAssertEqual(r.nextAction.kind, "startTeamRun")
        XCTAssertEqual(r.nextAction.command, "alln run \"<message>\" --team code_bug_hunt_max --detach --json")
        XCTAssertTrue(r.readyWorkers.contains { $0.purpose == "plan" }) // synthetic writer
    }

    func testPreflightDesignCoreThreeImageWorkers() {
        let ready = [
            opus(),
            Model(id: "model_gemini", displayName: "Gemini", modelLabel: "g", driverId: "antigravity", role: .answerer),
            Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt", driverId: "codex", role: .answerer),
            Model(id: "model_grok", displayName: "Grok", modelLabel: "grok", driverId: "grok", role: .answerer),
        ]
        let r = TeamPreflight.preflight(teams: teams, lane: .design, teamId: "design_design",
                                        type: nil, effort: .high, readyModels: ready)
        XCTAssertTrue(r.canStart)
        XCTAssertEqual(r.readyWorkers.filter { $0.purpose != "plan" }.count, 3)
    }

    func testPreflightRejectsConflictingTeamAndType() {
        let r = TeamPreflight.preflight(teams: teams, lane: .code, teamId: "code_bug_hunt",
                                        type: "landing-page", effort: nil, readyModels: [opus()])
        XCTAssertFalse(r.canStart)
        XCTAssertTrue(r.blockedReason?.contains("conflicts with") ?? false)
        XCTAssertEqual(r.nextAction.kind, "performHumanAction")
    }

    func testPreflightCopyTypeRoutes() {
        let r = TeamPreflight.preflight(teams: teams, lane: .copy, teamId: nil,
                                        type: "landing-page", effort: nil, readyModels: [opus()])
        XCTAssertEqual(r.teamPresetId, "copy_landing")
        XCTAssertTrue(r.canStart)
    }

    func testPreflightDoesNotRunOrMutate() {
        // Preflight is pure: calling it twice yields identical results, no run id.
        let a = TeamPreflight.preflight(teams: teams, lane: .code, teamId: "code_plan", type: nil, effort: .med, readyModels: [opus()])
        let b = TeamPreflight.preflight(teams: teams, lane: .code, teamId: "code_plan", type: nil, effort: .med, readyModels: [opus()])
        XCTAssertEqual(a, b)
    }

    /// ASF-S02: preflight nextAction encodes `command`, never a `"tool"` key.
    func testPreflightNextActionJSONHasCommandNotTool() throws {
        let r = TeamPreflight.preflight(teams: teams, lane: .code, teamId: "code_bug_hunt",
                                        type: nil, effort: nil, readyModels: [opus()])
        XCTAssertTrue(r.canStart)
        XCTAssertTrue(r.nextAction.command.hasPrefix("alln run"))
        XCTAssertEqual(ContractRegistry.resolveCommandName(from: r.nextAction.command), "run")

        let obj = try JSONSerialization.jsonObject(with: CoreJSON.encode(r)) as? [String: Any]
        let next = try XCTUnwrap(obj?["nextAction"] as? [String: Any])
        XCTAssertEqual(next["kind"] as? String, "startTeamRun")
        XCTAssertNotNil(next["command"] as? String)
        XCTAssertNil(next["tool"], "ASF-S02: tool key must not appear in nextAction")
        // Whole envelope must not reintroduce a tool-id next-action grammar.
        let raw = String(data: try CoreJSON.encode(r.nextAction), encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("\"tool\""))
    }

    func testAsyncTeamNextActionJSONHasCommandNotTool() throws {
        let poll = AsyncTeamNextAction.pollStatus(runId: "run-abc")
        let result = AsyncTeamNextAction.fetchResult(runId: "run-abc")
        for action in [poll, result] {
            let obj = try JSONSerialization.jsonObject(with: CoreJSON.encode(action)) as? [String: Any]
            XCTAssertNotNil(obj?["command"] as? String)
            XCTAssertNil(obj?["tool"])
            XCTAssertTrue((obj?["command"] as? String)?.hasPrefix("alln team ") ?? false)
            XCTAssertNotNil(ContractRegistry.resolveCommandName(from: action.command))
        }
    }
}
