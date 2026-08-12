import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// ONB-S02b: Application Support mirror of bundled recipe cards.
final class RecipeInstallMirrorTests: XCTestCase {

    func testSyncWritesBundledRecipesIntoDestination() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-recipe-mirror-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let dest = scratch.appendingPathComponent("Recipes", isDirectory: true)

        XCTAssertFalse(RecipeCatalog.list().isEmpty, "Core bundle must ship recipes")
        let written = try XCTUnwrap(RecipeInstallMirror.sync(to: dest))
        XCTAssertEqual(written.path, dest.path)

        let mirrored = try FileManager.default.contentsOfDirectory(
            at: dest,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }
        XCTAssertEqual(mirrored.count, RecipeCatalog.list().count)

        for recipe in RecipeCatalog.list() {
            let file = dest.appendingPathComponent("\(recipe.id).md")
            let body = try String(contentsOf: file, encoding: .utf8)
            XCTAssertEqual(body, recipe.markdown)
        }
    }

    func testSyncOverwritesStaleMirrorFiles() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-recipe-mirror-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let dest = scratch.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let first = try XCTUnwrap(RecipeCatalog.list().first)
        let stale = dest.appendingPathComponent("\(first.id).md")
        try "STALE".write(to: stale, atomically: true, encoding: .utf8)

        _ = RecipeInstallMirror.sync(to: dest)
        let body = try String(contentsOf: stale, encoding: .utf8)
        XCTAssertEqual(body, first.markdown)
        XCTAssertNotEqual(body, "STALE")
    }

    func testSyncRemovesRetiredRecipeFiles() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-recipe-mirror-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let dest = scratch.appendingPathComponent("Recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let orphan = dest.appendingPathComponent("retired-old-recipe.md")
        try "gone".write(to: orphan, atomically: true, encoding: .utf8)

        _ = try XCTUnwrap(RecipeInstallMirror.sync(to: dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testDirectoryURLIsUnderApplicationSupportRecipes() {
        let supportRoot = AllnighterPaths.support.standardizedFileURL
        let directory = RecipeInstallMirror.directoryURL.standardizedFileURL
        let expected = AllnighterPaths.recipes.standardizedFileURL

        XCTAssertEqual(
            directory,
            expected,
            "recipes mirror must resolve to AllnighterPaths.recipes; got \(directory.path)"
        )
        XCTAssertEqual(
            directory.lastPathComponent,
            "Recipes",
            "recipes mirror must use the Recipes path component"
        )
        XCTAssertTrue(
            directory.path.hasPrefix(supportRoot.path + "/"),
            "recipes mirror must sit under the one resolved support root; got \(directory.path)"
        )
        // Under XCTest the shared root is the process test redirect (test/real-state
        // seam), not the real Application Support tree.
        XCTAssertTrue(
            AllnighterSupportRoot.isTestSupportRedirectActive,
            "XCTest must activate the support-root redirect"
        )
    }

    func testBlurbExtractsIntentSubtitle() {
        let md = """
        # Get another model to implement this

        You hold the PM seat; Allnighter runs the crew.

        ## Example utterances
        """
        XCTAssertEqual(
            RecipeInstallMirror.blurb(from: md),
            "You hold the PM seat; Allnighter runs the crew."
        )
    }
}
