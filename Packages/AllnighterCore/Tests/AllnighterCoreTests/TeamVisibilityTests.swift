import XCTest
@testable import AllnighterCore

final class TeamVisibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("team-vis-\(UUID().uuidString).json")
        TeamVisibility.overrideForTesting(file: tmp)
    }
    override func tearDown() {
        TeamVisibility.overrideForTesting(file: nil)
        super.tearDown()
    }

    func testEnabledByDefault() {
        XCTAssertTrue(TeamVisibility.isEnabled("code_core"), "teams show unless explicitly hidden")
        XCTAssertTrue(TeamVisibility.disabledIds().isEmpty)
    }

    func testDisableThenReEnable() throws {
        try TeamVisibility.setEnabled("bug_hunt", false)
        XCTAssertFalse(TeamVisibility.isEnabled("bug_hunt"))
        XCTAssertEqual(TeamVisibility.disabledIds(), ["bug_hunt"])
        // Other teams unaffected.
        XCTAssertTrue(TeamVisibility.isEnabled("code_core"))
        // Re-enable removes it from the disabled set.
        try TeamVisibility.setEnabled("bug_hunt", true)
        XCTAssertTrue(TeamVisibility.isEnabled("bug_hunt"))
        XCTAssertTrue(TeamVisibility.disabledIds().isEmpty)
    }

    func testDisableIsIdempotentAndPersists() throws {
        try TeamVisibility.setEnabled("bug_hunt", false)
        try TeamVisibility.setEnabled("bug_hunt", false)
        XCTAssertEqual(TeamVisibility.disabledIds(), ["bug_hunt"], "no duplicate entries")
    }

    // MARK: - Listing projection honors visibility (CLI + MCP funnel)

    /// An inactive team drops from the default `teams_list`/`alln teams` projection,
    /// so CLI and MCP agree with the GUI — the OFF state is no longer GUI-only.
    func testInactiveTeamDropsFromCatalogProjection() throws {
        let teams = TeamCatalog.all
        let target = try XCTUnwrap(teams.first)
        try TeamVisibility.setEnabled(target.id, false)

        let listed = TeamCatalogJSON.project(teams, lane: nil, contractVersion: "test")
        XCTAssertFalse(listed.teams.contains { $0.id == target.id },
                       "switched-OFF team must not appear in the default catalog listing")
        XCTAssertTrue(listed.teams.allSatisfy(\.active), "default listing returns only active teams")
    }

    /// `includeInactive` reveals the OFF team, stamped `active: false` — truth is
    /// surfaced as a field, never silently dropped (agent-first law).
    func testIncludeInactiveSurfacesTeamWithActiveFalse() throws {
        let teams = TeamCatalog.all
        let target = try XCTUnwrap(teams.first)
        try TeamVisibility.setEnabled(target.id, false)

        let all = TeamCatalogJSON.project(teams, lane: nil, contractVersion: "test", includeInactive: true)
        let entry = try XCTUnwrap(all.teams.first { $0.id == target.id })
        XCTAssertFalse(entry.active, "inactive team is returned with active:false when includeInactive")
    }

    /// Hiding a team must never break resolution by id — `team_start`, the default-run
    /// team, and a thread's chosen team all resolve through `TeamCatalog.get`.
    func testInactiveTeamStillResolvesById() throws {
        let target = try XCTUnwrap(TeamCatalog.all.first)
        try TeamVisibility.setEnabled(target.id, false)
        XCTAssertNotNil(TeamCatalog.get(target.id), "inactive means hidden from listings, not unrunnable")
    }
}
