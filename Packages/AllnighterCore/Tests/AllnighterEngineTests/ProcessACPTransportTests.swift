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
        let transport = try ProcessACPTransport(command: grokPath()!, profile: .grok(model: "grok-build"), cwd: cwd)
        defer { transport.terminate() }
        let session = ACPSession(transport: transport, profile: .grok(model: "grok-build"))

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

    private func agentPath() -> String? {
        for p in ["\(NSHomeDirectory())/.local/bin/agent", "/usr/local/bin/agent", "/opt/homebrew/bin/agent"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "agent"
    }

    /// Live cursor ACP against the real Allnighter repo — proves warm turn-2 latency vs cold `-p`.
    ///   ALLN_CURSOR_ACP_LIVE=1 swift test --package-path Packages/AllnighterCore --filter ProcessACPTransportTests/testLiveCursorWarmTurnsRecallAndStayFast
    func testLiveCursorWarmTurnsRecallAndStayFast() async throws {
        guard ProcessInfo.processInfo.environment["ALLN_CURSOR_ACP_LIVE"] == "1" else {
            throw XCTSkip("set ALLN_CURSOR_ACP_LIVE=1 to run the live cursor ACP integration test")
        }
        let cwd = FileManager.default.currentDirectoryPath
        let transport = try ProcessACPTransport(
            command: agentPath()!, profile: .cursorAgent(model: "composer-2.5"), cwd: cwd)
        defer { transport.terminate() }
        let profile = ACPTransportProfile.cursorAgent(model: "composer-2.5")
        let session = ACPSession(transport: transport, profile: profile)

        try await withTimeout(90) { try await session.start(cwd: cwd) }

        _ = try await withTimeout(90) {
            try await Self.answer(session.prompt("Remember the word amberclock. Reply with just: OK"))
        }

        let t2 = Date()
        let a2 = try await withTimeout(90) {
            try await Self.answer(session.prompt("What single word did I ask you to remember? Reply with ONLY that word."))
        }
        let turn2ms = Int(Date().timeIntervalSince(t2) * 1000)
        print("cursor ACP turn 2: \(turn2ms)ms answer=\(a2.prefix(40))")

        XCTAssertTrue(a2.lowercased().contains("amberclock"), "warm session must recall across turns; got: \(a2)")
        XCTAssertLessThan(turn2ms, 8000, "warm turn-2 should beat cold `-p` (~5s+) per turn")
    }

    private func codexPath() -> String? {
        for p in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(NSHomeDirectory())/.local/bin/codex"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "codex"
    }

    /// Live Codex app-server warm path. GATED:
    ///   ALLN_CODEX_LIVE=1 swift test --package-path Packages/AllnighterCore --filter ProcessACPTransportTests/testLiveCodexWarmTurnsRecallAndStayFast
    func testLiveCodexWarmTurnsRecallAndStayFast() async throws {
        guard ProcessInfo.processInfo.environment["ALLN_CODEX_LIVE"] == "1" else {
            throw XCTSkip("set ALLN_CODEX_LIVE=1 to run the live codex app-server integration test")
        }
        let cwd = NSTemporaryDirectory() + "alln-codex-live-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: cwd) }
        let transport = try ProcessACPTransport(command: codexPath()!, profile: .codex(model: "gpt-5.5"), cwd: cwd)
        defer { transport.terminate() }
        let session = CodexSession(transport: transport, model: "gpt-5.5")

        try await withTimeout(60) { try await session.start(cwd: cwd) }
        _ = try await withTimeout(60) { try await Self.answer(session.prompt("Remember the word amberclock. Reply with just: OK")) }
        let t2 = Date()
        let a2 = try await withTimeout(60) { try await Self.answer(session.prompt("What single word did I ask you to remember? Reply with ONLY that word.")) }
        let turn2ms = Int(Date().timeIntervalSince(t2) * 1000)
        print("codex app-server turn 2: \(turn2ms)ms answer=\(a2.prefix(40))")

        XCTAssertTrue(a2.lowercased().contains("amberclock"), "warm session must recall; got: \(a2)")
        XCTAssertLessThan(turn2ms, 10000, "warm turn-2 should beat cold `codex exec` per turn")
    }
}
