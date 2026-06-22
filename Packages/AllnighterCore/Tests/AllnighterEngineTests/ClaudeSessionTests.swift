import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Warm_Single_Lane_Chat Phase 2: the Claude Code stream-json session driver, scripted with a fake
/// transport. No handshake — `start` just launches the reader; a turn streams `text_delta`s and ends
/// on `{"type":"result"}`.
final class ClaudeSessionTests: XCTestCase {

    final class FakeTransport: ACPTransport, @unchecked Sendable {
        private let inbound: AsyncStream<String>
        private let inboundCont: AsyncStream<String>.Continuation
        private let sentStream: AsyncStream<String>
        private let sentCont: AsyncStream<String>.Continuation
        init() {
            (inbound, inboundCont) = AsyncStream<String>.makeStream()
            (sentStream, sentCont) = AsyncStream<String>.makeStream()
        }
        func send(_ line: String) { sentCont.yield(line) }
        func inboundLines() -> AsyncStream<String> { inbound }
        func terminate() { inboundCont.finish() }
        func push(_ line: String) { inboundCont.yield(line) }
        func finishInbound() { inboundCont.finish() }
        func sent() -> AsyncStream<String> { sentStream }
    }

    func testStreamedTurnCompletesOnResult() async throws {
        let t = FakeTransport()
        let session = ClaudeSession(transport: t)
        var sent = t.sent().makeAsyncIterator()
        try await session.start(cwd: "/repo")   // no handshake

        let stream = await session.prompt("say hi")
        let collector = Task { () -> [ACPTurnEvent] in
            var c: [ACPTurnEvent] = []; for try await e in stream { c.append(e) }; return c
        }

        let userLine = await sent.next()!
        let obj = (try? JSONSerialization.jsonObject(with: Data(userLine.utf8))) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "user")

        t.push(#"{"type":"system","subtype":"init","session_id":"s"}"#)   // ignored
        t.push(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}}"#)
        t.push(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"amber"}}}"#)
        t.push(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"clock"}}}"#)
        t.push(#"{"type":"result","subtype":"success","is_error":false,"result":"amberclock"}"#)

        let events = try await collector.value
        XCTAssertEqual(events, [.reasoningDelta("hmm"), .answerDelta("amber"), .answerDelta("clock")])
    }

    func testDisconnectFailsActiveTurn() async throws {
        let t = FakeTransport()
        let session = ClaudeSession(transport: t)
        var sent = t.sent().makeAsyncIterator()
        try await session.start(cwd: "/repo")

        let stream = await session.prompt("hi")
        let collector = Task { () -> Error? in
            do { for try await _ in stream {} ; return nil } catch { return error }
        }
        _ = await sent.next()    // user message
        t.finishInbound()        // claude process died
        let err = await collector.value
        XCTAssertEqual(err as? ACPError, .disconnected)
    }
}
