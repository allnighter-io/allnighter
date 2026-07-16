import XCTest
@testable import AllnighterCore

/// PN-S04 roster resolution matrix: team unique/ambiguous/none, seat override,
/// remembered/lane-default is CLI-level; mapping is stated here.
final class PanelTeamResolverTests: XCTestCase {

    private func sampleTeams() -> [TeamPreset] {
        [
            TeamPreset(
                id: "code_spec_review", displayName: "Spec Review", lane: .code,
                outputKind: .specReview,
                workerSpecs: [
                    TeamWorkerSpec(id: "spec_first", skillId: "spec_first_principles_reviewer", purpose: .answer, preferredModelId: "model_opus"),
                    TeamWorkerSpec(id: "spec_scope", skillId: "spec_scope_steward", purpose: .answer, preferredModelId: "model_sonnet"),
                    TeamWorkerSpec(id: "spec_hype", skillId: "spec_hype_skeptic", purpose: .review, preferredModelId: "model_gemini"),
                ],
                lead: TeamLeadSpec(skillId: "spec_review_writer", preferredModelId: "model_opus"),
                builtIn: true
            ),
            TeamPreset(
                id: "code_security_review", displayName: "Security Review", lane: .code,
                outputKind: .securityRegister,
                workerSpecs: [
                    TeamWorkerSpec(id: "boundary", skillId: "boundary_mapper", purpose: .answer, preferredModelId: "model_opus"),
                ],
                lead: TeamLeadSpec(skillId: "security_register_writer"),
                builtIn: true
            ),
            TeamPreset(
                id: "code_core", displayName: "Code Core", lane: .code,
                outputKind: .plan, isDefaultForLane: true,
                workerSpecs: [
                    TeamWorkerSpec(id: "product_architect", skillId: "product_architect", purpose: .answer, preferredModelId: "model_cursor_composer_25"),
                ],
                lead: TeamLeadSpec(skillId: "plan_writer_build"),
                builtIn: true
            ),
        ]
    }

    func testUniqueTeamAliasResolvesAndEchoes() {
        let result = PanelTeamResolver.resolveTeam(alias: "spec_review", teams: sampleTeams())
        guard case .success(let team) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(team.id, "code_spec_review")
    }

    func testAmbiguousAliasListsCandidatesWithSeatCount() {
        // "review" matches Spec Review and Security Review
        let result = PanelTeamResolver.resolveTeam(alias: "review", teams: sampleTeams())
        guard case .failure(.ambiguous(let alias, let candidates)) = result else {
            return XCTFail("expected ambiguous, got \(result)")
        }
        XCTAssertEqual(alias, "review")
        XCTAssertEqual(candidates.count, 2)
        let formatted = PanelTeamResolver.formatCandidates(candidates)
        XCTAssertTrue(formatted.contains("seats"))
        XCTAssertTrue(formatted.contains("Spec Review") || formatted.contains("code_spec_review"))
    }

    func testNoMatchListsAvailableTeams() {
        let result = PanelTeamResolver.resolveTeam(alias: "pressure", teams: sampleTeams())
        guard case .failure(.noMatch(let alias, let available)) = result else {
            return XCTFail("expected noMatch, got \(result)")
        }
        XCTAssertEqual(alias, "pressure")
        XCTAssertFalse(available.isEmpty)
        let formatted = PanelTeamResolver.formatAvailable(available)
        XCTAssertTrue(formatted.contains("code_core"))
    }

    func testSeatsMappingUsesPreferredModelAndSkillAsLens() {
        let team = sampleTeams()[0]
        let seats = PanelTeamResolver.seats(from: team)
        // Lead is NOT a seat (session synthesizes).
        XCTAssertEqual(seats.count, 3)
        XCTAssertEqual(seats[0].workerId, "model_opus")
        XCTAssertEqual(seats[0].lens, "spec_first_principles_reviewer")
        XCTAssertEqual(seats[1].workerId, "model_sonnet")
        XCTAssertEqual(seats[2].lens, "spec_hype_skeptic")
    }

    func testSeatOverrideReplacesAndExtends() {
        let base = [
            PanelSeat(workerId: "model_opus", lens: "old"),
            PanelSeat(workerId: "model_sonnet", lens: "simplicity"),
        ]
        let overrides = [
            PanelSeat(workerId: "model_opus", lens: "adversary"),
            PanelSeat(workerId: "model_codex", lens: "contracts"),
        ]
        let merged = PanelTeamResolver.applySeatOverrides(base: base, overrides: overrides)
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged[0].lens, "adversary")
        XCTAssertEqual(merged[1].workerId, "model_sonnet")
        XCTAssertEqual(merged[2].workerId, "model_codex")
    }

    func testParseSeatFlag() {
        let seat = PanelTeamResolver.parseSeatFlag("model_opus:adversary")
        XCTAssertEqual(seat?.workerId, "model_opus")
        XCTAssertEqual(seat?.lens, "adversary")
        XCTAssertNil(PanelTeamResolver.parseSeatFlag("no-colon"))
        XCTAssertNil(PanelTeamResolver.parseSeatFlag(":empty"))
    }
}
