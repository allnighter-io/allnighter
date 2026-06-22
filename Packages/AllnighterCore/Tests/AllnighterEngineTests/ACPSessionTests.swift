import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Warm_Single_Lane_Chat §4b: the ACP session driver, exercised with a scripted fake transport
/// (no real grok process). Proves handshake → session → streamed turn → completion, plus the
/// server-request ack and disconnect handling.
final class ACPSessionTests: XCTestCase {

    /// A scripted in-memory transport. `sent()` lets the test observe outgoing lines in order;
    /// `push()` injects agent→client lines.
    final class FakeACPTransport: ACPTransport, @unchecked Sendable {
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
    private func params(_ line: String) -> [String: Any] { (obj(line)["params"] as? [String: Any]) ?? [:] }
    private func resultLine(id: Int, sessionId: String? = nil) -> String {
        sessionId.map { #"{"jsonrpc":"2.0","id":\#(id),"result":{"sessionId":"\#($0)"}}"# }
            ?? #"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#
    }
    private func updateLine(_ kind: String, text: String? = nil, title: String? = nil) -> String {
        var fields = #""sessionUpdate":"\#(kind)""#
        if let text { fields += #","content":{"type":"text","text":"\#(text)"}"# }
        if let title { fields += #","title":"\#(title)""# }
        return #"{"jsonrpc":"2.0","method":"session/update","params":{"update":{\#(fields)}}}"#
    }

    func testHandshakeThenStreamedTurnCompletes() async throws {
        let t = FakeACPTransport()
        let session = ACPSession(transport: t)
        var sent = t.sent().makeAsyncIterator()

        let startTask = Task { try await session.start(cwd: "/repo/root") }

        let initLine = await sent.next()!
        XCTAssertEqual(jsonMethod(initLine), "initialize")
        t.push(resultLine(id: jsonId(initLine)))

        let newLine = await sent.next()!
        XCTAssertEqual(jsonMethod(newLine), "session/new")
        XCTAssertEqual(params(newLine)["cwd"] as? String, "/repo/root")
        t.push(resultLine(id: jsonId(newLine), sessionId: "S1"))

        try await startTask.value   // handshake complete

        let stream = await session.prompt("say hi")
        let collector = Task { () -> [ACPTurnEvent] in
            var collected: [ACPTurnEvent] = []
            for try await e in stream { collected.append(e) }
            return collected
        }

        let promptLine = await sent.next()!
        XCTAssertEqual(jsonMethod(promptLine), "session/prompt")
        XCTAssertEqual(params(promptLine)["sessionId"] as? String, "S1")
        let promptId = jsonId(promptLine)

        t.push(updateLine("agent_thought_chunk", text: "thinking"))
        t.push(updateLine("tool_call", title: "read_file"))
        t.push(updateLine("agent_message_chunk", text: "Hi"))
        t.push(resultLine(id: promptId))   // turn complete

        let events = try await collector.value
        XCTAssertEqual(events, [.reasoningDelta("thinking"), .toolActivity("read_file"), .answerDelta("Hi")])
    }

    func testServerRequestIsAcked() async throws {
        let t = FakeACPTransport()
        let session = ACPSession(transport: t)
        var sent = t.sent().makeAsyncIterator()
        let startTask = Task { try await session.start(cwd: "/r") }
        t.push(resultLine(id: jsonId(await sent.next()!)))                 // initialize
        t.push(resultLine(id: jsonId(await sent.next()!), sessionId: "S")) // session/new
        try await startTask.value

        // agent asks the client something mid-idle; the session must ack with an empty result.
        t.push(#"{"jsonrpc":"2.0","id":777,"method":"session/request_permission","params":{}}"#)
        var ack: String?
        while let line = await sent.next() {
            if jsonId(line) == 777 { ack = line; break }
        }
        XCTAssertNotNil(ack, "server request must be acked")
        XCTAssertTrue(ack!.contains("\"result\""))
    }

    func testDisconnectFailsActiveTurn() async throws {
        let t = FakeACPTransport()
        let session = ACPSession(transport: t)
        var sent = t.sent().makeAsyncIterator()
        let startTask = Task { try await session.start(cwd: "/r") }
        t.push(resultLine(id: jsonId(await sent.next()!)))
        t.push(resultLine(id: jsonId(await sent.next()!), sessionId: "S"))
        try await startTask.value

        let stream = await session.prompt("hi")
        let collector = Task { () -> Error? in
            do { for try await _ in stream {} ; return nil } catch { return error }
        }
        _ = await sent.next()           // the prompt line
        t.finishInbound()               // agent process dies

        let err = await collector.value
        XCTAssertEqual(err as? ACPError, .disconnected)
    }
}
