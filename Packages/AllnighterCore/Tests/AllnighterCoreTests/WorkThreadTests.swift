import XCTest
@testable import AllnighterCore

/// Models, fixtures, derived liveness, family mapping, and turn lifecycle for
/// Persistent Work Threads (PWT-S01).
final class WorkThreadTests: XCTestCase {

    private func assertRoundTrips<T: Codable & Equatable>(_ type: T.Type, _ name: Fixtures.Name) throws {
        let decoded = try Fixtures.decode(type, name)
        let reEncoded = try CoreJSON.encode(decoded)
        let reDecoded = try CoreJSON.decode(type, from: reEncoded)
        XCTAssertEqual(decoded, reDecoded, "Round-trip mismatch for \(name.rawValue)")
    }

    private func assertLegacyThreadRoundTrips(_ name: Fixtures.Name) throws {
        var decoded = try Fixtures.decode(WorkThread.self, name)
        XCTAssertEqual(decoded.formatVersion, 0, "Bundled legacy fixture \(name.rawValue) should decode as v0")
        decoded.upgradeFormatVersionIfNeeded()
        let reEncoded = try CoreJSON.encode(decoded)
        let reDecoded = try CoreJSON.decode(WorkThread.self, from: reEncoded)
        XCTAssertEqual(decoded, reDecoded, "Round-trip mismatch for \(name.rawValue)")
        XCTAssertEqual(reDecoded.formatVersion, WorkThread.currentFormatVersion)
    }

    // MARK: - Round-trip

    func testThreadFixturesRoundTrip() throws {
        try assertLegacyThreadRoundTrips(.threadChat)
        try assertLegacyThreadRoundTrips(.threadImported)
        try assertRoundTrips(ThreadContextPacket.self, .threadContextPacket)
    }

    func testNewThreadDefaultsToCurrentFormatVersion() {
        let thread = WorkThread(id: "t1", title: "T", createdAt: epoch, updatedAt: epoch)
        XCTAssertEqual(thread.formatVersion, WorkThread.currentFormatVersion)
    }

    func testChatThreadShape() throws {
        let thread = try Fixtures.thread(.threadChat)
        XCTAssertEqual(thread.status, .active)
        XCTAssertEqual(thread.turns.count, 3)
        XCTAssertEqual(thread.defaultModelId, "model_opus")
        XCTAssertEqual(thread.workingDir, "/Users/mike/Code/acme")
        // The team turn references a run and carries no inline chat text.
        let teamRun = thread.turns.first { $0.kind == .teamRun }
        XCTAssertEqual(teamRun?.runId, "run_complete_01")
        XCTAssertNil(teamRun?.text)
        XCTAssertEqual(teamRun?.artifactRefs.first?.kind, .plan)
    }

    // MARK: - Derived liveness

    func testDerivedLivenessFromTurns() throws {
        let thread = try Fixtures.thread(.threadChat)
        XCTAssertFalse(thread.isRunning)         // all turns done
        XCTAssertFalse(thread.needsAttention)    // no failed/blocking turns
        XCTAssertEqual(thread.lastModelId, "model_opus")
        XCTAssertEqual(thread.preview, "Start with a single owner-scoped flag before per-seat roles.")
        XCTAssertFalse(thread.isPinned)
    }

    func testRunningIsDerivedFromQueuedOrRunningTurn() {
        var thread = makeEmptyThread()
        thread.turns = [makeTurn(kind: .workerChat, status: .running, author: .worker)]
        XCTAssertTrue(thread.isRunning)
        XCTAssertTrue(thread.hasActiveHeavyTurn == false) // worker_chat is not heavy
    }

    func testNeedsAttentionFromFailedTurn() {
        var thread = makeEmptyThread()
        thread.turns = [makeTurn(kind: .workerChat, status: .failed, author: .worker)]
        XCTAssertTrue(thread.needsAttention)
    }

    func testNeedsAttentionFromBlockingSystemEventOnly() {
        var thread = makeEmptyThread()
        // A benign migration note must NOT raise attention.
        thread.turns = [makeTurn(kind: .systemEvent, status: .done, author: .system, systemEvent: .migrationImported)]
        XCTAssertFalse(thread.needsAttention)
        // An OPEN sign-in / manual-paste note blocks on the user.
        thread.turns = [makeTurn(kind: .systemEvent, status: .running, author: .system, systemEvent: .signInRequired)]
        XCTAssertTrue(thread.needsAttention)
        thread.turns = [makeTurn(kind: .systemEvent, status: .running, author: .system, systemEvent: .manualPaste)]
        XCTAssertTrue(thread.needsAttention)
        // Once resolved (terminal), the same note no longer nags.
        thread.turns = [makeTurn(kind: .systemEvent, status: .done, author: .system, systemEvent: .manualPaste)]
        XCTAssertFalse(thread.needsAttention)
    }

    func testHasActiveHeavyTurn() {
        var thread = makeEmptyThread()
        thread.turns = [makeTurn(kind: .teamRun, status: .running, author: .system)]
        XCTAssertTrue(thread.hasActiveHeavyTurn)
        thread.turns = [makeTurn(kind: .teamRun, status: .done, author: .system)]
        XCTAssertFalse(thread.hasActiveHeavyTurn)
    }

    // MARK: - Family mapping

    func testFamilyMappingCoversEveryKind() {
        let expected: [ThreadTurnKind: TurnFamily] = [
            .userMessage: .message, .userDecision: .message,
            .workerChat: .reply,
            .teamRun: .team, .designBoard: .team, .reviewBoard: .team,
            .mutatingRun: .team,
            .systemEvent: .system,
        ]
        for kind in ThreadTurnKind.allCases {
            XCTAssertEqual(kind.family, expected[kind], "Unmapped family for \(kind.rawValue)")
        }
    }

    func testHeavyKinds() {
        let heavy: Set<ThreadTurnKind> = [.teamRun, .designBoard, .reviewBoard, .mutatingRun]
        for kind in ThreadTurnKind.allCases {
            XCTAssertEqual(kind.isHeavy, heavy.contains(kind), "Wrong heavy flag for \(kind.rawValue)")
        }
    }

    // MARK: - Turn lifecycle / illegal states

    func testTurnLifecycleLegalTransitions() {
        XCTAssertTrue(ThreadTurnStatus.draft.allowedTransitions().contains(.queued))
        XCTAssertTrue(ThreadTurnStatus.queued.allowedTransitions().contains(.running))
        XCTAssertTrue(ThreadTurnStatus.running.allowedTransitions().contains(.done))
        XCTAssertTrue(ThreadTurnStatus.running.allowedTransitions().contains(.timedOut))
        XCTAssertTrue(ThreadTurnStatus.running.allowedTransitions().contains(.cancelled))
    }

    func testTurnLifecycleIllegalTransitions() {
        // Terminal states are sinks.
        for terminal in [ThreadTurnStatus.done, .failed, .timedOut, .cancelled] {
            XCTAssertTrue(terminal.isTerminal)
            XCTAssertTrue(terminal.allowedTransitions().isEmpty, "\(terminal) must be terminal")
        }
        // Cannot jump from draft straight to done, or from queued to done.
        XCTAssertFalse(ThreadTurnStatus.draft.allowedTransitions().contains(.done))
        XCTAssertFalse(ThreadTurnStatus.queued.allowedTransitions().contains(.done))
    }

    func testCanTransitionHelper() {
        let running = makeTurn(kind: .workerChat, status: .running, author: .worker)
        XCTAssertTrue(running.canTransition(to: .done))
        XCTAssertFalse(running.canTransition(to: .queued))
    }

    // MARK: - Helpers

    private func makeEmptyThread() -> WorkThread {
        WorkThread(id: "t1", title: "t", createdAt: epoch, updatedAt: epoch)
    }

    private func makeTurn(
        kind: ThreadTurnKind,
        status: ThreadTurnStatus,
        author: TurnAuthor,
        systemEvent: SystemEventKind? = nil
    ) -> ThreadTurn {
        ThreadTurn(
            id: "turn_\(kind.rawValue)_\(status.rawValue)",
            threadId: "t1",
            kind: kind,
            status: status,
            createdAt: epoch,
            author: author,
            text: author == .worker ? "reply" : nil,
            modelId: author == .worker ? "model_opus" : nil,
            systemEvent: systemEvent
        )
    }

    private let epoch = Date(timeIntervalSince1970: 0)
}
