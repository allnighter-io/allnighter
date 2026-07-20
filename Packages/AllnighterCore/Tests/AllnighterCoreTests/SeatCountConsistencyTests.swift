import XCTest
@testable import AllnighterCore

/// SH-S06 / Law 8: one seatCount across list, menu, show (and catalog owner).
final class SeatCountConsistencyTests: XCTestCase {
    func testBuiltInSeatCountMatchesListMenuShowAndProjectedSum() throws {
        let teams = BuiltInTeams.all.filter { !$0.isLabTeam }
        let list = TeamCatalogJSON.project(
            teams, lane: nil, contractVersion: ContractRegistry.contractVersion
        )
        let menu = MenuCatalog.project(teams: teams)
        let listById = Dictionary(uniqueKeysWithValues: list.teams.map { ($0.id, $0) })
        let menuById = Dictionary(uniqueKeysWithValues: menu.teams.map { ($0.id, $0) })

        for team in teams {
            let show = TeamShowJSON.project(
                team,
                contractVersion: ContractRegistry.contractVersion,
                origin: "seed",
                seedId: team.id,
                restoreAvailable: false,
                isDefaultForRun: team.id == "default_chat"
            )
            let catalog = team.catalogSeatCount
            XCTAssertEqual(show.seatCount, catalog, "\(team.id) show.seatCount")
            XCTAssertEqual(show.projectedSeatSum, catalog, "\(team.id) projected seat sum")
            XCTAssertEqual(listById[team.id]?.seatCount, catalog, "\(team.id) list.seatCount")
            XCTAssertEqual(menuById[team.id]?.seatCount, catalog, "\(team.id) menu.seatCount")
        }
    }

    func testCustomDuplicateKeepsSeatCountConsistency() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("seat-count-\(UUID().uuidString)", isDirectory: true)
        let teamsRoot = root.appendingPathComponent("teams", isDirectory: true)
        let skillsRoot = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: teamsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
        defer { CatalogRoots.resetTestingOverrides() }

        let custom = try TeamCatalog.duplicateBuiltIn("code_bug_hunt", name: "Seat Count Custom")
        var edited = custom
        edited.workerSpecs = edited.workerSpecs.map { row in
            var copy = row
            if copy.count == 1 { copy.count = 2 }
            return copy
        }
        try TeamCatalog.saveCustom(edited)
        let loaded = try XCTUnwrap(TeamCatalog.get(edited.id))

        let show = TeamShowJSON.project(
            loaded,
            contractVersion: ContractRegistry.contractVersion,
            origin: "custom",
            seedId: nil,
            restoreAvailable: false,
            isDefaultForRun: false
        )
        let list = TeamCatalogJSON.project(
            [loaded], lane: nil, contractVersion: ContractRegistry.contractVersion
        )
        let menu = MenuCatalog.project(teams: [loaded])

        XCTAssertEqual(show.projectedSeatSum, loaded.catalogSeatCount)
        XCTAssertEqual(show.seatCount, loaded.catalogSeatCount)
        XCTAssertEqual(list.teams.first?.seatCount, loaded.catalogSeatCount)
        XCTAssertEqual(menu.teams.first?.seatCount, loaded.catalogSeatCount)
        XCTAssertGreaterThan(loaded.catalogSeatCount, loaded.workerSpecs.count + 1)
    }

    func testMenuShowTeamDetailUsesSeatCount() throws {
        let detail = try MenuCatalog.show(ref: "team:code_bug_hunt")
        let team = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        XCTAssertEqual(detail.team?.seatCount, team.catalogSeatCount)
    }
}
