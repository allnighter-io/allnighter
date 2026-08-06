import XCTest
@testable import AllnighterCore

/// ONB-S02a: shipped recipe `.md` SSOT + teaching-snippet drift gate.
final class RecipeCatalogTests: XCTestCase {
    func testBundledRecipeCountAtLeastSix() {
        let recipes = RecipeCatalog.list()
        XCTAssertGreaterThanOrEqual(recipes.count, 6, "expected ≥6 intent recipe cards, got \(recipes.count)")
        XCTAssertNotNil(RecipeCatalog.bundledDirectoryURL, "Recipes subdirectory missing from Bundle.module")
    }

    func testEveryRecipeEmbedsCurrentTeachingSnippet() {
        let wrap = TeachingSnippet.wrap()
        let hashMarker = "hash=\(TeachingSnippet.contentHash)"
        for recipe in RecipeCatalog.list() {
            XCTAssertTrue(
                recipe.markdown.contains(wrap),
                "recipe \(recipe.id) must carry the composed TeachingSnippet.wrap() block"
            )
            XCTAssertTrue(
                recipe.markdown.contains(hashMarker),
                "recipe \(recipe.id) teaching hash drifted"
            )
            XCTAssertFalse(
                recipe.markdown.contains(RecipeCatalog.teachingPlaceholder),
                "recipe \(recipe.id) shipped an unsubstituted teaching placeholder"
            )
        }
    }

    /// The anti-drift gate. A source card that stores its own copy of the block
    /// can go stale; a card that stores a placeholder cannot. Composition is
    /// what makes `TeachingSnippet` the single definition, so forbid the
    /// literal at the only layer that could reintroduce it.
    func testSourceCardsStoreAPlaceholderNotACopyOfTheBlock() throws {
        let dir = try XCTUnwrap(RecipeCatalog.bundledDirectoryURL)
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "md" }
        XCTAssertGreaterThanOrEqual(urls.count, 6)

        for url in urls {
            let source = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent
            XCTAssertFalse(
                source.contains(TeachingSnippet.openMarkerPrefix),
                "\(name) hand-copies the teaching block — use \(RecipeCatalog.teachingPlaceholder) instead"
            )
            XCTAssertFalse(
                source.contains(TeachingSnippet.closeMarker),
                "\(name) hand-copies the teaching block — use \(RecipeCatalog.teachingPlaceholder) instead"
            )
            XCTAssertTrue(
                source.contains(RecipeCatalog.teachingPlaceholder),
                "\(name) is missing the teaching placeholder"
            )
        }
    }

    /// Composition must be inert on a card that never asked for a block.
    func testComposeLeavesCardsWithoutAPlaceholderUntouched() {
        let plain = "# Title\n\nNo teaching here.\n"
        XCTAssertEqual(RecipeCatalog.compose(plain), plain)
    }

    func testTitlesAreIntentShaped() {
        let recipes = RecipeCatalog.list()
        XCTAssertFalse(recipes.isEmpty)
        // Spot-check: H1 titles are user-intent phrases, not lone product nouns.
        let byId = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) })
        XCTAssertEqual(byId["get-another-model-to-implement-this"], "Get another model to implement this")
        XCTAssertEqual(byId["challenge-this-decision-before-i-commit"], "Challenge this decision before I commit")
        XCTAssertEqual(byId["keep-working-while-im-away"], "Keep working while I'm away")
        XCTAssertEqual(byId["ask-several-models-and-compare"], "Ask several models and compare")
        XCTAssertEqual(byId["recover-a-run-that-lost-its-terminal"], "Recover a run that lost its terminal")
        XCTAssertEqual(byId["use-a-specific-model-without-silent-substitution"], "Use a specific model without silent substitution")
        XCTAssertEqual(byId["get-sols-take-without-changing-files"], "Get Sol's take without changing files")

        for recipe in recipes {
            XCTAssertFalse(
                ["Pilot", "Relay", "Panel", "Spec Review"].contains(recipe.title),
                "title should be intent-shaped, not product noun alone: \(recipe.title)"
            )
            XCTAssertTrue(
                recipe.markdown.contains("## Example utterances"),
                "recipe \(recipe.id) missing example utterances"
            )
        }
    }

    func testLoopRecipeTeachesStatusFirstNotInfiniteWatch() throws {
        let md = try XCTUnwrap(RecipeCatalog.markdown(id: "get-another-model-to-implement-this"))
        XCTAssertTrue(md.contains("--no-wait"), "Loop recipe must teach handoff --no-wait")
        XCTAssertTrue(md.contains("loop status"), "Loop recipe must teach status poll")
        XCTAssertTrue(md.contains("optional") || md.contains("disposable"), "watch must be demoted")
        XCTAssertTrue(md.lowercased().contains("inspect"), "orphan path must teach inspect")
        XCTAssertTrue(md.lowercased().contains("blind retry") || md.lowercased().contains("never blind"))
    }

    func testMarkdownLookupById() {
        let id = "get-sols-take-without-changing-files"
        let md = RecipeCatalog.markdown(id: id)
        XCTAssertNotNil(md)
        XCTAssertTrue(md!.contains("model_gpt_sol"))
        XCTAssertTrue(md!.contains("alln run --project"))
        XCTAssertNil(RecipeCatalog.markdown(id: "no-such-recipe"))
    }

    func testHelpTopicSurfacesRecipes() {
        let topic = HelpTopicRegistry.topic(id: "recipes")
        XCTAssertNotNil(topic)
        XCTAssertEqual(topic?.sections.count, RecipeCatalog.list().count)
        XCTAssertTrue(HelpService.search("recipe").results.contains { $0.topicId == "recipes" })
        let md = HelpService.docsMarkdown(topic: "recipes")
        XCTAssertNotNil(md)
        XCTAssertTrue(md!.contains("Get another model to implement this"))
    }

    func testSummariesMatchList() {
        let summaries = RecipeCatalog.summaries()
        let list = RecipeCatalog.list()
        XCTAssertEqual(summaries.count, list.count)
        XCTAssertEqual(summaries.map(\.id), list.map(\.id))
        XCTAssertEqual(summaries.map(\.title), list.map(\.title))
    }
}
