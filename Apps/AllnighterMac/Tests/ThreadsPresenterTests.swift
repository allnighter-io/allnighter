import XCTest
@testable import AllnighterMac
import AllnighterCore

/// Pure view-state for the Work Threads surfaces: triage ordering, turn pills,
/// heartbeat, and the byte-only context size label (no token theater).
final class ThreadsPresenterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func thread(
        _ id: String, updatedAt: Date, pinned: Bool = false, archived: Bool = false, turns: [ThreadTurn] = []
    ) -> WorkThread {
        WorkThread(id: id, title: id, status: archived ? .archived : .active,
                   createdAt: t0, updatedAt: updatedAt, pinnedAt: pinned ? t0 : nil, turns: turns)
    }

    private func turn(_ kind: ThreadTurnKind, _ status: ThreadTurnStatus, systemEvent: SystemEventKind? = nil) -> ThreadTurn {
        ThreadTurn(id: "\(kind.rawValue)-\(status.rawValue)", threadId: "x", kind: kind, status: status,
                   createdAt: t0, author: kind == .workerChat ? .worker : .system, workerId: "worker_opus",
                   systemEvent: systemEvent)
    }

    // MARK: - Triage ordering

    func testTriageOrderFollowsSpec() {
        let attention = thread("attn", updatedAt: t0, turns: [turn(.workerChat, .failed)])
        let pinnedAttention = thread("pinAttn", updatedAt: t0, pinned: true, turns: [turn(.workerChat, .failed)])
        let running = thread("run", updatedAt: t0, turns: [turn(.workerChat, .running)])
        let pinnedRunning = thread("pinRun", updatedAt: t0, pinned: true, turns: [turn(.workerChat, .running)])
        let pinnedIdle = thread("pinIdle", updatedAt: t0, pinned: true)
        let recentNew = thread("recentNew", updatedAt: t0.addingTimeInterval(100))
        let recentOld = thread("recentOld", updatedAt: t0)

        let ordered = ThreadsPresenter.triaged(
            [recentOld, running, pinnedIdle, recentNew, pinnedRunning, attention, pinnedAttention]
        ).map(\.id)

        XCTAssertEqual(ordered, ["pinAttn", "attn", "pinRun", "run", "pinIdle", "recentNew", "recentOld"])
    }

    func testArchivedThreadsExcludedFromTriage() {
        let live = thread("live", updatedAt: t0)
        let archived = thread("archived", updatedAt: t0.addingTimeInterval(999), archived: true)
        XCTAssertEqual(ThreadsPresenter.triaged([archived, live]).map(\.id), ["live"])
    }

    func testRowState() {
        XCTAssertEqual(ThreadsPresenter.rowState(thread("a", updatedAt: t0, turns: [turn(.workerChat, .failed)])), .needsAttention)
        XCTAssertEqual(ThreadsPresenter.rowState(thread("b", updatedAt: t0, turns: [turn(.workerChat, .running)])), .running)
        XCTAssertEqual(ThreadsPresenter.rowState(thread("c", updatedAt: t0)), .idle)
    }

    // MARK: - Turn presentation

    func testPillKindMapping() {
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .queued), .queued)
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .draft), .queued)
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .running), .running)
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .done), .done)
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .failed), .failed)
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .cancelled), .failed)
        XCTAssertEqual(ThreadsPresenter.pillKind(for: .timedOut), .timedOut)
    }

    func testIsLiveAndElapsed() {
        let running = turn(.workerChat, .running)
        XCTAssertTrue(ThreadsPresenter.isLive(running))
        XCTAssertFalse(ThreadsPresenter.isLive(turn(.workerChat, .done)))
        XCTAssertEqual(ThreadsPresenter.elapsedSeconds(running, now: t0.addingTimeInterval(42)), 42)
        XCTAssertEqual(ThreadsPresenter.elapsedSeconds(running, now: t0.addingTimeInterval(-5)), 0)
    }

    func testBodyTextFallsBackToHonestFailureReason() {
        var failed = turn(.workerChat, .failed); failed.text = nil
        XCTAssertEqual(ThreadsPresenter.bodyText(failed), "Worker failed.")
        var timedOut = turn(.workerChat, .timedOut); timedOut.text = nil
        XCTAssertEqual(ThreadsPresenter.bodyText(timedOut), "Worker timed out.")
        var done = turn(.workerChat, .done); done.text = "the answer"
        XCTAssertEqual(ThreadsPresenter.bodyText(done), "the answer")
    }

    func testAuthorLabel() {
        XCTAssertEqual(ThreadsPresenter.authorLabel(turn(.workerChat, .done)), "worker_opus")
        var user = turn(.userMessage, .done); user.author = .user
        XCTAssertEqual(ThreadsPresenter.authorLabel(user), "You")
    }

    // MARK: - No usage theater

    func testContextSizeLabelIsBytesNotTokens() {
        let packet = ThreadContextPacket(id: "p", threadId: "t", turnId: "u", createdAt: t0,
                                         strategy: .recentTurns, text: "hello")
        let label = ThreadsPresenter.contextSizeLabel(packet)
        XCTAssertEqual(label, "5 bytes")
        XCTAssertFalse(label.lowercased().contains("token"))
    }
}
