import XCTest
@testable import AllnighterCore

/// CRAFT-1: the team/craft model gains Signal as the 4th craft plus team posture
/// and a mutating flag, on the SAME substrate (no second system). Existing teams
/// keep correct, non-mutating postures.
final class CraftModelTests: XCTestCase {
    func testSignalIsAFourthCraft() {
        XCTAssertEqual(WorkLane.allCases.count, 4)
        XCTAssertTrue(WorkLane.allCases.contains(.signal))
        XCTAssertEqual(WorkLane.signal.rawValue, "signal")
    }

    func testInsightOutputKindAndPostures() {
        XCTAssertTrue(TeamOutputKind.allCases.contains(.insight))
        XCTAssertEqual(Set(TeamPosture.allCases), [.scout, .propose, .review, .execute])
    }

    func testTeamPresetRoundTripsPostureAndMutating() throws {
        let team = TeamPreset(
            id: "signal_demo", displayName: "Demo", lane: .signal, outputKind: .insight,
            posture: .scout, mutating: false,
            workerSpecs: [TeamWorkerSpec(id: "r", skillId: "s")],
            lead: TeamLeadSpec(skillId: "w"), builtIn: true)
        let data = try CoreJSON.encode(team)
        let back = try CoreJSON.decode(TeamPreset.self, from: data)
        XCTAssertEqual(back.posture, .scout)
        XCTAssertEqual(back.mutating, false)
        XCTAssertEqual(back.lane, .signal)
        XCTAssertEqual(back.outputKind, .insight)
    }

    func testExistingBuiltInsHaveCorrectNonMutatingPostures() {
        // Drafting outputs propose; audit/diagnostic outputs review; none mutate.
        XCTAssertEqual(BuiltInTeams.team("code_core")?.posture, .propose)
        XCTAssertEqual(BuiltInTeams.team("design_core")?.posture, .propose)
        XCTAssertEqual(BuiltInTeams.team("copy_core")?.posture, .propose)
        XCTAssertEqual(BuiltInTeams.team("code_security_review")?.posture, .review)
        XCTAssertEqual(BuiltInTeams.team("code_bug_hunt")?.posture, .review)
        XCTAssertEqual(BuiltInTeams.team("code_release_proof")?.posture, .review)
        for team in BuiltInTeams.all {
            XCTAssertFalse(team.mutating, "\(team.id) must be non-mutating (advisory; Execute is a separate gate)")
        }
    }

    func testStaleBuildLanguageIsGoneFromPublicNames() {
        // Cutover hygiene: no public team display name still says "Build".
        for team in BuiltInTeams.all {
            XCTAssertFalse(team.displayName.contains("Build"), "\(team.id) display name still says Build")
        }
        XCTAssertEqual(BuiltInTeams.team("code_core")?.displayName, "Code Core")
    }

    func testSignalLaneHasNoBuiltInsYet() {
        // CRAFT-2 adds Signal built-in teams + signal-capable models/skills.
        XCTAssertTrue(BuiltInTeams.teams(in: .signal).isEmpty)
    }
}
