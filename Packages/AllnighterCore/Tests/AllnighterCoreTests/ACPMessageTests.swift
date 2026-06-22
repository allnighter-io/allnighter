import XCTest
@testable import AllnighterCore

/// Warm_Single_Lane_Chat §4b: the ACP framing that drives a warm `grok agent stdio` worker.
/// Samples are the EXACT wire captured from the live spike (2026-06-21).
final class ACPMessageTests: XCTestCase {

    // MARK: outgoing encoders round-trip to valid JSON-RPC

    private func decode(_ line: String) -> [String: Any] {
        XCTAssertTrue(line.hasSuffix("\n"), "messages are newline-framed")
        let data = line.data(using: .utf8)!
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func testInitializeEncodes() {
        let obj = decode(ACP.initialize(id: 1))
        XCTAssertEqual(obj["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(obj["id"] as? Int, 1)
        XCTAssertEqual(obj["method"] as? String, "initialize")
        XCTAssertEqual((obj["params"] as? [String: Any])?["protocolVersion"] as? Int, 1)
    }

    func testSessionNewCarriesCwd() {
        let obj = decode(ACP.sessionNew(id: 2, cwd: "/repo/root"))
        XCTAssertEqual(obj["method"] as? String, "session/new")
        XCTAssertEqual((obj["params"] as? [String: Any])?["cwd"] as? String, "/repo/root")
    }

    func testSessionPromptShapesTheTurn() {
        let obj = decode(ACP.sessionPrompt(id: 3, sessionId: "sess-1", text: "hello"))
        XCTAssertEqual(obj["method"] as? String, "session/prompt")
        let params = obj["params"] as? [String: Any]
        XCTAssertEqual(params?["sessionId"] as? String, "sess-1")
        let prompt = params?["prompt"] as? [[String: String]]
        XCTAssertEqual(prompt?.first?["type"], "text")
        XCTAssertEqual(prompt?.first?["text"], "hello")
    }

    // MARK: inbound classifier — exact captured wire

    func testInitializeResultIsAResultWithNoSession() {
        // captured initialize reply (truncated agentCapabilities elided)
        let line = #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true}}}"#
        XCTAssertEqual(ACP.parse(line), .result(id: 1, sessionId: nil))
    }

    func testSessionNewResultCarriesSessionId() {
        let line = #"{"jsonrpc":"2.0","id":2,"result":{"sessionId":"abc-123"}}"#
        XCTAssertEqual(ACP.parse(line), .result(id: 2, sessionId: "abc-123"))
    }

    func testAgentMessageChunkIsAnswerText() {
        let line = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"amberclock"}}}}"#
        guard case let .update(u)? = ACP.parse(line) else { return XCTFail("expected update") }
        XCTAssertEqual(u.kind, .message)
        XCTAssertEqual(u.text, "amberclock")
    }

    func testThoughtChunkIsReasoning() {
        let line = #"{"jsonrpc":"2.0","method":"session/update","params":{"update":{"sessionUpdate":"agent_thought_chunk","content":{"text":"thinking..."}}}}"#
        guard case let .update(u)? = ACP.parse(line) else { return XCTFail("expected update") }
        XCTAssertEqual(u.kind, .thought)
        XCTAssertEqual(u.text, "thinking...")
    }

    func testToolCallCarriesTitle() {
        let line = #"{"jsonrpc":"2.0","method":"session/update","params":{"update":{"sessionUpdate":"tool_call","title":"read_file","kind":"read"}}}"#
        guard case let .update(u)? = ACP.parse(line) else { return XCTFail("expected update") }
        XCTAssertEqual(u.kind, .toolCall)
        XCTAssertEqual(u.title, "read_file")
    }

    func testServerRequestIsFlaggedForAck() {
        // agent asks the client something (id + method, no result) — we must ack so it doesn't hang.
        let line = #"{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{}}"#
        XCTAssertEqual(ACP.parse(line), .serverRequest(id: 7, method: "session/request_permission"))
    }

    func testAnnouncementNotificationIsOther() {
        // captured: a non-session notification we ignore.
        let line = #"{"jsonrpc":"2.0","method":"_x.ai/announcements/update","params":{"gen":1}}"#
        XCTAssertEqual(ACP.parse(line), .other)
    }

    func testErrorResponseIsFailure() {
        let line = #"{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"method not found"}}"#
        XCTAssertEqual(ACP.parse(line), .failure(id: 3, code: -32601, message: "method not found"))
    }

    func testBlankAndGarbageAreNil() {
        XCTAssertNil(ACP.parse(""))
        XCTAssertNil(ACP.parse("   "))
        XCTAssertNil(ACP.parse("not json"))
    }
}
