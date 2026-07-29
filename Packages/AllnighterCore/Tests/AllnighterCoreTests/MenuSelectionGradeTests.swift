import XCTest
@testable import AllnighterCore

/// MR-S03 — selection-grade menu rows (authored useWhen/dontUseWhen + templates).
final class MenuSelectionGradeTests: XCTestCase {
    private var menu: MenuJSON {
        MenuCatalog.project(teams: BuiltInTeams.all.filter { !$0.isLabTeam })
    }

    func testEveryActionTeamModelRecipeHasAuthoredSelectionCopy() {
        let m = menu
        XCTAssertFalse(m.actions.isEmpty)
        for action in m.actions {
            XCTAssertFalse(action.useWhen.isEmpty, action.id)
            XCTAssertFalse(action.dontUseWhen.isEmpty, action.id)
            XCTAssertNotNil(MenuSelectionCopy.action(action.id), "action \(action.id) not authored")
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(action.useWhen), action.useWhen)
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(action.dontUseWhen), action.dontUseWhen)
        }
        for team in m.teams {
            XCTAssertFalse(team.useWhen.isEmpty, team.id)
            XCTAssertFalse(team.dontUseWhen.isEmpty, team.id)
            XCTAssertNotEqual(team.useWhen, team.displayName, "team \(team.id) useWhen is displayName-only")
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(team.useWhen), team.useWhen)
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(team.dontUseWhen), team.dontUseWhen)
        }
        for model in m.models {
            XCTAssertFalse(model.useWhen.isEmpty, model.id)
            XCTAssertFalse(model.dontUseWhen.isEmpty, model.id)
            XCTAssertNotEqual(model.useWhen, model.displayName, "model \(model.id) useWhen is displayName-only")
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(model.useWhen), model.useWhen)
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(model.dontUseWhen), model.dontUseWhen)
        }
        for recipe in m.recipes {
            XCTAssertFalse(recipe.useWhen.isEmpty, recipe.id)
            XCTAssertFalse(recipe.dontUseWhen.isEmpty, recipe.id)
            XCTAssertNotEqual(recipe.useWhen, recipe.title, "recipe \(recipe.id) useWhen is title-only")
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(recipe.useWhen), recipe.useWhen)
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(recipe.dontUseWhen), recipe.dontUseWhen)
        }
    }

    func testSelectionCopyCoversEveryBuiltInTarget() {
        for team in BuiltInTeams.all where !team.isLabTeam {
            let copy = MenuSelectionCopy.team(
                id: team.id,
                displayName: team.displayName,
                description: team.description,
                mutating: team.mutating
            )
            XCTAssertFalse(MenuSelectionCopy.isBannedStub(copy.dontUseWhen), team.id)
            XCTAssertNotEqual(copy.useWhen, team.displayName, team.id)
            if !team.description.isEmpty {
                XCTAssertNotEqual(
                    copy.useWhen,
                    String(team.description.prefix(MenuSelectionCopy.useWhenMax)),
                    "team \(team.id) appears to use description fallback"
                )
            }
        }
        for def in ModelCatalog.builtIns {
            let copy = MenuSelectionCopy.model(
                id: def.id,
                displayName: def.displayName,
                driverId: def.driverId
            )
            XCTAssertNotEqual(copy.useWhen, def.displayName, def.id)
            XCTAssertFalse(copy.useWhen.hasPrefix("Custom "), "model \(def.id) missing authored copy")
        }
        for recipe in RecipeCatalog.list() {
            let copy = MenuSelectionCopy.recipe(id: recipe.id, title: recipe.title)
            XCTAssertNotEqual(copy.useWhen, recipe.title, recipe.id)
            XCTAssertFalse(copy.dontUseWhen.contains("Custom recipe"), recipe.id)
        }
    }

    func testTemplateVariablesAreDeclaredAndTargetBound() {
        let m = menu
        let declared = MenuSelectionCopy.declaredTemplateVariables
        XCTAssertEqual(
            MenuSelectionCopy.templateVariables(in: m.detailTemplate).subtracting(declared),
            []
        )
        for team in m.teams {
            let runVars = MenuSelectionCopy.templateVariables(in: team.runTemplate)
            let valVars = MenuSelectionCopy.templateVariables(in: team.validateTemplate)
            XCTAssertEqual(runVars.subtracting(declared), [], team.id)
            XCTAssertEqual(valVars.subtracting(declared), [], team.id)
            XCTAssertTrue(runVars.contains("message"), team.id)
            XCTAssertTrue(team.runTemplate.contains("--team \(team.id)"), team.id)
            XCTAssertTrue(team.validateTemplate.contains("--team \(team.id)"), team.id)
            XCTAssertTrue(team.validateTemplate.contains("--dry-run"), team.id)
        }
        for model in m.models {
            let runVars = MenuSelectionCopy.templateVariables(in: model.runTemplate)
            let valVars = MenuSelectionCopy.templateVariables(in: model.validateTemplate)
            XCTAssertEqual(runVars.subtracting(declared), [], model.id)
            XCTAssertEqual(valVars.subtracting(declared), [], model.id)
            XCTAssertTrue(model.runTemplate.contains("--model \(model.id)"), model.id)
            XCTAssertTrue(model.validateTemplate.contains("--model \(model.id)"), model.id)
            XCTAssertTrue(model.validateTemplate.contains("--dry-run"), model.id)
        }
    }

    func testEffectsRefResolvesAndSpendingActionsNameManagementCommands() {
        let m = menu
        for action in m.actions {
            XCTAssertNotNil(m.effectProfiles[action.effectsRef], action.id)
        }
        let run = try! XCTUnwrap(m.actions.first { $0.id == "run" })
        XCTAssertTrue(run.dontUseWhen.contains("teams duplicate"), run.dontUseWhen)
        XCTAssertTrue(run.dontUseWhen.contains("new") || run.dontUseWhen.contains("edit"), run.dontUseWhen)
        let dup = try! XCTUnwrap(m.actions.first { $0.id == "teams duplicate" })
        XCTAssertTrue(dup.dontUseWhen.contains("`run`") || dup.dontUseWhen.contains("run"), dup.dontUseWhen)
        XCTAssertFalse(dup.dontUseWhen.contains("team start"), "cross-verb leak: \(dup.dontUseWhen)")
        let edit = try! XCTUnwrap(m.actions.first { $0.id == "teams edit" })
        XCTAssertTrue(edit.dontUseWhen.contains("`run`") || edit.dontUseWhen.contains("run"), edit.dontUseWhen)
        XCTAssertFalse(edit.dontUseWhen.contains("team start"), "cross-verb leak: \(edit.dontUseWhen)")
        XCTAssertNil(m.actions.first { $0.id == "teams new" }, "teams new is not a menu action")
        XCTAssertNotNil(MenuSelectionCopy.action("teams new"))
        XCTAssertTrue(MenuSelectionCopy.action("teams new")!.useWhen.lowercased().contains("novel")
            || MenuSelectionCopy.action("teams new")!.useWhen.contains("TeamPreset"))
        XCTAssertTrue(MenuSelectionCopy.action("teams duplicate")!.dontUseWhen.contains("run")
            || MenuSelectionCopy.action("teams duplicate")!.dontUseWhen.contains("teams new")
            || MenuSelectionCopy.action("teams duplicate")!.dontUseWhen.contains("novel"))
    }

    func testPerRowBoundsAndBuiltInFixtureStillWithin32KiB() throws {
        let m = menu
        for action in m.actions {
            try MenuSelectionCopy.validateBounds(
                .init(useWhen: action.useWhen, dontUseWhen: action.dontUseWhen),
                kind: "action",
                id: action.id
            )
        }
        for team in m.teams {
            try MenuSelectionCopy.validateBounds(
                .init(useWhen: team.useWhen, dontUseWhen: team.dontUseWhen),
                kind: "team",
                id: team.id
            )
        }
        for model in m.models {
            try MenuSelectionCopy.validateBounds(
                .init(useWhen: model.useWhen, dontUseWhen: model.dontUseWhen),
                kind: "model",
                id: model.id
            )
        }
        for recipe in m.recipes {
            try MenuSelectionCopy.validateBounds(
                .init(useWhen: recipe.useWhen, dontUseWhen: recipe.dontUseWhen),
                kind: "recipe",
                id: recipe.id
            )
        }
        let data = try MenuCatalog.encodeCompact(m)
        XCTAssertLessThanOrEqual(data.count, 32768, "built-in MenuJSON \(data.count) exceeds 32 KiB")
    }

    func testAuthoredBoundsRejectOversizedCustomRecord() {
        let oversized = MenuSelectionCopy.Pair(
            useWhen: String(repeating: "x", count: MenuSelectionCopy.useWhenMax + 1),
            dontUseWhen: "ok"
        )
        XCTAssertThrowsError(try MenuSelectionCopy.validateBounds(oversized, kind: "team", id: "custom_x")) { err in
            guard let bound = err as? MenuSelectionCopy.BoundError,
                  case .useWhenTooLong = bound
            else {
                return XCTFail("expected useWhenTooLong, got \(err)")
            }
        }
    }
}
