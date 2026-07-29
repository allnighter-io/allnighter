import XCTest
@testable import AllnighterCore

/// `teams show` exposes crew, scout, lead — not crew-only workerSpecs.
final class TeamsShowTests: XCTestCase {
    func testBugHuntShowIncludesLeadCrewAndExactSeatCount() throws {
        let team = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let show = TeamShowJSON.project(
            team,
            contractVersion: ContractRegistry.contractVersion,
            origin: "seed",
            seedId: team.id,
            restoreAvailable: false,
            isDefaultForRun: false
        )

        XCTAssertNil(show.scout)
        XCTAssertEqual(show.crew.count, team.agentSpecs.count)
        XCTAssertEqual(show.lead.role, "lead")
        XCTAssertEqual(show.lead.skillId, team.lead.skillId)
        XCTAssertEqual(show.lead.count, 1)
        XCTAssertEqual(show.lead.preferredModelId, team.lead.preferredModelId)
        XCTAssertEqual(show.lead.fallbackModelIds, team.lead.fallbackModelIds)
        XCTAssertEqual(
            show.lead.requiredCapabilityTags,
            team.lead.requiredCapabilityTags.map(\.rawValue)
        )
        XCTAssertEqual(show.seatCount, team.catalogSeatCount)
        XCTAssertEqual(show.projectedSeatSum, show.seatCount)
        XCTAssertEqual(show.seatCount, show.crew.reduce(0) { $0 + $1.count } + 1)
    }

    func testSignalShowIncludesScoutModelsAndTriangulation() throws {
        let team = try XCTUnwrap(BuiltInTeams.team("signal_outside"))
        let show = TeamShowJSON.project(
            team,
            contractVersion: ContractRegistry.contractVersion,
            origin: "seed",
            seedId: team.id,
            restoreAvailable: false,
            isDefaultForRun: false
        )

        let scout = try XCTUnwrap(show.scout)
        XCTAssertEqual(scout.role, "scout")
        XCTAssertEqual(scout.skillId, team.scout?.skillId)
        XCTAssertEqual(scout.preferredModelId, team.scout?.preferredModelId)
        XCTAssertEqual(scout.fallbackModelIds, team.scout?.fallbackModelIds)
        XCTAssertEqual(scout.allowedModelIds, team.scout?.allowedModelIds ?? [])
        XCTAssertEqual(scout.count, 1)

        XCTAssertFalse(show.crew.isEmpty)
        for (row, spec) in zip(show.crew, team.agentSpecs) {
            XCTAssertEqual(row.role, "crew")
            XCTAssertEqual(row.id, spec.id)
            XCTAssertEqual(row.skillId, spec.skillId)
            XCTAssertEqual(row.count, max(1, spec.count))
            XCTAssertEqual(row.preferredModelId, spec.preferredModelId)
            XCTAssertEqual(row.fallbackModelIds, spec.fallbackModelIds)
            XCTAssertEqual(row.allowedModelIds, spec.allowedModelIds)
            XCTAssertEqual(row.requiredCapabilityTags, spec.requiredCapabilityTags.map(\.rawValue))
            XCTAssertEqual(row.triangulate, spec.triangulate)
            XCTAssertEqual(row.triangulatePreferenceIds, spec.triangulatePreferenceIds)
            XCTAssertEqual(row.required, spec.required)
        }

        XCTAssertEqual(show.seatCount, team.catalogSeatCount)
        XCTAssertEqual(show.projectedSeatSum, show.seatCount)
    }

    func testGrowthMinShowProjectsRowMultiplicity() throws {
        let team = try XCTUnwrap(BuiltInTeams.team("code_growth_min"))
        let show = TeamShowJSON.project(
            team,
            contractVersion: ContractRegistry.contractVersion,
            origin: "seed",
            seedId: team.id,
            restoreAvailable: false,
            isDefaultForRun: false
        )
        let seat = try XCTUnwrap(show.crew.first)
        XCTAssertEqual(seat.count, 4)
        XCTAssertTrue(seat.triangulate)
        XCTAssertEqual(show.seatCount, 5)
        XCTAssertEqual(show.projectedSeatSum, 5)
    }

    func testDefinitionRemainsFullTeamPreset() throws {
        let team = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let data = try CoreJSON.encode(team)
        let roundTrip = try CoreJSON.decode(TeamPreset.self, from: data)
        XCTAssertEqual(roundTrip, team)
    }
}
