import XCTest
@testable import AllnighterCore

/// Build-time gate: every authored `MenuSelectionCopy` entry must satisfy
/// selection bounds and non-stub rules. Runtime projection degrades over-length
/// strings; this test is the loud fail that replaced the front-door crash.
final class MenuSelectionCopyAuthoredBoundsTests: XCTestCase {
    func testEveryAuthoredEntryWithinBoundsAndNotBannedStub() throws {
        let entries = MenuSelectionCopy.authoredEntries()
        XCTAssertFalse(entries.isEmpty, "authored tables must not be empty")

        var failures: [String] = []
        for entry in entries {
            let use = entry.pair.useWhen.trimmingCharacters(in: .whitespacesAndNewlines)
            let dont = entry.pair.dontUseWhen.trimmingCharacters(in: .whitespacesAndNewlines)
            if use.isEmpty {
                failures.append("\(entry.kind) \(entry.id) useWhen is empty")
            }
            if dont.isEmpty {
                failures.append("\(entry.kind) \(entry.id) dontUseWhen is empty")
            }
            if use.count > MenuSelectionCopy.useWhenMax {
                failures.append(
                    "\(entry.kind) \(entry.id) useWhen length \(use.count) > \(MenuSelectionCopy.useWhenMax)"
                )
            }
            if dont.count > MenuSelectionCopy.dontUseWhenMax {
                failures.append(
                    "\(entry.kind) \(entry.id) dontUseWhen length \(dont.count) > \(MenuSelectionCopy.dontUseWhenMax)"
                )
            }
            if MenuSelectionCopy.isBannedStub(use) {
                failures.append("\(entry.kind) \(entry.id) useWhen is banned stub: \(use)")
            }
            if MenuSelectionCopy.isBannedStub(dont) {
                failures.append("\(entry.kind) \(entry.id) dontUseWhen is banned stub: \(dont)")
            }
            // Also exercise validateBounds for a single structured error path.
            do {
                try MenuSelectionCopy.validateBounds(entry.pair, kind: entry.kind, id: entry.id)
            } catch {
                // Already recorded length/empty above; keep message if somehow distinct.
                let text = "\(error)"
                if !failures.contains(where: { text.contains($0) || $0.contains(entry.id) }) {
                    failures.append(text)
                }
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "authored MenuSelectionCopy bounds/stub failures:\n" + failures.joined(separator: "\n")
        )
    }

    /// Calling `project()` must not crash the front door (the Luna typo used to).
    func testMenuCatalogProjectCompletesForBuiltInCatalog() {
        // Selection prose is `--detailed` only after the stage-1 menu slimming,
        // so a bounds check on that prose must project the tier that carries it.
        let menu = MenuCatalog.project(teams: BuiltInTeams.all.filter { !$0.isLabTeam }, detailed: true)
        XCTAssertFalse(menu.models.isEmpty)
        XCTAssertFalse(menu.teams.isEmpty)
        XCTAssertFalse(menu.actions.isEmpty)
        XCTAssertFalse(menu.recipes.isEmpty)
        // Stage 3: models carry no authored selection prose, so there is no
        // per-model bound left to grade here. Team and recipe copy is still
        // graded by the assertions above.
    }

    func testProjectedBoundsOverLongAuthoredCopyWithoutThrowing() {
        let oversized = MenuSelectionCopy.Pair(
            useWhen: String(repeating: "a", count: MenuSelectionCopy.useWhenMax + 10),
            dontUseWhen: String(repeating: "b", count: MenuSelectionCopy.dontUseWhenMax + 10)
        )
        let projected = MenuSelectionCopy.projected(oversized)
        XCTAssertEqual(projected.useWhen.count, MenuSelectionCopy.useWhenMax)
        XCTAssertEqual(projected.dontUseWhen.count, MenuSelectionCopy.dontUseWhenMax)
        XCTAssertTrue(projected.useWhen.hasSuffix("…"))
        XCTAssertTrue(projected.dontUseWhen.hasSuffix("…"))
        XCTAssertNoThrow(
            try MenuSelectionCopy.validateBounds(projected, kind: "model", id: "oversized_fixture")
        )
    }
}
