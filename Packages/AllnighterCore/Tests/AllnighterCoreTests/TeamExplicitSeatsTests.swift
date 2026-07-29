import XCTest
import AllnighterCore

/// RSO-S01 — runtime `--seat` overrides for judgment-team crew rows.
final class TeamExplicitSeatsTests: XCTestCase {

    private func readyBench() -> [Model] {
        [
            Model(id: "model_gpt_sol", displayName: "GPT", modelLabel: "gpt",
                  driverId: "codex", role: .answerer, enabled: true),
            Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                  driverId: "grok", role: .answerer, enabled: true),
            Model(id: "model_cursor_composer_25", displayName: "Composer", modelLabel: "composer",
                  driverId: "cursor", role: .answerer, enabled: true),
        ]
    }

    func testCrewSlotCountMatchesSpecReviewMin() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        XCTAssertEqual(TeamExplicitSeats.crewSlotCount(team: team), 3)
    }

    func testValidateFlagsRejectsExecutionTeam() {
        let team = BuiltInTeams.team("build_slice")!
        let err = TeamExplicitSeats.validateFlags(
            seatModelIds: ["model_gpt_sol"],
            explicitTeamChosen: true,
            explicitWorkerChosen: false,
            preset: team
        )
        XCTAssertEqual(err, .executionTeamNotAllowed("build_slice"))
    }

    func testValidateFlagsRejectsWorkerPlusSeat() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let err = TeamExplicitSeats.validateFlags(
            seatModelIds: ["model_gpt_sol", "model_grok", "model_cursor_composer_25"],
            explicitTeamChosen: true,
            explicitWorkerChosen: true,
            preset: team
        )
        XCTAssertEqual(err, .conflictsWithWorker)
    }

    func testValidateFlagsRejectsCountMismatch() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let err = TeamExplicitSeats.validateFlags(
            seatModelIds: ["model_gpt_sol", "model_grok"],
            explicitTeamChosen: true,
            explicitWorkerChosen: false,
            preset: team
        )
        XCTAssertEqual(err, .countMismatch(expected: 3, received: 2))
    }

    func testResolveHonorsOrderedSeats() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let bench = readyBench()
        let result = TeamExplicitSeats.resolve(
            team: team,
            lane: .code,
            effort: .med,
            seatModelIds: ["model_gpt_sol", "model_grok", "model_cursor_composer_25"],
            models: bench,
            readyModels: bench
        )
        guard case .success(let resolved) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(
            resolved.answerWorkers.map(\.modelId),
            ["model_gpt_sol", "model_grok", "model_cursor_composer_25"]
        )
        XCTAssertTrue(resolved.answerWorkers.allSatisfy {
            $0.seatingReason == TeamExplicitSeats.explicitSeatingReason
        })
    }
}
