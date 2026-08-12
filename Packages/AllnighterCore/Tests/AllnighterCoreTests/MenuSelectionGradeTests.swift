import XCTest
@testable import AllnighterCore

/// MR-S03 — selection-grade menu rows (authored useWhen/dontUseWhen + templates).
final class MenuSelectionGradeTests: XCTestCase {

    // Founder ruling 2026-08-12: "Expand the seat budget. If founder asks to
    // add models we expand." ASR-S07 ("25600 is untouched; trimming copy is
    // the get-to-green move") is overruled. The budget follows the bench.
    //
    // Per-seat MenuJSON cost from the two Grok 4.6 additions
    // (`model_grok_46`, `model_cursor_grok_46`):
    //   built-in  25,183 → 25,956 B  (+773 B / 2 seats = 387 B/seat)
    //   realistic 28,014 → 28,788 B  (+774 B / 2 seats = 387 B/seat)
    // Ceilings sized for ≥8 more seats at that cost, then rounded to a KiB
    // boundary (30 KiB / 32 KiB). A normal model addition must not turn the
    // wall red. Do not "fix" a future miss by cutting authored copy.
    private static let builtInTier1MenuBudgetBytes = 30_720
    private static let realisticTier1MenuBudgetBytes = 32_768

    /// Selection PROSE lives in `--detailed` after the stage-1 menu slimming, so
    /// every grading test below must project that tier to see it.
    private var menu: MenuJSON {
        MenuCatalog.project(teams: BuiltInTeams.all.filter { !$0.isLabTeam }, detailed: true)
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
        // Stage 3: models carry no authored selection prose. What a seat is
        // FOR is a catalog fact, so that is what gets graded now. Team and
        // recipe copy is still authored and still graded, above and below.
        for model in m.models {
            XCTAssertFalse(model.id.isEmpty)
            XCTAssertFalse(model.driverId.isEmpty, "every seat names its owning CLI")
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
            let runVars = MenuSelectionCopy.templateVariables(in: team.runTemplate ?? "")
            let valVars = MenuSelectionCopy.templateVariables(in: team.validateTemplate ?? "")
            XCTAssertEqual(runVars.subtracting(declared), [], team.id)
            XCTAssertEqual(valVars.subtracting(declared), [], team.id)
            XCTAssertTrue(runVars.contains("message"), team.id)
            XCTAssertTrue((team.runTemplate ?? "").contains("--team \(team.id)"), team.id)
            XCTAssertTrue((team.validateTemplate ?? "").contains("--team \(team.id)"), team.id)
            XCTAssertTrue((team.validateTemplate ?? "").contains("--dry-run"), team.id)
        }
        for model in m.models {
            let runVars = MenuSelectionCopy.templateVariables(in: model.runTemplate ?? "")
            let valVars = MenuSelectionCopy.templateVariables(in: model.validateTemplate ?? "")
            XCTAssertEqual(runVars.subtracting(declared), [], model.id)
            XCTAssertEqual(valVars.subtracting(declared), [], model.id)
            XCTAssertTrue((model.runTemplate ?? "").contains("--model \(model.id)"), model.id)
            XCTAssertTrue((model.validateTemplate ?? "").contains("--model \(model.id)"), model.id)
            XCTAssertTrue((model.validateTemplate ?? "").contains("--dry-run"), model.id)
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

    /// Duplicate-to-edit built-in teams into `custom_` overlay rows (mirrors
    /// `TeamPreset.duplicated`, the real path a saved custom team takes).
    private func customTeams(from builtIns: [TeamPreset], count: Int) -> [TeamPreset] {
        (0..<count).map { i in
            builtIns[i % builtIns.count].duplicated(newId: "custom_team_\(i)", newName: "Custom Team \(i)")
        }
    }

    /// Custom model rows in the same shape `builtInModelEntries()` (MenuCatalog.swift)
    /// produces for built-ins, but with `custom_`-prefixed ids — the real overlay shape.
    private func customModelEntries(from defs: [ModelDefinition], count: Int) -> [ModelListJSON.Entry] {
        (0..<count).map { i in
            let def = defs[i % defs.count]
            return ModelListJSON.Entry(
                id: "custom_\(def.driverId)_variant_\(i)",
                displayName: "Custom \(def.displayName) Variant \(i)",
                modelLabel: def.modelLabel,
                driverId: def.driverId,
                driverName: def.driverId,
                role: def.role.rawValue,
                origin: "custom",
                enabled: true,
                ready: false,
                status: "notChecked",
                state: "onBench",
                capabilities: def.capabilities
            )
        }
    }

    /// A realistic projection: built-ins plus a representative slice of `custom_`
    /// overlay teams and models (id-prefixed, full useWhen/dontWhen/templates —
    /// the shape a real bench with saved customs actually sends over the wire).
    private func realisticMenu(detailed: Bool = false) -> MenuJSON {
        let builtInTeams = BuiltInTeams.all.filter { !$0.isLabTeam }
        let builtInModels = ModelCatalog.list()
        let teams = builtInTeams + customTeams(from: builtInTeams, count: 6)
        let modelEntries = builtInModels.map { def in
            ModelListJSON.Entry(
                id: def.id,
                displayName: def.displayName,
                modelLabel: def.modelLabel,
                driverId: def.driverId,
                driverName: def.driverId,
                role: def.role.rawValue,
                origin: def.origin.rawValue,
                enabled: ModelCatalog.isEnabled(def.id),
                ready: false,
                status: "notChecked",
                state: ModelCatalog.isEnabled(def.id) ? "onBench" : "available",
                capabilities: ModelCatalog.capabilities(def.id)
            )
        }.filter(\.enabled) + customModelEntries(from: builtInModels, count: 6)
        return MenuCatalog.project(teams: teams, modelEntries: modelEntries, detailed: detailed)
    }

    func testPerRowBoundsAndBuiltInFixtureWithinBudget() throws {
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
        // No authored model copy left to bound-check (stage 3).
        for recipe in m.recipes {
            try MenuSelectionCopy.validateBounds(
                .init(useWhen: recipe.useWhen, dontUseWhen: recipe.dontUseWhen),
                kind: "recipe",
                id: recipe.id
            )
        }
        let data = try MenuCatalog.encodeCompact(
            MenuCatalog.project(teams: BuiltInTeams.all.filter { !$0.isLabTeam }))
        // Total-payload gate for the built-in-only fixture. Per-row
        // `validateBounds` above stays tight (one bloated useWhen/dontUseWhen
        // is the real risk). This ceiling exists to catch runaway growth
        // (catalog duplicated, a row repeated per model) — not routine seat
        // additions. Founder ruling 2026-08-12 raised it from 25 KiB after
        // Grok 4.6; see the class-level constants for the measured 387 B/seat
        // and the 8-seat headroom math. 25,956 B measured; 30 KiB fits ~12
        // further seats at that cost.
        XCTAssertLessThanOrEqual(
            data.count,
            Self.builtInTier1MenuBudgetBytes,
            "built-in Tier-1 MenuJSON \(data.count) exceeds \(Self.builtInTier1MenuBudgetBytes) B budget"
        )
    }

    func testPerRowBoundsAndRealisticCatalogWithinBudget() throws {
        // Two concerns, two tiers. Per-row PROSE bounds can only be checked where
        // the prose exists (`--detailed`); the size BUDGET must gate what agents
        // actually receive (Tier-1). Measuring the budget on `--detailed` would
        // gate a payload nobody is served by default.
        let m = realisticMenu(detailed: true)
        for team in m.teams {
            try MenuSelectionCopy.validateBounds(
                .init(useWhen: team.useWhen, dontUseWhen: team.dontUseWhen),
                kind: "team",
                id: team.id
            )
        }
        // No authored model copy left to bound-check (stage 3).
        let data = try MenuCatalog.encodeCompact(realisticMenu())
        // Total-payload gate for the realistic (built-ins + 6 custom teams +
        // 6 custom models) fixture — the closer stand-in for a live bench.
        // Per-row `validateBounds` above stays tight. This ceiling catches
        // runaway growth, not a normal model addition. Founder ruling
        // 2026-08-12 raised it from 28 KiB after Grok 4.6; see the class-level
        // constants. 28,788 B measured; 32 KiB fits ~10 further seats at
        // 387 B/seat.
        XCTAssertLessThanOrEqual(
            data.count,
            Self.realisticTier1MenuBudgetBytes,
            "realistic Tier-1 MenuJSON \(data.count) exceeds \(Self.realisticTier1MenuBudgetBytes) B budget"
        )
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
