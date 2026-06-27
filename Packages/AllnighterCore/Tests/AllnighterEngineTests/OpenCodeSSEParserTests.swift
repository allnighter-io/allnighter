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
