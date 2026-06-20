import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class StreamingPartialBufferTests: XCTestCase {

    func testAppendBelowCapKeepsEverything() {
        var buffer = StreamingPartialBuffer()
        buffer.append("Hello, ")
        buffer.append("world")
        XCTAssertEqual(buffer.visibleText, "Hello, world")
        XCTAssertFalse(buffer.isTruncated)
    }

    func testCapKeepsNewestSuffixAndMarksTruncated() {
        var buffer = StreamingPartialBuffer(capBytes: 10, flushBytes: 1)
        buffer.append("0123456789")          // exactly at cap
        XCTAssertFalse(buffer.isTruncated)
        buffer.append("ABCDE")               // overflow → keep newest 10 bytes
        XCTAssertTrue(buffer.isTruncated)
        XCTAssertEqual(buffer.visibleText, "56789ABCDE")
        XCTAssertEqual(buffer.visibleText.utf8.count, 10)
    }

    func testFlushThresholdSignalsThenResets() {
        var buffer = StreamingPartialBuffer(capBytes: 1_000, flushBytes: 8)
        XCTAssertFalse(buffer.append("1234"))   // 4 bytes < 8
        XCTAssertTrue(buffer.append("5678"))    // 8 bytes ≥ 8 → flush due
        buffer.markFlushed()
        XCTAssertFalse(buffer.append("9"))      // counter reset
    }

    func testNewestSuffixCutsOnCharacterBoundary() {
        // A multi-byte emoji must not be split mid-scalar when trimming.
        let s = String(repeating: "a", count: 8) + "😀"   // 8 + 4 bytes = 12
        let suffix = StreamingPartialBuffer.newestSuffix(of: s, maxBytes: 6)
        XCTAssertTrue(suffix.hasSuffix("😀"))
        XCTAssertLessThanOrEqual(suffix.utf8.count, 6)
        XCTAssertNotNil(suffix.unicodeScalars.last)   // valid string, no broken scalar
    }

    func testThreadTurnPartialTruncatedRoundTrips() throws {
        var turn = ThreadTurn(id: "t", threadId: "th", kind: .workerChat, status: .running,
                              createdAt: Date(), author: .worker, text: "partial")
        turn.partialOutputTruncated = true
        let data = try JSONEncoder().encode(turn)
        let back = try JSONDecoder().decode(ThreadTurn.self, from: data)
        XCTAssertTrue(back.partialOutputTruncated)
    }

    func testLegacyTurnJSONDecodesTruncatedFalse() throws {
        let json = #"{"id":"t","threadId":"th","kind":"worker_chat","status":"done","createdAt":0,"author":"worker","artifactRefs":[],"attachmentRefs":[],"fileReferenceRefs":[]}"#
        let turn = try JSONDecoder().decode(ThreadTurn.self, from: Data(json.utf8))
        XCTAssertFalse(turn.partialOutputTruncated)
    }
}
