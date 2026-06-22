import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// Warm_Single_Lane_Chat §4b: live integration of the real ACP transport against `grok agent stdio`.
/// GATED — spawns grok (network + quota). Run explicitly:
///   ALLN_ACP_LIVE=1 swift test --package-path Packages/AllnighterCore --filter ProcessACPTransportTests
/// Otherwise it skips so the green wall stays offline/fast.
final class ProcessACPTransportTests: XCTestCase {

    private func grokPath() -> String? {
        for p in ["\(NSHomeDirectory())/.local/bin/grok", "/usr/local/bin/grok", "/opt/homebrew/bin/grok"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "grok"  // fall back to PATH via /usr/bin/env
    }

    private static func answer(_ stream: AsyncThrowingStream<ACPTurnEvent, Error>) async throws -> String {
        var text = ""
        for try await e in stream { if case let .answerDelta(t) = e { text += t } }
        return text
    }

    /// Fail fast instead of hanging forever if the transport never responds.
    private func withTimeout<T: Sendable>(_ seconds: Double, _ op: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); throw ACPError.disconnected }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func testLiveWarmTurnsRecallAndStayFast() async throws {
        guard ProcessInfo.processInfo.environment["ALLN_ACP_LIVE"] == "1" else {
            throw XCTSkip("set ALLN_ACP_LIVE=1 to run the live grok ACP integration test")
        }
        // A CLEAN temp dir so we validate the TRANSPORT, not repo-walk speed. (`swift test`'s cwd
        // is the package dir, which carries a ~528M .build that grok would index for tens of seconds.)
        let cwd = NSTemporaryDirectory() + "alln-acp-live-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: cwd) }
        let transport = try ProcessACPTransport(command: grokPath()!, model: "grok-build", cwd: cwd)
        defer { transport.terminate() }
        let session = ACPSession(transport: transport)

        let t0 = Date()
        try await withTimeout(60) { try await session.start(cwd: cwd) }
        print("ACP start (handshake + session/new): \(Int(Date().timeIntervalSince(t0) * 1000))ms")

        let t1 = Date()
        let a1 = try await withTimeout(60) { try await Self.answer(session.prompt("Remember the word amberclock. Reply with just: OK")) }
        print("turn 1: \(Int(Date().timeIntervalSince(t1) * 1000))ms answer=\(a1.prefix(40))")

        let t2 = Date()
        let a2 = try await withTimeout(60) { try await Self.answer(session.prompt("What single word did I ask you to remember? Reply with ONLY that word.")) }
        let turn2ms = Int(Date().timeIntervalSince(t2) * 1000)
        print("turn 2: \(turn2ms)ms answer=\(a2.prefix(40))")

        XCTAssertTrue(a2.lowercased().contains("amberclock"), "warm session must recall across turns; got: \(a2)")
        XCTAssertLessThan(turn2ms, 15000, "warm turn-2 should be fast, not a 22s cold walk")
    }
}
