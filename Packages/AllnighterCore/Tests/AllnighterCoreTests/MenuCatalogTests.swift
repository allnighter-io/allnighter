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
            + menu.models.map(\.ref)
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
}
