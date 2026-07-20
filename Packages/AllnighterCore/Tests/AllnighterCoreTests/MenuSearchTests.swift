import XCTest
@testable import AllnighterCore

final class MenuSearchTests: XCTestCase {
    func testSearchReturnsMenuCardsWithoutRecommendationFields() throws {
        let menu = MenuCatalog.project()
        let r = MenuCatalog.search("opencode", limit: 8, menu: menu)
        XCTAssertFalse(r.results.isEmpty, "opencode must hit a menu model/command card")
        XCTAssertEqual(r.catalogRevision, menu.catalogRevision)
        XCTAssertTrue(r.results.contains { $0.kind == "model" && $0.id.contains("opencode") })

        let envelope = HelpProjector.search("opencode", limit: 8, contractVersion: "2.1.0", menu: menu)
        let data = try CoreJSON.encode(envelope)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for banned in ["recommended", "confidence", "selected", "suggestedAnswerMarkdown",
                       "suggestedAnswerRefs", "nextToolPlan", "discoveryModelIds", "score", "isMiss"] {
            XCTAssertNil(obj[banned], "search must not emit \(banned)")
        }
        let raw = String(data: data, encoding: .utf8)!.lowercased()
        XCTAssertFalse(raw.contains("\"recommended\""))
        XCTAssertFalse(raw.contains("\"confidence\""))
        XCTAssertFalse(raw.contains("\"selected\""))
        XCTAssertFalse(envelope.results.isEmpty)
        XCTAssertEqual(envelope.results.first?.kind.isEmpty, false)
    }

    func testSearchRunFindsCommandOrActionCards() {
        let r = MenuCatalog.search("run", limit: 10)
        XCTAssertTrue(r.results.contains { $0.kind == "command" && $0.id == "run" }
            || r.results.contains { $0.kind == "action" && $0.id == "run" })
    }

    func testNonsenseSearchReturnsZeroCards() {
        let r = MenuCatalog.search("asdfqwerty-no-such-topic-999", limit: 5)
        XCTAssertTrue(r.results.isEmpty)
    }

    func testSearchDoesNotEmbedScoreOnHits() throws {
        let hit = try XCTUnwrap(MenuCatalog.search("sonnet", limit: 3).results.first)
        let data = try CoreJSON.encode(hit)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["score"])
        XCTAssertNil(obj["recommended"])
        XCTAssertNil(obj["confidence"])
        XCTAssertNotNil(obj["ref"])
        XCTAssertNotNil(obj["kind"])
    }

    func testZeroLimitReturnsEmpty() {
        let r = MenuCatalog.search("run", limit: 0)
        XCTAssertTrue(r.results.isEmpty)
    }
}
