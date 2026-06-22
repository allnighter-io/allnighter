import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Warm_Single_Lane_Chat Phase 3: the Codex app-server session driver, scripted with a fake transport
/// (no real `codex app-server`). Proves the dialect-specific flow: initialize → initialized notif →
/// thread/start → turn/start, finishing the turn on a `turn/completed` NOTIFICATION (not a result).
final class CodexSessionTests: XCTestCase {

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

    private func obj(_ line: String) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]) ?? [:]
    }
    private func jsonId(_ line: String) -> Int { (obj(line)["id"] as? Int) ?? -1 }
    private func jsonMethod(_ line: String) -> String { (obj(line)["method"] as? String) ?? "" }

    private func handshake(_ t: FakeTransport, _ sent: inout AsyncStream<String>.AsyncIterator,
                           _ session: CodexSession) async throws {
        let initLine = await sent.next()!
        XCTAssertEqual(jsonMethod(initLine), "initialize")
        t.push(#"{"id":\#(jsonId(initLine)),"result":{}}"#)
        let initdLine = await sent.next()!
        XCTAssertEqual(jsonMethod(initdLine), "initialized")   // notification, no response needed
        let threadLine = await sent.next()!
        XCTAssertEqual(jsonMethod(threadLine), "thread/start")
        t.push(#"{"id":\#(jsonId(threadLine)),"result":{"thread":{"id":"TH"}}}"#)
    }

    func testHandshakeThenTurnCompletesOnNotification() async throws {
        let t = FakeTransport()
        let session = CodexSession(transport: t, model: "gpt-5.5")
        var sent = t.sent().makeAsyncIterator()
        let startTask = Task { try await session.start(cwd: "/repo") }
        try await handshake(t, &sent, session)
        try await startTask.value

        let stream = await session.prompt("say hi")
        let collector = Task { () -> [ACPTurnEvent] in
            var c: [ACPTurnEvent] = []; for try await e in stream { c.append(e) }; return c
        }
        let turnLine = await sent.next()!
        XCTAssertEqual(jsonMethod(turnLine), "turn/start")

        t.push(#"{"method":"item/reasoning/textDelta","params":{"text":"thinking"}}"#)
        t.push(#"{"method":"item/agentMessage/delta","params":{"delta":"amberclock"}}"#)
        // turn/start's own result is NOT completion — it must be ignored:
        t.push(#"{"id":\#(jsonId(turnLine)),"result":{}}"#)
        t.push(#"{"method":"item/agentMessage/delta","params":{"delta":"!"}}"#)  // still streaming
        t.push(#"{"method":"turn/completed","params":{}}"#)                       // THIS ends the turn

        let events = try await collector.value
        XCTAssertEqual(events, [.reasoningDelta("thinking"), .answerDelta("amberclock"), .answerDelta("!")])
    }

    func testDisconnectFailsActiveTurn() async throws {
        let t = FakeTransport()
        let session = CodexSession(transport: t, model: "gpt-5.5")
        var sent = t.sent().makeAsyncIterator()
        let startTask = Task { try await session.start(cwd: "/repo") }
        try await handshake(t, &sent, session)
        try await startTask.value

        let stream = await session.prompt("hi")
        let collector = Task { () -> Error? in
            do { for try await _ in stream {} ; return nil } catch { return error }
        }
        _ = await sent.next()        // turn/start
        t.finishInbound()            // codex app-server died
        let err = await collector.value
        XCTAssertEqual(err as? ACPError, .disconnected)
    }
}
