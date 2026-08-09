import XCTest
@testable import AllnighterCore

/// MR-S03 — selection-grade menu rows (authored useWhen/dontUseWhen + templates).
final class MenuSelectionGradeTests: XCTestCase {
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

    func testPerRowBoundsAndBuiltInFixtureStillWithin25KiB() throws {
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
        // Measured 2026-08-05: built-in-only fixture compacts to 34,644 B after seven
        // default-on OpenCode Go seats. Live bench (built-ins + real saved customs)
        // compacts higher. The built-in fixture alone is not the surface QABC gates —
        // see testPerRowBoundsAndRealisticCatalogWithinBudget below — but a tight
        // ceiling here (~4% headroom over the measured value) still catches
        // built-in bloat (new team/model/recipe authored copy) early.
        // Tier-1 built-in fixture measures 32,168 B after the stage-1 slimming
        // (was 36,934 B when this gated the pre-slim payload). Tightened rather
        // than left slack: a budget above what ships stops gating growth.
        // PF-S01 (2026-08-08): every model row gained `freshness`
        // (checkedAt/ageMinutes/stale/evidenceSource/nextAction) — disclosure
        // the Works Test requires on Tier-1, not `--detailed`-only. Measured
        // 30,113 B; budget moved to 30 KiB (30,720 B), ~2% headroom.
        // PF-S04 (2026-08-09): a model is never independently probed, so every
        // model row was copying its driver's `freshness` object verbatim —
        // measured 29 objects, only 9 distinct values. Model rows now carry
        // only the decision bit (`stale`); the full disclosure stays once, on
        // the driver row, reachable via the model row's existing `driverId`.
        // Measured 25,183 B; budget lowered to 25 KiB (25,600 B), ~1.7%
        // headroom — a budget left at the old value would stop gating growth.
        XCTAssertLessThanOrEqual(data.count, 25600, "built-in Tier-1 MenuJSON \(data.count) exceeds 25 KiB")
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
        // Budget derivation (QABC-S00a, 2026-07-31): the built-in-only fixture
        // that `testPerRowBoundsAndBuiltInFixtureStillWithin25KiB` gates does
        // NOT protect the real agent-facing surface — live `alln menu --json`
        // on this bench compacts to 35,027 B, above the old 32 KiB gate, and
        // that weight is legitimate: runTemplate+validateTemplate across every
        // model and team are 8,196 B (23%) so a cold agent can copy an exact
        // command instead of constructing one — do not trim them. QABC-S00b
        // adds a capacity decision row (~562 B compact). 40 KiB (40,960 B)
        // covers the measured 35,027 B live bench plus the S00b capacity row
        // plus headroom for a realistic number of saved custom teams/models,
        // without being so loose it stops gating growth.
        // PF-S01 (2026-08-08): `freshness` on every model row. Measured
        // 33,964 B; budget moved to 34 KiB (34,816 B), ~2.5% headroom.
        // PF-S04 (2026-08-09): model rows normalize `freshness` down to a
        // single inline `stale` boolean (see the sibling test above for the
        // measured duplication this removes); driver rows are unchanged.
        // Measured 28,014 B; budget lowered to 28 KiB (28,672 B), ~2.3%
        // headroom.
        XCTAssertLessThanOrEqual(data.count, 28672, "realistic Tier-1 MenuJSON \(data.count) exceeds 28 KiB budget")
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
