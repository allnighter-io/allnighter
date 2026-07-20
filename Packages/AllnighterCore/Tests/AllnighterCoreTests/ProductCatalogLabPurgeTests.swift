import XCTest
@testable import AllnighterCore

/// AE-S02: product TeamCatalog contains zero `isLabTeam` entries; write path
/// redirects lab-tagged teams to lab storage (match on typeTags, not id prefix).
final class ProductCatalogLabPurgeTests: XCTestCase {
    private var teamsRoot: URL!
    private var skillsRoot: URL!
    private var labRoot: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        teamsRoot = base.appendingPathComponent("teams", isDirectory: true)
        skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        labRoot = base.appendingPathComponent("lab-teams", isDirectory: true)
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot, labTeams: labRoot)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        try? FileManager.default.removeItem(at: teamsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testBuiltInCatalogContainsZeroLabTeams() {
        let labs = BuiltInTeams.all.filter(\.isLabTeam)
        XCTAssertTrue(labs.isEmpty, "built-ins must not ship lab teams: \(labs.map(\.id))")
    }

    func testProductAllContainsZeroLabTeams() {
        XCTAssertTrue(TeamCatalog.all.filter(\.isLabTeam).isEmpty)
    }

    func testSaveCustomRedirectsLabTaggedTeamToLabStorage() throws {
        var team = try TeamCatalog.duplicateBuiltIn("code_bug_hunt", name: "Lab Experiment")
        // Ensure lab tag (code_core-style: display Lab without lab_ id prefix).
        team.id = "code_core"
        team.displayName = "Code Core · Lab"
        team.typeTags = [TeamPreset.labTypeTag]

        try TeamCatalog.saveCustom(team)

        XCTAssertNil(
            CatalogFileIO.loadOne(id: "code_core", kind: .team, root: CatalogRoots.teams, as: TeamPreset.self),
            "lab team must not land in product Catalogs/teams"
        )
        XCTAssertNotNil(LabTeamCatalog.get("code_core"))
        XCTAssertTrue(TeamCatalog.all.filter(\.isLabTeam).isEmpty)
        XCTAssertEqual(TeamCatalog.get("code_core")?.displayName, "Code Core · Lab",
                       "explicit get still resolves lab teams for the Team Lab runner")
    }

    func testStrayLabFileMigratesOutOfProductCatalog() throws {
        var team = try TeamCatalog.duplicateBuiltIn("code_bug_hunt", name: "Stray Lab")
        team.id = "lab_code_bug_hunt_r99_champion"
        team.typeTags = [TeamPreset.labTypeTag]
        team.displayName = "Bug Hunt · Lab"
        // Bypass saveCustom — write a stray product-root file the way old Team Lab did.
        try CatalogFileIO.save(team, id: team.id, kind: .team, root: CatalogRoots.teams)
        XCTAssertNotNil(CatalogFileIO.loadOne(id: team.id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self))

        _ = TeamCatalog.all

        XCTAssertNil(CatalogFileIO.loadOne(id: team.id, kind: .team, root: CatalogRoots.teams, as: TeamPreset.self))
        XCTAssertNotNil(LabTeamCatalog.get(team.id))
        XCTAssertTrue(TeamCatalog.all.filter(\.isLabTeam).isEmpty)
        XCTAssertTrue(TeamCatalog.all.contains { $0.id == "code_bug_hunt_min" },
                      "shipped Bug Hunt Min must remain visible")
    }

    func testIsLabTeamMatchesTypeTagsNotIdPrefix() {
        var bare = try! XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        bare.typeTags = [TeamPreset.labTypeTag]
        bare.id = "code_core"
        XCTAssertTrue(bare.isLabTeam, "code_core with lab tag must match without lab_ prefix")

        var prefixed = bare
        prefixed.id = "lab_code_bug_hunt_r1"
        prefixed.typeTags = []
        XCTAssertFalse(prefixed.isLabTeam, "lab_ id prefix alone must not imply lab")
    }

    func testCatalogSeatCountIncludesLeadAndScout() {
        let min = try! XCTUnwrap(BuiltInTeams.team("code_bug_hunt_min"))
        XCTAssertNil(min.scout)
        XCTAssertEqual(min.catalogSeatCount, min.workerSpecs.reduce(0) { $0 + max(1, $1.count) } + 1)

        let signal = try! XCTUnwrap(BuiltInTeams.team("signal_outside"))
        XCTAssertNotNil(signal.scout)
        XCTAssertEqual(signal.catalogSeatCount, signal.workerSpecs.reduce(0) { $0 + max(1, $1.count) } + 2)

        let projected = TeamCatalogJSON.project(
            [min, signal], lane: nil, contractVersion: ContractRegistry.contractVersion
        )
        XCTAssertEqual(projected.teams.first { $0.id == min.id }?.seatCount, min.catalogSeatCount)
        XCTAssertEqual(projected.teams.first { $0.id == signal.id }?.seatCount, signal.catalogSeatCount)
    }

    func testCatalogSeatCountIncludesRowMultiplicity() {
        let growth = try! XCTUnwrap(BuiltInTeams.team("code_growth_min"))
        XCTAssertEqual(growth.workerSpecs.first?.count, 4)
        XCTAssertEqual(growth.catalogSeatCount, 5, "4 triangulated crew + lead")
        XCTAssertNotEqual(growth.catalogSeatCount, growth.workerSpecs.count + 1,
                          "row count alone under-counts multiplicity")
    }
}
