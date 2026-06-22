import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Warm_Single_Lane_Chat §5 S1: the warm worker wrapper. Uses an auto-responding fake transport so
/// the one-time-handshake + warm-reuse property is provable without a real grok process.
final class WarmWorkerTests: XCTestCase {

    /// Fake transport that auto-answers ACP requests; counts `session/new` to prove the cold
    /// handshake happens exactly ONCE no matter how many turns run.
    final class AutoACPTransport: ACPTransport, @unchecked Sendable {
        private let inbound: AsyncStream<String>
        private let cont: AsyncStream<String>.Continuation
        private let lock = NSLock()
        private var _sessionNewCount = 0
        var sessionNewCount: Int { lock.lock(); defer { lock.unlock() }; return _sessionNewCount }

        init() { (inbound, cont) = AsyncStream<String>.makeStream() }
        func inboundLines() -> AsyncStream<String> { inbound }
        func terminate() { cont.finish() }

        func send(_ line: String) {
            let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
            guard let id = obj["id"] as? Int, let method = obj["method"] as? String else { return }
            switch method {
            case "session/new":
                lock.lock(); _sessionNewCount += 1; lock.unlock()
                cont.yield(#"{"jsonrpc":"2.0","id":\#(id),"result":{"sessionId":"S"}}"#)
            case "session/prompt":
                cont.yield(#"{"jsonrpc":"2.0","method":"session/update","params":{"update":{"sessionUpdate":"agent_message_chunk","content":{"text":"OK"}}}}"#)
                cont.yield(#"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#)
            default:
                cont.yield(#"{"jsonrpc":"2.0","id":\#(id),"result":{}}"#)  // initialize, etc.
            }
        }
    }

    private let key = ExternalWorkerSession.Key(threadId: "t1", sourceId: "grok", modelId: "grok-build", repoRoot: "/repo")
    private let profile = ACPTransportProfile.grok(model: "grok-build")

    private func answer(_ stream: AsyncThrowingStream<ACPTurnEvent, Error>) async throws -> String {
        var text = ""
        for try await e in stream { if case let .answerDelta(t) = e { text += t } }
        return text
    }

    func testHandshakeHappensOnceAcrossTurns() async throws {
        let transport = AutoACPTransport()
        let worker = WarmWorker(key: key, transport: transport, profile: profile, cwd: "/repo")

        let a1 = try await answer(worker.prompt("turn one"))
        let a2 = try await answer(worker.prompt("turn two"))
        let a3 = try await answer(worker.prompt("turn three"))

        XCTAssertEqual([a1, a2, a3], ["OK", "OK", "OK"])
        XCTAssertEqual(transport.sessionNewCount, 1, "the cold handshake/index must happen ONCE — warm reuse")
    }

    func testShutdownMakesWorkerDead() async throws {
        let transport = AutoACPTransport()
        let worker = WarmWorker(key: key, transport: transport, profile: profile, cwd: "/repo")
        _ = try await answer(worker.prompt("hi"))
        await worker.shutdown()

        let dead = await worker.isDead
        XCTAssertTrue(dead)
        do { _ = try await worker.prompt("again"); XCTFail("dead worker must refuse") }
        catch { XCTAssertEqual(error as? ACPError, .disconnected) }
    }

    func testLastUsedAdvancesWithTurns() async throws {
        let transport = AutoACPTransport()
        let t0 = Date(timeIntervalSince1970: 1000)
        let worker = WarmWorker(key: key, transport: transport, profile: profile, cwd: "/repo", now: t0)
        _ = try await answer(worker.prompt("hi", now: Date(timeIntervalSince1970: 2000)))
        let idleVsOld = await worker.isIdle(since: Date(timeIntervalSince1970: 1500))
        let idleVsNew = await worker.isIdle(since: Date(timeIntervalSince1970: 3000))
        XCTAssertFalse(idleVsOld, "used at t=2000, not idle relative to t=1500")
        XCTAssertTrue(idleVsNew, "idle relative to t=3000")
    }
}
