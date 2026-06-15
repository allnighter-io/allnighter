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

    // MARK: - Round-trip

    func testThreadFixturesRoundTrip() throws {
        try assertRoundTrips(WorkThread.self, .threadChat)
        try assertRoundTrips(WorkThread.self, .threadImported)
        try assertRoundTrips(ThreadContextPacket.self, .threadContextPacket)
    }

    func testChatThreadShape() throws {
        let thread = try Fixtures.thread(.threadChat)
        XCTAssertEqual(thread.status, .active)
        XCTAssertEqual(thread.turns.count, 3)
        XCTAssertEqual(thread.defaultWorkerId, "worker_opus")
        XCTAssertEqual(thread.workingDir, "/Users/mike/Code/acme")
        // The council turn references a run and carries no inline chat text.
        let council = thread.turns.first { $0.kind == .councilRun }
        XCTAssertEqual(council?.runId, "run_complete_01")
        XCTAssertNil(council?.text)
        XCTAssertEqual(council?.artifactRefs.first?.kind, .masterPlan)
    }

    // MARK: - Derived liveness

    func testDerivedLivenessFromTurns() throws {
        let thread = try Fixtures.thread(.threadChat)
        XCTAssertFalse(thread.isRunning)         // all turns done
        XCTAssertFalse(thread.needsAttention)    // no failed/blocking turns
        XCTAssertEqual(thread.lastWorkerId, "worker_opus")
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
        // Sign-in and manual-paste notes block on the user.
        thread.turns = [makeTurn(kind: .systemEvent, status: .done, author: .system, systemEvent: .signInRequired)]
        XCTAssertTrue(thread.needsAttention)
        thread.turns = [makeTurn(kind: .systemEvent, status: .done, author: .system, systemEvent: .manualPaste)]
        XCTAssertTrue(thread.needsAttention)
    }

    func testHasActiveHeavyTurn() {
        var thread = makeEmptyThread()
        thread.turns = [makeTurn(kind: .councilRun, status: .running, author: .system)]
        XCTAssertTrue(thread.hasActiveHeavyTurn)
        thread.turns = [makeTurn(kind: .councilRun, status: .done, author: .system)]
        XCTAssertFalse(thread.hasActiveHeavyTurn)
    }

    // MARK: - Family mapping

    func testFamilyMappingCoversEveryKind() {
        let expected: [ThreadTurnKind: TurnFamily] = [
            .userMessage: .message, .userDecision: .message,
            .workerChat: .reply,
            .councilRun: .council, .designBoard: .council, .reviewBoard: .council,
            .workOrder: .build, .dispatch: .build, .returnReview: .build,
            .systemEvent: .system,
        ]
        for kind in ThreadTurnKind.allCases {
            XCTAssertEqual(kind.family, expected[kind], "Unmapped family for \(kind.rawValue)")
        }
    }

    func testHeavyKinds() {
        let heavy: Set<ThreadTurnKind> = [.councilRun, .designBoard, .reviewBoard, .dispatch, .returnReview]
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
            workerId: author == .worker ? "worker_opus" : nil,
            systemEvent: systemEvent
        )
    }

    private let epoch = Date(timeIntervalSince1970: 0)
}
