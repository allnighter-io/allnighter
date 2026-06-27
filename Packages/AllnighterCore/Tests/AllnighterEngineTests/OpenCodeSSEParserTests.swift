import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class OpenCodeSSEParserTests: XCTestCase {
    func testNewSuffixIncrementalText() {
        XCTAssertEqual(OpenCodeSSEParser.newSuffix(previous: "hel", current: "hello"), "lo")
        XCTAssertEqual(OpenCodeSSEParser.newSuffix(previous: "", current: "hello"), "hello")
        XCTAssertEqual(OpenCodeSSEParser.newSuffix(previous: "hello", current: "hello"), "")
    }

    func testMessagePartUpdatedDeltaYieldsAnswerDelta() {
        let parser = OpenCodeSSEParser()
        let line = #"data: {"type":"message.part.updated","properties":{"part":{"type":"text","text":"hi"},"delta":"hi"}}"#
        let events = parser.receive(Data((line + "\n").utf8))
        XCTAssertEqual(events.count, 1)
        guard case .answerDelta(let text, _, _) = events[0] else {
            return XCTFail("expected answerDelta")
        }
        XCTAssertEqual(text, "hi")
        XCTAssertEqual(parser.accumulatedAnswer, "hi")
    }

    func testReasoningDeltaAccumulates() {
        let parser = OpenCodeSSEParser()
        let line = #"data: {"type":"message.part.updated","properties":{"part":{"type":"reasoning"},"delta":"think"}}"#
        let events = parser.receive(Data((line + "\n").utf8))
        guard case .reasoningDelta(let text, _) = events[0] else {
            return XCTFail("expected reasoningDelta")
        }
        XCTAssertEqual(text, "think")
        XCTAssertEqual(parser.accumulatedReasoning, "think")
    }

    func testToolPartCountsAndEmitsToolActivity() {
        let parser = OpenCodeSSEParser()
        // Two updates for the SAME tool call (running → completed) count once.
        let running = #"data: {"type":"message.part.updated","properties":{"part":{"type":"tool","callID":"call_1","tool":"write","state":{"status":"running"}}}}"#
        let completed = #"data: {"type":"message.part.updated","properties":{"part":{"type":"tool","callID":"call_1","tool":"write","state":{"status":"completed"}}}}"#
        let other = #"data: {"type":"message.part.updated","properties":{"part":{"type":"tool","callID":"call_2","tool":"bash","state":{"status":"completed"}}}}"#
        let events = parser.receive(Data((running + "\n").utf8))
        guard case .toolActivity(let label, let kind) = events[0] else { return XCTFail("expected toolActivity") }
        XCTAssertEqual(label, "write")
        XCTAssertEqual(kind, "running")
        _ = parser.receive(Data((completed + "\n").utf8))
        _ = parser.receive(Data((other + "\n").utf8))
        XCTAssertEqual(parser.toolActionCount, 2)
        XCTAssertTrue(parser.accumulatedAnswer.isEmpty)
    }

    func testSessionErrorIsCaptured() {
        let parser = OpenCodeSSEParser()
        let line = #"data: {"type":"session.error","properties":{"error":{"name":"ProviderAuthError","data":{"message":"auth failed"}}}}"#
        _ = parser.receive(Data((line + "\n").utf8))
        XCTAssertEqual(parser.sessionError, "auth failed")
    }

    func testSessionIdleIsRawEvent() {
        let parser = OpenCodeSSEParser()
        let line = #"data: {"type":"session.idle","properties":{"sessionID":"ses_x"}}"#
        let events = parser.receive(Data((line + "\n\n").utf8))
        guard case .rawEvent(let source, let json) = events[0] else {
            return XCTFail("expected rawEvent")
        }
        XCTAssertEqual(source, "opencode")
        XCTAssertTrue(json.contains("session.idle"))
    }
}
