import XCTest
@testable import AllnighterCore

final class HelpProjectorTests: XCTestCase {

    func testSearchEnvelopeIsMenuCardsWithoutRecommendationFields() throws {
        let j = HelpProjector.search("how do I send this to a team?", limit: 5, contractVersion: "2.1.0")
        XCTAssertEqual(j.contractVersion, "2.1.0")
        XCTAssertFalse(j.catalogRevision.isEmpty)
        let data = try CoreJSON.encode(j)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(obj["suggestedAnswerMarkdown"])
        XCTAssertNil(obj["nextToolPlan"])
        XCTAssertNil(obj["discoveryModelIds"])
        XCTAssertNil(obj["isMiss"])
        XCTAssertNil(obj["routingLaw"])
        XCTAssertNotNil(obj["results"])
    }

    func testLiveTopicPlanRoutesToALiveTool() {
        let j = HelpProjector.get(topic: "current_setup", contractVersion: "2.1.0")
        XCTAssertTrue(j.found)
        XCTAssertEqual(j.topic?.needsLiveCheck, true)
        XCTAssertEqual(j.nextToolPlan.first?.command, "alln menu --json")
    }

    func testGetByError() {
        XCTAssertEqual(HelpProjector.get(error: "SOURCE_AUTH_EXPIRED", contractVersion: "2.1.0").topic?.id, "setup_and_auth")
    }

    func testMissEnvelopeOffersCloseMatchesSitemapAndSearchPlan() {
        let j = HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "2.1.0")
        XCTAssertFalse(j.found)
        XCTAssertFalse(j.sitemap.isEmpty)
        XCTAssertEqual(j.nextToolPlan.first?.command, "alln help search <query> --json")
    }

    func testTopicsEnvelopeListsTheSitemap() {
        let j = HelpProjector.topics(contractVersion: "2.1.0")
        XCTAssertEqual(j.topics.count, HelpTopicRegistry.topics.count)
        XCTAssertTrue(j.topics.contains { $0.topicId == "quickstart" })
    }

    func testErrorBridgeResolvesHelpTopicAndPlan() {
        let spec = ContractRegistry.milestone1.errors.first { $0.code == "SOURCE_AUTH_EXPIRED" }!
        let b = ErrorHelpBridge.explain(spec, contractVersion: "2.1.0")
        XCTAssertEqual(b.helpTopicId, "setup_and_auth")
        XCTAssertEqual(b.helpRef, "alln://help/setup_and_auth")
        XCTAssertEqual(b.nextToolPlan.first?.command, "alln help get --ref alln://help/setup_and_auth --json")
        XCTAssertTrue(b.nextToolPlan.contains { $0.command == "alln doctor --json" }, "source.* errors route to a re-probe")
    }

    func testErrorBridgeWithoutAHelpTopicStillReturns() {
        let spec = ContractRegistry.milestone1.errors.first { $0.code == "CONTRACT_DRIFT" }!
        let b = ErrorHelpBridge.explain(spec, contractVersion: "2.1.0")
        XCTAssertNil(b.helpTopicId)
        XCTAssertNil(b.helpRef)
    }

    func testEnvelopesRoundTripCodable() throws {
        let s = HelpProjector.search("pending", limit: 3, contractVersion: "2.1.0")
        XCTAssertEqual(try CoreJSON.decode(HelpSearchJSON.self, from: CoreJSON.encode(s)), s)
        let g = HelpProjector.get(topic: "pending", contractVersion: "2.1.0")
        XCTAssertEqual(try CoreJSON.decode(HelpGetJSON.self, from: CoreJSON.encode(g)), g)
    }

    /// ASF-S02: nextToolPlan steps (get/error only) carry runnable `command` strings; no `"tool"` key.
    func testNextToolPlanJSONHasCommandNotTool() throws {
        let get = HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "2.1.0")
        let getObj = try JSONSerialization.jsonObject(with: CoreJSON.encode(get)) as? [String: Any]
        let getPlan = try XCTUnwrap(getObj?["nextToolPlan"] as? [[String: Any]])
        XCTAssertEqual(getPlan.first?["command"] as? String, "alln help search <query> --json")
        XCTAssertNil(getPlan.first?["tool"])

        let spec = ContractRegistry.milestone1.errors.first { $0.code == "SOURCE_AUTH_EXPIRED" }!
        let explain = ErrorHelpBridge.explain(spec, contractVersion: "2.1.0")
        let explainObj = try JSONSerialization.jsonObject(with: CoreJSON.encode(explain)) as? [String: Any]
        let explainPlan = try XCTUnwrap(explainObj?["nextToolPlan"] as? [[String: Any]])
        for step in explainPlan {
            XCTAssertNil(step["tool"])
            XCTAssertNotNil(step["command"])
        }
    }

    // Retargeted from opencode/glm to a surviving catalog term (founder ruling
    // 2026-07-24 removed the two opencode built-in models). kimi still ships built-in.
    func testSearchKimiReturnsModelCards() {
        let j = HelpProjector.search("kimi", limit: 8, contractVersion: "2.1.0")
        XCTAssertFalse(j.results.isEmpty, "kimi must hit menu cards")
        XCTAssertTrue(j.results.contains { $0.kind == "model" && $0.id.contains("kimi") })
    }

    func testSearchGrokReturnsModelCards() {
        let j = HelpProjector.search("grok", limit: 8, contractVersion: "2.1.0")
        XCTAssertFalse(j.results.isEmpty)
        XCTAssertTrue(j.results.contains { $0.id.contains("grok") || $0.title.lowercased().contains("grok") })
    }

    func testNonsenseSearchReturnsZeroCards() {
        let j = HelpProjector.search("asdfqwerty-no-such-topic-999", limit: 5, contractVersion: "2.1.0")
        XCTAssertTrue(j.results.isEmpty, "nonsense must not fuzzy-hijack a card")
    }
}
