import XCTest
@testable import AllnighterCore

final class TeamRequestResolverTests: XCTestCase {

    private let teams = BuiltInTeams.all

    private func resolve(lane: WorkLane?, team: String?, type: String?, effort: EffortLevel? = nil) -> Result<TeamRequestResolver.Resolved, TeamRequestResolver.Failure> {
        TeamRequestResolver.resolve(teams: teams, lane: lane, teamId: team, type: type, effort: effort)
    }

    // MARK: - Works Test H — Copy type routes to a team

    func testCopyTypeRoutesToLandingPageTeam() {
        guard case .success(let r) = resolve(lane: .copy, team: nil, type: "landing-page") else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(r.team.id, "copy_landing_page")
        XCTAssertEqual(r.type, "landing-page")
        XCTAssertEqual(r.lane, .copy)
    }

    func testExplicitTeamWins() {
        guard case .success(let r) = resolve(lane: .build, team: "build_bug_hunt", type: nil) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(r.team.id, "build_bug_hunt")
        XCTAssertEqual(r.effort, .high) // bug hunt default
    }

    func testLaneDefaultWhenNoTeamOrType() {
        guard case .success(let r) = resolve(lane: .design, team: nil, type: nil) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(r.team.id, "design_core")
    }

    func testEffortOverrideRespected() {
        guard case .success(let r) = resolve(lane: .build, team: "build_core", type: nil, effort: .high) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(r.effort, .high)
    }

    func testTeamWithoutLaneDerivesLane() {
        guard case .success(let r) = resolve(lane: nil, team: "design_premium_polish", type: nil) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(r.lane, .design)
    }

    // MARK: - Conflicts / errors

    func testConflictingTeamAndTypeRejected() {
        guard case .failure(let f) = resolve(lane: .build, team: "build_bug_hunt", type: "landing-page") else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(f, .conflictingTeamAndType(team: "build_bug_hunt", type: "landing-page"))
        XCTAssertEqual(f.code, "CLI_USAGE_ERROR")
    }

    func testTypeMatchingTeamTagIsAllowed() {
        // copy_landing_page carries the landing-page tag, so the pair is valid.
        guard case .success(let r) = resolve(lane: .copy, team: "copy_landing_page", type: "landing-page") else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(r.team.id, "copy_landing_page")
        XCTAssertEqual(r.type, "landing-page")
    }

    func testLaneMismatchRejected() {
        guard case .failure(let f) = resolve(lane: .design, team: "build_bug_hunt", type: nil) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(f, .laneMismatch(team: "build_bug_hunt", teamLane: .build, requestLane: .design))
    }

    func testUnknownTeamRejected() {
        guard case .failure(let f) = resolve(lane: .build, team: "build_nope", type: nil) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(f, .unknownTeam("build_nope"))
        XCTAssertEqual(f.code, "DEFAULT_TEAM_INVALID")
    }

    func testLaneRequiredWhenNoTeam() {
        guard case .failure(let f) = resolve(lane: nil, team: nil, type: nil) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(f, .laneRequired)
    }

    func testNoTeamForUnknownType() {
        guard case .failure(let f) = resolve(lane: .copy, team: nil, type: "carrier-pigeon") else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(f, .noTeamForType(lane: .copy, type: "carrier-pigeon"))
    }
}
