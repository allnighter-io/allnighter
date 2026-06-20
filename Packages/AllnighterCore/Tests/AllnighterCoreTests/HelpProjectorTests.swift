import XCTest
@testable import AllnighterCore

final class HelpProjectorTests: XCTestCase {

    func testSearchEnvelopeCarriesContractVersionRoutingLawAndPlan() {
        let j = HelpProjector.search("how do I send this to a team?", limit: 5, contractVersion: "1.0.0")
        XCTAssertEqual(j.contractVersion, "1.0.0")
        XCTAssertEqual(j.routingLaw, HelpService.routingLaw)
        XCTAssertEqual(j.results.first?.topicId, "team_run_loop")
        XCTAssertNotNil(j.suggestedAnswerMarkdown)
        // The plan routes to help_get on the top topic.
        XCTAssertEqual(j.nextToolPlan.first?.tool, "help_get")
        XCTAssertEqual(j.nextToolPlan.first?.args["topic"], "team_run_loop")
    }

    func testLiveTopicPlanRoutesToALiveTool() {
        let j = HelpProjector.get(topic: "current_setup", contractVersion: "1.0.0")
        XCTAssertTrue(j.found)
        XCTAssertEqual(j.topic?.needsLiveCheck, true)
        XCTAssertEqual(j.nextToolPlan.first?.tool, "mcp_hello")
    }

    func testGetByToolAndError() {
        XCTAssertTrue(HelpProjector.get(tool: "defaults_get", contractVersion: "1.0.0").found)
        XCTAssertEqual(HelpProjector.get(error: "SOURCE_AUTH_EXPIRED", contractVersion: "1.0.0").topic?.id, "setup_and_auth")
    }

    func testMissEnvelopeOffersCloseMatchesSitemapAndSearchPlan() {
        let j = HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "1.0.0")
        XCTAssertFalse(j.found)
        XCTAssertFalse(j.sitemap.isEmpty)
        XCTAssertEqual(j.nextToolPlan.first?.tool, "help_search")
    }

    func testTopicsEnvelopeListsTheSitemap() {
        let j = HelpProjector.topics(contractVersion: "1.0.0")
        XCTAssertEqual(j.topics.count, HelpTopicRegistry.topics.count)
        XCTAssertTrue(j.topics.contains { $0.topicId == "quickstart" })
    }

    func testEnvelopesRoundTripCodable() throws {
        let s = HelpProjector.search("pending", limit: 3, contractVersion: "1.0.0")
        XCTAssertEqual(try CoreJSON.decode(HelpSearchJSON.self, from: CoreJSON.encode(s)), s)
        let g = HelpProjector.get(topic: "pending", contractVersion: "1.0.0")
        XCTAssertEqual(try CoreJSON.decode(HelpGetJSON.self, from: CoreJSON.encode(g)), g)
    }
}
