import XCTest
@testable import AllnighterCore

/// Warm_Single_Lane_Chat Phase 2: the Claude Code stream-json codec. Wire shapes from the live spike
/// (claude 2.1.185) — no handshake/session id; `{"type":"user"}` in, `stream_event` deltas +
/// `{"type":"result"}` out.
final class ClaudeMessageTests: XCTestCase {

    private func decode(_ line: String) -> [String: Any] {
        XCTAssertTrue(line.hasSuffix("\n"))
        return ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]) ?? [:]
    }

    func testUserMessageEncodes() {
        let obj = decode(ClaudeMsg.userMessage("hello"))
        XCTAssertEqual(obj["type"] as? String, "user")
        let message = obj["message"] as? [String: Any]
        XCTAssertEqual(message?["role"] as? String, "user")
        let content = message?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "hello")
    }

    func testTextDeltaIsAnswer() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"amber"}}}"#
        XCTAssertEqual(ClaudeMsg.parse(line), .answerDelta("amber"))
    }

    func testThinkingDeltaIsReasoning() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}}"#
        XCTAssertEqual(ClaudeMsg.parse(line), .reasoningDelta("hmm"))
    }

    func testResultIsTurnCompleted() {
        XCTAssertEqual(ClaudeMsg.parse(#"{"type":"result","subtype":"success","result":"OK","is_error":false}"#),
                       .turnCompleted(usage: nil))
    }

    func testResultUsageExtracted() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"usage":{"input_tokens":2655,"output_tokens":18,"cache_read_input_tokens":15626}}"#
        XCTAssertEqual(ClaudeMsg.parse(line), .turnCompleted(usage: ReportedTokenUsage(inputTokens: 2655, outputTokens: 18)))
    }

    func testErrorResultIsFailure() {
        XCTAssertEqual(ClaudeMsg.parse(#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#),
                       .failure(message: "boom"))
    }

    func testSystemInitAndUnknownAreOther() {
        XCTAssertEqual(ClaudeMsg.parse(#"{"type":"system","subtype":"init","session_id":"x"}"#), .other)
        XCTAssertEqual(ClaudeMsg.parse(#"{"type":"assistant","message":{"content":[]}}"#), .other)
        XCTAssertNil(ClaudeMsg.parse("not json"))
    }
}
