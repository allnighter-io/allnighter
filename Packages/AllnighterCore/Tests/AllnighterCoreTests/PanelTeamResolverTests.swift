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
                id: "code_plan", displayName: "Plan", lane: .code,
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
        XCTAssertTrue(formatted.contains("code_plan"))
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
        XCTAssertEqual(seat?.alias, "model_opus")
        XCTAssertEqual(seat?.lens, "adversary")
        XCTAssertNil(PanelTeamResolver.parseSeatFlag("no-colon"))
        XCTAssertNil(PanelTeamResolver.parseSeatFlag(":empty"))
    }

    private func model(_ id: String, name: String, driver: String = "claude_code", enabled: Bool = true) -> Model {
        Model(id: id, displayName: name, modelLabel: name.lowercased(), driverId: driver, role: .both, enabled: enabled)
    }

    func testResolveSeatAliasPrefersEnabledUnique() {
        let models = [
            model("model_agy_sonnet", name: "Claude Sonnet 4.6", driver: "antigravity", enabled: false),
            model("model_sonnet", name: "Sonnet 4.6", enabled: true),
        ]
        XCTAssertEqual(
            try PanelTeamResolver.resolveSeatAlias("sonnet", models: models).get(),
            "model_sonnet"
        )
    }

    func testResolveSeatAliasFallsBackToFullCatalogForOffBench() {
        let models = [
            model("model_sonnet", name: "Sonnet 4.6", enabled: true),
            model("model_cursor_grok_45", name: "Cursor Grok 4.5", driver: "cursor_agent", enabled: false),
        ]
        XCTAssertEqual(
            try PanelTeamResolver.resolveSeatAlias("cursor_grok", models: models).get(),
            "model_cursor_grok_45"
        )
    }

    func testResolveSeatAliasExactDisplayNamePrefersEnabled() {
        let models = [
            model("model_cursor_grok_45", name: "Cursor Grok 4.5", driver: "cursor_agent", enabled: false),
            model("model_grok", name: "Grok 4.5", driver: "grok", enabled: true),
        ]
        XCTAssertEqual(
            try PanelTeamResolver.resolveSeatAlias("grok 4.5", models: models).get(),
            "model_grok"
        )
    }

    func testResolveSeatAliasPrefersStrongerWhenMultipleEnabledMatch() {
        // model_sonnet (rank 80) beats unranked AGY Sonnet; same policy as pilot.
        let models = [
            model("model_sonnet", name: "Sonnet 4.6", enabled: true),
            model("model_agy_sonnet", name: "AGY Sonnet", driver: "antigravity", enabled: true),
        ]
        XCTAssertEqual(
            try PanelTeamResolver.resolveSeatAlias("sonnet", models: models).get(),
            "model_sonnet"
        )
    }

    func testResolveSeatAliasOpusPrefersClaude48OverAgy() {
        let models = [
            model("model_agy_opus", name: "Claude Opus 4.6", driver: "antigravity", enabled: true),
            model("model_opus", name: "Opus 4.8", enabled: true),
        ]
        XCTAssertEqual(
            try PanelTeamResolver.resolveSeatAlias("opus", models: models).get(),
            "model_opus"
        )
    }

    func testResolveSeatAliasAmbiguousWhenRanksTieAmongEnabled() {
        let models = [
            model("model_custom_a", name: "Custom Alpha", driver: "codex", enabled: true),
            model("model_custom_b", name: "Custom Alpha Plus", driver: "codex", enabled: true),
        ]
        let result = PanelTeamResolver.resolveSeatAlias("alpha", models: models)
        guard case .failure(.ambiguous(let alias, let candidates)) = result else {
            return XCTFail("expected ambiguous, got \(result)")
        }
        XCTAssertEqual(alias, "alpha")
        XCTAssertEqual(candidates.map(\.id).sorted(), ["model_custom_a", "model_custom_b"])
    }

    func testResolveSeatAliasUnknownListsReadyViaNoMatch() {
        let models = [
            model("model_sonnet", name: "Sonnet 4.6", enabled: true),
        ]
        let result = PanelTeamResolver.resolveSeatAlias("nope", models: models)
        guard case .failure(.noMatch(let alias, let ready)) = result else {
            return XCTFail("expected noMatch, got \(result)")
        }
        XCTAssertEqual(alias, "nope")
        XCTAssertEqual(ready.map(\.id), ["model_sonnet"])
    }

    func testResolveSeatFlagStoresResolvedModelIdNotAlias() {
        let models = [model("model_sonnet", name: "Sonnet 4.6")]
        guard case .success(let seat)? = PanelTeamResolver.resolveSeatFlag(
            "sonnet:failure-modes", models: models
        ) else {
            return XCTFail("expected resolved seat")
        }
        XCTAssertEqual(seat.workerId, "model_sonnet")
        XCTAssertEqual(seat.lens, "failure-modes")
        XCTAssertNotEqual(seat.workerId, "sonnet")
    }

    func testValidateRosterUnknownModel() {
        let seats = [PanelSeat(workerId: "model_missing", lens: "x")]
        let models = [model("model_sonnet", name: "Sonnet")]
        let registry = DriverRegistry([
            // minimal: any manifest id matching driver
        ])
        // Empty registry — still unknown model first.
        let result = PanelTeamResolver.validateRoster(seats: seats, models: models, registry: registry)
        guard case .failure(.unknownModel(let workerId, let modelId)) = result else {
            return XCTFail("expected unknownModel, got \(result)")
        }
        XCTAssertEqual(workerId, "model_missing")
        XCTAssertEqual(modelId, "model_missing")
    }

    func testValidateRosterKnownModelWithDriverPasses() throws {
        let seats = [PanelSeat(workerId: "model_sonnet", lens: "x")]
        let models = [model("model_sonnet", name: "Sonnet")]
        let manifest = DriverManifest(
            id: "claude_code", displayName: "Claude", kind: .headlessCLI,
            invoke: .init(command: "claude", args: ["-p", "{{prompt}}"])
        )
        let registry = DriverRegistry([manifest])
        XCTAssertNoThrow(try PanelTeamResolver.validateRoster(
            seats: seats, models: models, registry: registry
        ).get())
    }
}
