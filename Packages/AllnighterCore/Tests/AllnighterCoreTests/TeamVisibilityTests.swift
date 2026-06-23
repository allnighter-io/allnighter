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
}
