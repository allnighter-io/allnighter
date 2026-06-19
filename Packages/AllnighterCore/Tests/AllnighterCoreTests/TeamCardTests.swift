import XCTest
@testable import AllnighterCore

/// T-S00: TeamCard is a projection over the existing TeamPreset — no new team, no
/// "promise" fluff. Requirements are DERIVED (ready worker for the craft; Execute
/// approval if mutating), never an authored input ask (Design needs no screenshot).
final class TeamCardTests: XCTestCase {
    func testCardProjectsExistingTeamFields() {
        let team = BuiltInTeams.team("signal_post_to_project")!
        let card = TeamCard.project(team)
        XCTAssertEqual(card.id, "signal_post_to_project")
        XCTAssertEqual(card.family, "signal")
        XCTAssertEqual(card.posture, "scout")
        XCTAssertFalse(card.mutating)
        XCTAssertEqual(card.outputKind, "insight")
        XCTAssertEqual(card.workerCount, team.workerSpecs.count)
        XCTAssertFalse(card.starterPrompts.isEmpty)   // best-shot placeholder present
    }

    func testRequirementsAreDerivedNotAuthoredInputAsks() {
        // A non-mutating scout card requires only a ready worker — never "attach a
        // screenshot" or any authored input gate.
        let signal = TeamCard.project(BuiltInTeams.team("signal_post_to_project")!)
        XCTAssertEqual(signal.requirements, ["Needs at least one ready signal worker."])

        let design = TeamCard.project(BuiltInTeams.team("design_premium_polish")!)
        XCTAssertEqual(design.requirements, ["Needs at least one ready design worker."])
        XCTAssertFalse(design.requirements.contains { $0.lowercased().contains("screenshot") || $0.lowercased().contains("image") })
    }

    func testMutatingCardRequiresExecuteApproval() {
        var team = BuiltInTeams.team("code_core")!
        team.mutating = true
        team.posture = .execute
        let card = TeamCard.project(team)
        XCTAssertTrue(card.mutating)
        XCTAssertTrue(card.requirements.contains { $0.contains("Execute approval") })
    }

    func testCatalogProjectionPinsRequestedTeams() {
        let cards = TeamCardCatalogJSON.project(
            BuiltInTeams.all, family: nil, contractVersion: "1.0.0",
            pinned: ["signal_post_to_project", "code_bug_hunt"])
        XCTAssertEqual(cards.cards.count, BuiltInTeams.all.count)
        XCTAssertEqual(Set(cards.cards.filter(\.pinned).map(\.id)), ["signal_post_to_project", "code_bug_hunt"])
        XCTAssertTrue(cards.cards.allSatisfy { !$0.displayName.isEmpty })
    }

    func testNoPromiseField() {
        // Reflection guard: the card must not carry a marketing "promise" field.
        let card = TeamCard.project(BuiltInTeams.team("code_core")!)
        let labels = Set(Mirror(reflecting: card).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("promise"))
    }
}
