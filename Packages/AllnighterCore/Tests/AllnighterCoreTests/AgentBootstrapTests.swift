import XCTest
@testable import AllnighterCore

final class AgentBootstrapTests: XCTestCase {

    private func opus() -> Model { Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both) }
    private let teams = BuiltInTeams.all

    // MARK: - mcp_hello readiness

    func testReadyBenchCanStartTeams() {
        let v = AgentReadiness.evaluate(teams: teams, readyModels: [opus()])
        XCTAssertTrue(v.canStartTeamRun)
        XCTAssertTrue(v.readyTeams.contains { $0.team == "build_bug_hunt" })
        XCTAssertNil(v.blockedReason)
        XCTAssertEqual(v.nextAction.kind, "startTeamRun")
    }

    func testEmptyBenchBlocksWithSourceAction() {
        let v = AgentReadiness.evaluate(teams: teams, readyModels: [])
        XCTAssertFalse(v.canStartTeamRun)
        XCTAssertTrue(v.readyTeams.isEmpty)
        XCTAssertEqual(v.nextAction.kind, "installOrAuthSource")
        XCTAssertTrue(v.blockedReason?.contains("No ready model") ?? false)
    }

    // MARK: - team_preflight

    func testPreflightBugHuntHighOnOneModel() {
        let r = TeamPreflight.preflight(teams: teams, lane: .build, teamId: "build_bug_hunt",
                                        type: nil, effort: .high, readyModels: [opus()])
        XCTAssertTrue(r.canStart)
        XCTAssertEqual(r.teamPresetId, "build_bug_hunt")
        XCTAssertEqual(r.effort, "high")
        XCTAssertEqual(r.outputKind, "bugPacket")
        XCTAssertEqual(r.readyWorkers.count, 10) // 9 answer/review + writer
        XCTAssertTrue(r.selfFusion.enabled)
        XCTAssertEqual(r.nextAction.kind, "startTeamRun")
        XCTAssertTrue(r.readyWorkers.contains { $0.purpose == "plan" }) // synthetic writer
    }

    func testPreflightDisablesOptionalImageRow() {
        // design_core has an optional image row (outlier_direction); Opus has no image.
        let r = TeamPreflight.preflight(teams: teams, lane: .design, teamId: "design_core",
                                        type: nil, effort: .high, readyModels: [opus()])
        XCTAssertTrue(r.canStart)
        XCTAssertTrue(r.blockedWorkers.contains { $0.skillId == "outlier_direction" && !$0.required })
    }

    func testPreflightRejectsConflictingTeamAndType() {
        let r = TeamPreflight.preflight(teams: teams, lane: .build, teamId: "build_bug_hunt",
                                        type: "landing-page", effort: nil, readyModels: [opus()])
        XCTAssertFalse(r.canStart)
        XCTAssertTrue(r.blockedReason?.contains("conflicts with") ?? false)
        XCTAssertEqual(r.nextAction.kind, "performHumanAction")
    }

    func testPreflightCopyTypeRoutes() {
        let r = TeamPreflight.preflight(teams: teams, lane: .copy, teamId: nil,
                                        type: "landing-page", effort: nil, readyModels: [opus()])
        XCTAssertEqual(r.teamPresetId, "copy_landing_page")
        XCTAssertTrue(r.canStart)
    }

    func testPreflightDoesNotRunOrMutate() {
        // Preflight is pure: calling it twice yields identical results, no run id.
        let a = TeamPreflight.preflight(teams: teams, lane: .build, teamId: "build_core", type: nil, effort: .med, readyModels: [opus()])
        let b = TeamPreflight.preflight(teams: teams, lane: .build, teamId: "build_core", type: nil, effort: .med, readyModels: [opus()])
        XCTAssertEqual(a, b)
    }
}
