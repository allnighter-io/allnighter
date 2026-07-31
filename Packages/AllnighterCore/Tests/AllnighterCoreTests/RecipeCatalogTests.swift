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
        let body = TeachingSnippet.body
        let hashMarker = "hash=\(TeachingSnippet.contentHash)"
        for recipe in RecipeCatalog.list() {
            let md = recipe.markdown
            let hasWrap = md.contains(wrap)
            let hasBodyAndMarkers =
                md.contains(body)
                && md.contains(TeachingSnippet.openMarkerPrefix)
                && md.contains(TeachingSnippet.closeMarker)
                && md.contains(hashMarker)
            XCTAssertTrue(
                hasWrap || hasBodyAndMarkers,
                "recipe \(recipe.id) must embed TeachingSnippet.wrap()/body (contentHash=\(TeachingSnippet.contentHash.prefix(12))…)"
            )
            // Marker hash must match current SSOT even if wrap() whitespace differs slightly.
            XCTAssertTrue(md.contains(hashMarker), "recipe \(recipe.id) teaching hash drifted")
        }
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
