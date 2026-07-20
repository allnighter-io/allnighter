import XCTest
@testable import AllnighterCore

final class HelpProjectorTests: XCTestCase {

    func testSearchEnvelopeCarriesContractVersionRoutingLawAndPlan() {
        let j = HelpProjector.search("how do I send this to a team?", limit: 5, contractVersion: "1.0.0")
        XCTAssertEqual(j.contractVersion, "1.0.0")
        XCTAssertEqual(j.routingLaw, HelpService.routingLaw)
        XCTAssertEqual(j.results.first?.topicId, "team_run_loop")
        XCTAssertNotNil(j.suggestedAnswerMarkdown)
        // The plan routes to a runnable help get on the top topic.
        XCTAssertEqual(j.nextToolPlan.first?.command, "alln help get team_run_loop --json")
        XCTAssertNotNil(ContractRegistry.resolveCommandName(from: j.nextToolPlan.first?.command ?? ""))
    }

    func testLiveTopicPlanRoutesToALiveTool() {
        let j = HelpProjector.get(topic: "current_setup", contractVersion: "1.0.0")
        XCTAssertTrue(j.found)
        XCTAssertEqual(j.topic?.needsLiveCheck, true)
        XCTAssertEqual(j.nextToolPlan.first?.command, "alln team hello --json")
    }

    func testGetByError() {
        XCTAssertEqual(HelpProjector.get(error: "SOURCE_AUTH_EXPIRED", contractVersion: "1.0.0").topic?.id, "setup_and_auth")
    }

    func testMissEnvelopeOffersCloseMatchesSitemapAndSearchPlan() {
        let j = HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "1.0.0")
        XCTAssertFalse(j.found)
        XCTAssertFalse(j.sitemap.isEmpty)
        XCTAssertEqual(j.nextToolPlan.first?.command, "alln help search <query> --json")
    }

    func testTopicsEnvelopeListsTheSitemap() {
        let j = HelpProjector.topics(contractVersion: "1.0.0")
        XCTAssertEqual(j.topics.count, HelpTopicRegistry.topics.count)
        XCTAssertTrue(j.topics.contains { $0.topicId == "quickstart" })
    }

    func testErrorBridgeResolvesHelpTopicAndPlan() {
        let spec = ContractRegistry.milestone1.errors.first { $0.code == "SOURCE_AUTH_EXPIRED" }!
        let b = ErrorHelpBridge.explain(spec, contractVersion: "1.0.0")
        XCTAssertEqual(b.helpTopicId, "setup_and_auth")
        XCTAssertEqual(b.helpRef, "alln://help/setup_and_auth")
        XCTAssertEqual(b.nextToolPlan.first?.command, "alln help get --ref alln://help/setup_and_auth --json")
        XCTAssertTrue(b.nextToolPlan.contains { $0.command == "alln doctor --json" }, "source.* errors route to a re-probe")
    }

    func testErrorBridgeWithoutAHelpTopicStillReturns() {
        let spec = ContractRegistry.milestone1.errors.first { $0.code == "CONTRACT_DRIFT" }!
        let b = ErrorHelpBridge.explain(spec, contractVersion: "1.0.0")
        XCTAssertNil(b.helpTopicId)
        XCTAssertNil(b.helpRef)
    }

    func testEnvelopesRoundTripCodable() throws {
        let s = HelpProjector.search("pending", limit: 3, contractVersion: "1.0.0")
        XCTAssertEqual(try CoreJSON.decode(HelpSearchJSON.self, from: CoreJSON.encode(s)), s)
        let g = HelpProjector.get(topic: "pending", contractVersion: "1.0.0")
        XCTAssertEqual(try CoreJSON.decode(HelpGetJSON.self, from: CoreJSON.encode(g)), g)
    }

    /// ASF-S02: nextToolPlan steps carry runnable `command` strings; no `"tool"` key.
    func testNextToolPlanJSONHasCommandNotTool() throws {
        let search = HelpProjector.search("how do I send this to a team?", limit: 5, contractVersion: "1.0.0")
        let searchObj = try JSONSerialization.jsonObject(with: CoreJSON.encode(search)) as? [String: Any]
        let searchPlan = try XCTUnwrap(searchObj?["nextToolPlan"] as? [[String: Any]])
        XCTAssertFalse(searchPlan.isEmpty)
        for step in searchPlan {
            XCTAssertNotNil(step["command"] as? String)
            XCTAssertNil(step["tool"], "ASF-S02: tool key must not appear in nextToolPlan")
            XCTAssertTrue((step["command"] as? String)?.hasPrefix("alln ") ?? false)
            XCTAssertNotNil(ContractRegistry.resolveCommandName(from: step["command"] as? String ?? ""))
        }

        let get = HelpProjector.get(topic: "totally-unknown-topic", contractVersion: "1.0.0")
        let getObj = try JSONSerialization.jsonObject(with: CoreJSON.encode(get)) as? [String: Any]
        let getPlan = try XCTUnwrap(getObj?["nextToolPlan"] as? [[String: Any]])
        XCTAssertEqual(getPlan.first?["command"] as? String, "alln help search <query> --json")
        XCTAssertNil(getPlan.first?["tool"])

        let spec = ContractRegistry.milestone1.errors.first { $0.code == "SOURCE_AUTH_EXPIRED" }!
        let explain = ErrorHelpBridge.explain(spec, contractVersion: "1.0.0")
        let explainObj = try JSONSerialization.jsonObject(with: CoreJSON.encode(explain)) as? [String: Any]
        let explainPlan = try XCTUnwrap(explainObj?["nextToolPlan"] as? [[String: Any]])
        for step in explainPlan {
            XCTAssertNil(step["tool"])
            XCTAssertNotNil(step["command"])
        }
    }

    // MARK: - ASF-S03 / ASF-S04

    func testSearchOpencodeReturnsCatalogHitAndRunnablePlan() {
        let j = HelpProjector.search("opencode", limit: 5, contractVersion: "1.0.0")
        XCTAssertFalse(j.isMiss)
        XCTAssertFalse(j.results.isEmpty, "opencode must hit the discovery index")
        XCTAssertEqual(j.results.first?.topicId, HelpDiscoveryIndex.discoveryTopicId)
        XCTAssertFalse(j.discoveryModelIds.isEmpty)
        XCTAssertTrue(j.discoveryModelIds.contains { $0.contains("opencode") })
        XCTAssertFalse(j.nextToolPlan.isEmpty)
        XCTAssertTrue(j.nextToolPlan.contains { $0.command.hasPrefix("alln route --for ") })
        XCTAssertTrue(j.nextToolPlan.contains { $0.command == "alln models --json" })
        XCTAssertTrue(j.nextToolPlan.contains { $0.command.hasPrefix("alln run --worker ") })
        for step in j.nextToolPlan {
            XCTAssertTrue(step.command.hasPrefix("alln "))
            XCTAssertNotNil(ContractRegistry.resolveCommandName(from: step.command))
        }
    }

    func testSearchGlmReturnsCatalogHitAndWorkerPlan() {
        let j = HelpProjector.search("glm", limit: 5, contractVersion: "1.0.0")
        XCTAssertFalse(j.isMiss)
        XCTAssertFalse(j.results.isEmpty)
        XCTAssertEqual(j.results.first?.topicId, HelpDiscoveryIndex.discoveryTopicId)
        XCTAssertTrue(j.discoveryModelIds.contains("model_opencode_glm_5_2"))
        XCTAssertTrue(j.nextToolPlan.contains { $0.command.hasPrefix("alln route --for ") })
        XCTAssertTrue(j.nextToolPlan.contains { $0.command == "alln models --json" })
        XCTAssertTrue(
            j.nextToolPlan.contains { $0.command.contains("model_opencode_glm_5_2") },
            "glm plan must point at the GLM worker"
        )
        for step in j.nextToolPlan {
            XCTAssertTrue(step.command.hasPrefix("alln "))
        }
    }

    func testNonsenseSearchIsMissWithRecoveryPlan() {
        let j = HelpProjector.search("asdfqwerty-no-such-topic-999", limit: 5, contractVersion: "1.0.0")
        XCTAssertTrue(j.isMiss)
        XCTAssertTrue(j.results.isEmpty, "nonsense must not fuzzy-hijack a topic")
        XCTAssertTrue(j.discoveryModelIds.isEmpty)
        XCTAssertFalse(j.nextToolPlan.isEmpty, "miss recovery must be non-empty")
        let commands = j.nextToolPlan.map(\.command)
        XCTAssertTrue(commands.contains("alln models --json"))
        XCTAssertTrue(commands.contains("alln team show --json"))
        XCTAssertTrue(commands.contains("alln doctor --json"))
        XCTAssertTrue(commands.contains { $0.hasPrefix("alln route --for ") })
        for step in j.nextToolPlan {
            XCTAssertTrue(step.command.hasPrefix("alln "))
            XCTAssertNotNil(ContractRegistry.resolveCommandName(from: step.command))
        }
    }

    func testCatalogTermsAreNotSilentWhileNonsenseHasAPlan() {
        let opencode = HelpProjector.search("opencode", limit: 5, contractVersion: "1.0.0")
        let nonsense = HelpProjector.search("asdfqwerty-no-such-topic-999", limit: 5, contractVersion: "1.0.0")
        XCTAssertFalse(opencode.results.isEmpty, "real product term must not be silent")
        XCTAssertFalse(opencode.nextToolPlan.isEmpty)
        XCTAssertTrue(nonsense.isMiss)
        XCTAssertFalse(nonsense.nextToolPlan.isEmpty)
    }
}
