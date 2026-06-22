import XCTest
@testable import AllnighterCore

/// Warm_Single_Lane_Chat Phase 3: the Codex app-server codec. Wire shapes verified against the live
/// spike (codex-cli 0.140.0) — JSON-RPC-shaped but with NO `jsonrpc` field.
final class CodexMessageTests: XCTestCase {

    private func decode(_ line: String) -> [String: Any] {
        XCTAssertTrue(line.hasSuffix("\n"), "messages are newline-framed")
        return ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]) ?? [:]
    }

    func testJsonrpcFieldIsOmitted() {
        XCTAssertNil(decode(Codex.initialize(id: 0))["jsonrpc"], "codex app-server omits the jsonrpc field")
    }

    func testInitializeEncodes() {
        let obj = decode(Codex.initialize(id: 0))
        XCTAssertEqual(obj["method"] as? String, "initialize")
        XCTAssertEqual(obj["id"] as? Int, 0)
        let clientInfo = (obj["params"] as? [String: Any])?["clientInfo"] as? [String: Any]
        XCTAssertEqual(clientInfo?["name"] as? String, "allnighter")
    }

    func testInitializedIsANotification() {
        let obj = decode(Codex.initialized())
        XCTAssertEqual(obj["method"] as? String, "initialized")
        XCTAssertNil(obj["id"], "notifications carry no id")
    }

    func testThreadStartBindsCwdModelAndNeverApproval() {
        let p = decode(Codex.threadStart(id: 1, cwd: "/repo", model: "gpt-5.5"))["params"] as? [String: Any]
        XCTAssertEqual(p?["cwd"] as? String, "/repo")
        XCTAssertEqual(p?["model"] as? String, "gpt-5.5")
        XCTAssertEqual(p?["approvalPolicy"] as? String, "never")
        XCTAssertEqual(p?["sandbox"] as? String, "workspace-write")
    }

    func testTurnStartShapesInput() {
        let p = decode(Codex.turnStart(id: 2, threadId: "th-1", text: "hello"))["params"] as? [String: Any]
        XCTAssertEqual(p?["threadId"] as? String, "th-1")
        let input = p?["input"] as? [[String: Any]]
        XCTAssertEqual(input?.first?["type"] as? String, "text")
        XCTAssertEqual(input?.first?["text"] as? String, "hello")
    }

    func testThreadStartResultCarriesThreadId() {
        let line = #"{"id":1,"result":{"thread":{"id":"th-abc"}}}"#
        XCTAssertEqual(Codex.parse(line), .result(id: 1, threadId: "th-abc"))
    }

    func testAgentMessageDeltaIsAnswer() {
        XCTAssertEqual(Codex.parse(#"{"method":"item/agentMessage/delta","params":{"delta":"amber"}}"#),
                       .answerDelta("amber"))
        // tolerate the text living under text/content too
        XCTAssertEqual(Codex.parse(#"{"method":"item/agentMessage/delta","params":{"text":"clock"}}"#),
                       .answerDelta("clock"))
    }

    func testReasoningDeltaVariants() {
        XCTAssertEqual(Codex.parse(#"{"method":"item/reasoning/textDelta","params":{"text":"t"}}"#),
                       .reasoningDelta("t"))
        XCTAssertEqual(Codex.parse(#"{"method":"item/reasoning/summaryTextDelta","params":{"delta":"s"}}"#),
                       .reasoningDelta("s"))
    }

    func testTurnCompletedIsTheTurnEndSignal() {
        XCTAssertEqual(Codex.parse(#"{"method":"turn/completed","params":{"turn":{"status":"completed"}}}"#),
                       .turnCompleted)
    }

    func testErrorIsFailure() {
        XCTAssertEqual(Codex.parse(#"{"id":3,"error":{"message":"boom"}}"#), .failure(id: 3, message: "boom"))
        XCTAssertEqual(Codex.parse(#"{"method":"error","params":{"message":"bang"}}"#), .failure(id: nil, message: "bang"))
    }

    func testUnknownNotificationIsOther() {
        XCTAssertEqual(Codex.parse(#"{"method":"mcpServer/startupStatus/updated","params":{}}"#), .other)
    }

    func testServerRequestIsFlagged() {
        XCTAssertEqual(Codex.parse(#"{"id":9,"method":"some/approval","params":{}}"#), .serverRequest(id: 9))
    }
}
