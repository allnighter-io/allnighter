import XCTest
@testable import AllnighterCore

final class MenuCatalogTests: XCTestCase {
    func testCompletenessAndTruncated() throws {
        let menu = MenuCatalog.project()
        XCTAssertFalse(menu.truncated)
        XCTAssertTrue(menu.completeness.actions.complete)
        XCTAssertTrue(menu.completeness.commands.complete)
        XCTAssertTrue(menu.completeness.teams.complete)
        XCTAssertTrue(menu.completeness.models.complete)
        XCTAssertTrue(menu.completeness.recipes.complete)
        XCTAssertTrue(menu.completeness.effectProfiles.complete)
        XCTAssertEqual(menu.completeness.actions.count, menu.actions.count)
        XCTAssertEqual(menu.completeness.commands.count, menu.commands.count)
        XCTAssertEqual(menu.completeness.teams.count, menu.teams.count)
        XCTAssertEqual(menu.completeness.models.count, menu.models.count)
        XCTAssertEqual(menu.completeness.recipes.count, menu.recipes.count)
        XCTAssertEqual(menu.completeness.effectProfiles.count, menu.effectProfiles.count)
    }

    func testUniqueRefsAcrossKinds() {
        let menu = MenuCatalog.project()
        let refs =
            menu.commands.map(\.ref)
            + menu.teams.map(\.ref)
            + menu.models.map { "model:\($0.id)" }   // Tier-1 omits ref; it is derivable
            + menu.recipes.map(\.ref)
        XCTAssertEqual(refs.count, Set(refs).count, "duplicate menu refs")
    }

    func testDeterministicOrdering() {
        let menu = MenuCatalog.project()
        XCTAssertEqual(menu.commands.map(\.name), menu.commands.map(\.name).sorted())
        XCTAssertEqual(menu.teams.map(\.id), menu.teams.map(\.id).sorted())
        XCTAssertEqual(menu.models.map(\.id), menu.models.map(\.id).sorted())
        XCTAssertEqual(menu.recipes.map(\.id), menu.recipes.map(\.id).sorted())
    }

    func testEveryPublicM1CommandAppears() {
        let menu = MenuCatalog.project()
        let publicNames = Set(
            ContractRegistry.milestone1.commands
                .filter { $0.milestone == .m1 && $0.visibility == .public }
                .map(\.name)
        )
        XCTAssertEqual(Set(menu.commands.map(\.name)), publicNames)
        XCTAssertTrue(menu.commands.contains { $0.ref == "command:run" })
        XCTAssertTrue(menu.commands.contains { $0.ref == "command:teams.duplicate" })
        XCTAssertTrue(menu.commands.contains { $0.ref == "command:menu" })
        XCTAssertTrue(menu.commands.contains { $0.ref == "command:menu.show" })
    }

    func testActionsMatchTaggedMenuActionCommands() {
        let menu = MenuCatalog.project()
        let tagged = ContractRegistry.milestone1.commands
            .filter { $0.milestone == .m1 && $0.visibility == .public && $0.menuAction }
            .map(\.name)
            .sorted()
        XCTAssertEqual(menu.actions.map(\.id).sorted(), tagged)
        let commandNames = Set(menu.commands.map(\.name))
        for action in menu.actions {
            XCTAssertTrue(commandNames.contains(action.id), "action \(action.id) missing command row")
        }
        XCTAssertTrue(tagged.contains("run"))
        XCTAssertTrue(tagged.contains("teams duplicate"))
        XCTAssertTrue(tagged.contains("teams edit"))
    }

    func testEveryEffectiveTeamModelRecipeAppears() {
        let menu = MenuCatalog.project()
        let expectedTeams = Set(TeamCatalog.all.filter { !$0.isLabTeam }.map(\.id))
        XCTAssertEqual(Set(menu.teams.map(\.id)), expectedTeams)
        XCTAssertEqual(
            Set(menu.models.map(\.id)),
            Set(ModelCatalog.list().filter { ModelCatalog.isEnabled($0.id) }.map(\.id)))
        XCTAssertEqual(Set(menu.recipes.map(\.id)), Set(RecipeCatalog.list().map(\.id)))
        for cmd in menu.commands {
            XCTAssertNotNil(menu.effectProfiles[cmd.effectsRef], "command \(cmd.name) effectsRef dangling")
        }
        for action in menu.actions {
            XCTAssertNotNil(menu.effectProfiles[action.effectsRef], "action \(action.id) effectsRef dangling")
        }
        XCTAssertTrue(
            menu.teams.contains { $0.ref == menu.defaults.defaultTeamRef },
            "defaults.defaultTeamRef missing from teams"
        )
    }

    func testBuiltInFixtureEncodeWithin32KiB() throws {
        let menu = MenuCatalog.project(teams: BuiltInTeams.all.filter { !$0.isLabTeam })
        let data = try MenuCatalog.encodeCompact(menu)
        // Measured 2026-08-05: 34,644 B with seven default-on OpenCode Go seats.
        XCTAssertLessThanOrEqual(data.count, 36096, "MenuJSON encode size \(data.count) exceeds 35.25 KiB")
    }

    func testShowHydratesKnownRefs() throws {
        let run = try MenuCatalog.show(ref: "command:run")
        XCTAssertEqual(run.kind, "command")
        XCTAssertEqual(run.command?.name, "run")
        XCTAssertFalse(try XCTUnwrap(run.command).mutuallyExclusiveFlags.isEmpty)
        XCTAssertFalse(try XCTUnwrap(run.command).flagConstraints.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(run.command?.flags.first(where: { $0.name == "effort" })?.allowedValues),
            ["low", "med", "high"]
        )

        let team = try MenuCatalog.show(ref: "team:code_growth")
        XCTAssertEqual(team.kind, "team")
        XCTAssertEqual(team.team?.id, "code_growth")

        let menu = MenuCatalog.project()
        let modelId = try XCTUnwrap(
            menu.models.first(where: { $0.id == "model_sonnet" })?.id
                ?? menu.models.first?.id
        )
        let model = try MenuCatalog.show(ref: "model:\(modelId)")
        XCTAssertEqual(model.kind, "model")
        XCTAssertEqual(model.model?.id, modelId)

        let recipeId = try XCTUnwrap(menu.recipes.first?.id)
        let recipe = try MenuCatalog.show(ref: "recipe:\(recipeId)")
        XCTAssertEqual(recipe.kind, "recipe")
        XCTAssertEqual(recipe.recipe?.id, recipeId)
        XCTAssertFalse(try XCTUnwrap(recipe.recipe).markdown.isEmpty)
    }

    func testUnknownRefFailsWithSameKindSuggestions() {
        do {
            _ = try MenuCatalog.show(ref: "team:not_a_real_team_zzz")
            XCTFail("expected MenuRefError")
        } catch let error as MenuRefError {
            XCTAssertEqual(error.kind, "team")
            XCTAssertFalse(error.suggestions.isEmpty)
            XCTAssertTrue(error.suggestions.allSatisfy { $0.hasPrefix("team:") })
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCatalogRevisionStableThenChanges() throws {
        let a = MenuCatalog.project()
        let b = MenuCatalog.project()
        XCTAssertEqual(a.catalogRevision, b.catalogRevision)

        let teams = TeamCatalog.all.filter { !$0.isLabTeam }
        guard let first = teams.first else {
            XCTFail("no teams"); return
        }
        // Revision covers id:active + model enabled/ready + recipe ids — flip active via visibility override.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("menu-rev-\(UUID().uuidString).json")
        TeamVisibility.overrideForTesting(file: tmp)
        defer { TeamVisibility.overrideForTesting(file: nil) }
        try TeamVisibility.setEnabled(first.id, false)
        let c = MenuCatalog.project(teams: teams)
        XCTAssertNotEqual(a.catalogRevision, c.catalogRevision)
    }

    // MARK: - Tier-1 vs --detailed (menu slimming, stage 1)

    private func seat(_ id: String, enabled: Bool) -> ModelListJSON.Entry {
        ModelListJSON.Entry(
            id: id, displayName: id, modelLabel: id,
            driverId: "claude_code", driverName: "claude_code",
            role: "answer", origin: "custom",
            enabled: enabled, ready: true,
            status: "ready", state: enabled ? "onBench" : "offBench",
            capabilities: ModelCapabilities()
        )
    }

    /// Tier-1 is the hot path — teaching rule 1 sends every agent here before
    /// first spend. It carries what SELECTION needs and nothing else.
    func testTierOneOmitsDerivableRefAndAdvisoryProse() throws {
        let menu = MenuCatalog.project(
            teams: BuiltInTeams.all.filter { !$0.isLabTeam },
            modelEntries: [seat("model_a", enabled: true)]
        )
        let m = try XCTUnwrap(menu.models.first)
        XCTAssertNil(m.ref, "ref is \"model:\" + id — derivable, so not information")
        XCTAssertNil(m.useWhen)
        XCTAssertNil(m.dontUseWhen)
        // The worked example must stay in front of the caller: this surface
        // teaches by example, and that is not what stage 1 trades away.
        XCTAssertFalse(m.runTemplate.isEmpty)
        XCTAssertFalse(m.validateTemplate.isEmpty)
        XCTAssertTrue(m.runTemplate.contains("model_a"))
    }

    /// An off-bench seat is not selectable, so Tier-1 summarises it — but never
    /// silently. Without the breadcrumb an agent told to use an off-bench id
    /// finds nothing and either invents an id or reports the tool broken.
    func testTierOneOmitsOffBenchSeatsButSaysSo() throws {
        let menu = MenuCatalog.project(
            teams: BuiltInTeams.all.filter { !$0.isLabTeam },
            modelEntries: [seat("model_on", enabled: true), seat("model_off", enabled: false)]
        )
        XCTAssertEqual(menu.models.map(\.id), ["model_on"])
        let blocked = try XCTUnwrap(menu.blocked, "omitted seats must be announced")
        XCTAssertEqual(blocked.count, 1)
        XCTAssertEqual(blocked.see, "alln models")
    }

    func testDetailedRestoresRefProseAndOffBenchSeats() throws {
        let menu = MenuCatalog.project(
            teams: BuiltInTeams.all.filter { !$0.isLabTeam },
            modelEntries: [seat("model_on", enabled: true), seat("model_off", enabled: false)],
            detailed: true
        )
        XCTAssertEqual(menu.models.count, 2, "--detailed lists off-bench seats too")
        XCTAssertNil(menu.blocked, "nothing was omitted, so nothing to announce")
        let m = try XCTUnwrap(menu.models.first)
        XCTAssertEqual(m.ref, "model:\(m.id)")
        XCTAssertNotNil(m.useWhen)
        XCTAssertNotNil(m.dontUseWhen)
    }

    func testTierOneIsSmallerThanDetailed() throws {
        let seats = (0..<12).map { seat("model_\($0)", enabled: true) }
        let teams = BuiltInTeams.all.filter { !$0.isLabTeam }
        let tier1 = try MenuCatalog.encodeCompact(
            MenuCatalog.project(teams: teams, modelEntries: seats)).count
        let full = try MenuCatalog.encodeCompact(
            MenuCatalog.project(teams: teams, modelEntries: seats, detailed: true)).count
        XCTAssertLessThan(tier1, full, "Tier-1 must actually be the cheaper payload")
    }

}
