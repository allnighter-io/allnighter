import XCTest
import AllnighterCore

final class AsyncTeamMCPParsingTests: XCTestCase {
    func testMCPArgumentsPreferPrompt() {
        let req = AsyncTeamStartRequest(mcpArguments: [
            "prompt": "ship it",
            "lane": "build",
            "team": "build_test",
            "effort": "low",
            "threadId": "thread-1",
            "originAgent": "openclaw",
            "originConversationId": "conv-9",
            "originMessageId": "msg-9",
            "idempotencyKey": "key-1",
        ])
        XCTAssertEqual(req?.question, "ship it")
        XCTAssertEqual(req?.lane, .build)
        XCTAssertEqual(req?.teamPresetId, "build_test")
        XCTAssertEqual(req?.effort, .low)
        XCTAssertEqual(req?.threadId, "thread-1")
        XCTAssertEqual(req?.originAgent, "openclaw")
        XCTAssertEqual(req?.originConversationId, "conv-9")
        XCTAssertEqual(req?.originMessageId, "msg-9")
        XCTAssertEqual(req?.idempotencyKey, "key-1")
    }

    func testMCPArgumentsAcceptQuestionAlias() {
        let req = AsyncTeamStartRequest(mcpArguments: ["question": "alias ok"])
        XCTAssertEqual(req?.question, "alias ok")
    }

    func testMCPArgumentsRejectEmptyPrompt() {
        XCTAssertNil(AsyncTeamStartRequest(mcpArguments: [:]))
        XCTAssertNil(AsyncTeamStartRequest(mcpArguments: ["prompt": ""]))
    }
}
