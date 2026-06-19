import XCTest
@testable import AllnighterMac
import AllnighterCore

/// Pure view-state for the Work Threads surfaces: triage ordering, turn pills,
/// heartbeat, and the byte-only context size label (no token theater).
final class ThreadsPresenterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    private func thread(
        _ id: String, updatedAt: Date, pinned: Bool = false, archived: Bool = false,
        readCursor: ThreadReadCursor? = nil, turns: [ThreadTurn] = []
    ) -> WorkThread {
        WorkThread(id: id, title: id, status: archived ? .archived : .active,
                   createdAt: t0, updatedAt: updatedAt, pinnedAt: pinned ? t0 : nil,
                   readCursor: readCursor, turns: turns)
    }

    private func turn(_ kind: ThreadTurnKind, _ status: ThreadTurnStatus, systemEvent: SystemEventKind? = nil) -> ThreadTurn {
        ThreadTurn(id: "\(kind.rawValue)-\(status.rawValue)", threadId: "x", kind: kind, status: status,
                   createdAt: t0, completedAt: status.isTerminal ? t1 : nil,
                   author: kind == .workerChat ? .worker : .system, workerId: "model_opus",
                   systemEvent: systemEvent)
    }

    // MARK: - Triage ordering

    func testTriageOrderFollowsSpec() {
        let attention = thread("attn", updatedAt: t0, turns: [turn(.workerChat, .failed)])
        let pinnedAttention = thread("pinAttn", updatedAt: t0, pinned: true, turns: [turn(.workerChat, .failed)])
        let unread = thread("unread", updatedAt: t0, readCursor: .empty(at: t0),
                            turns: [turn(.workerChat, .done)])
        let pinnedUnread = thread("pinUnread", updatedAt: t0, pinned: true, readCursor: .empty(at: t0),
                                  turns: [turn(.workerChat, .done)])
        let running = thread("run", updatedAt: t0, turns: [turn(.workerChat, .running)])
        let pinnedRunning = thread("pinRun", updatedAt: t0, pinned: true, turns: [turn(.workerChat, .running)])
        let pinnedIdle = thread("pinIdle", updatedAt: t0, pinned: true)
        let recentNew = thread("recentNew", updatedAt: t0.addingTimeInterval(100))
        let recentOld = thread("recentOld", updatedAt: t0)

        let ordered = ThreadsPresenter.triaged(
            [recentOld, unread, running, pinnedIdle, recentNew, pinnedRunning, attention, pinnedAttention, pinnedUnread]
        ).map(\.id)

        XCTAssertEqual(
            ordered,
            ["pinAttn", "attn", "pinUnread", "unread", "pinRun", "run", "pinIdle", "recentNew", "recentOld"]
        )
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

    func testUnreadFreshnessSeparateFromRowState() {
        let unread = thread("u", updatedAt: t0, readCursor: .empty(at: t0), turns: [turn(.workerChat, .done)])
        XCTAssertEqual(ThreadsPresenter.rowState(unread), .idle)
        XCTAssertTrue(ThreadsPresenter.showsUnreadLight(unread))
        XCTAssertEqual(ThreadsPresenter.firstUnreadTurnId(unread), unread.turns[0].id)

        let failedUnread = thread("f", updatedAt: t0, readCursor: .empty(at: t0), turns: [turn(.workerChat, .failed)])
        XCTAssertEqual(ThreadsPresenter.rowState(failedUnread), .needsAttention)
        XCTAssertTrue(ThreadsPresenter.showsUnreadLight(failedUnread))
        XCTAssertTrue(ThreadsPresenter.unreadNeedsAttention(failedUnread))

        let runningNoUnread = thread("r", updatedAt: t0, readCursor: .empty(at: t0),
                                     turns: [turn(.workerChat, .running)])
        XCTAssertEqual(ThreadsPresenter.rowState(runningNoUnread), .running)
        XCTAssertFalse(ThreadsPresenter.showsUnreadLight(runningNoUnread))
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
        XCTAssertEqual(ThreadsPresenter.authorLabel(turn(.workerChat, .done)), "model_opus")
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

    func testConversationStatus() {
        let replied = thread("r", updatedAt: t0, turns: [turn(.workerChat, .done)])
        XCTAssertEqual(ThreadsPresenter.conversationStatus(for: replied), .replied)

        let running = thread("run", updatedAt: t0, turns: [turn(.workerChat, .running)])
        XCTAssertEqual(ThreadsPresenter.conversationStatus(for: running), .running)
    }

    // MARK: - Rail filter / search / grouping (CR4e)

    private func textTurn(_ kind: ThreadTurnKind, _ text: String) -> ThreadTurn {
        ThreadTurn(id: "\(kind.rawValue)-txt", threadId: "x", kind: kind, status: .done,
                   createdAt: t0, author: .worker, text: text)
    }

    func testLaneInference() {
        XCTAssertEqual(ThreadsPresenter.lane(of: thread("d", updatedAt: t0, turns: [turn(.designBoard, .done)])), .design)
        XCTAssertEqual(ThreadsPresenter.lane(of: thread("b", updatedAt: t0, turns: [turn(.teamRun, .done)])), .code)
        XCTAssertEqual(ThreadsPresenter.lane(of: thread("b2", updatedAt: t0, turns: [turn(.mutatingRun, .done)])), .code)
        XCTAssertNil(ThreadsPresenter.lane(of: thread("chat", updatedAt: t0, turns: [turn(.workerChat, .done)])))
        XCTAssertNil(ThreadsPresenter.lane(of: thread("empty", updatedAt: t0)))
    }

    func testRailFilterByLaneAndRunning() {
        let design = thread("d", updatedAt: t0, turns: [turn(.designBoard, .done)])
        let build = thread("b", updatedAt: t0, turns: [turn(.teamRun, .done)])
        let runningBuild = thread("rb", updatedAt: t0, turns: [turn(.mutatingRun, .running)])
        let chat = thread("c", updatedAt: t0, turns: [turn(.workerChat, .done)])
        let all = [design, build, runningBuild, chat]

        XCTAssertEqual(Set(ThreadsPresenter.railThreads(all, filter: .all, search: "").map(\.id)),
                       ["d", "b", "rb", "c"])
        XCTAssertEqual(ThreadsPresenter.railThreads(all, filter: .design, search: "").map(\.id), ["d"])
        XCTAssertEqual(Set(ThreadsPresenter.railThreads(all, filter: .code, search: "").map(\.id)),
                       ["b", "rb"])
        XCTAssertEqual(ThreadsPresenter.railThreads(all, filter: .running, search: "").map(\.id), ["rb"])
    }

    func testRailSearchMatchesTitleAndTurnText() {
        let byTitle = WorkThread(id: "t1", title: "Rate-limit the API", status: .active,
                                 createdAt: t0, updatedAt: t0)
        let byText = WorkThread(id: "t2", title: "Misc", status: .active, createdAt: t0, updatedAt: t0,
                                turns: [textTurn(.workerChat, "use a token bucket here")])
        let neither = WorkThread(id: "t3", title: "Profile redesign", status: .active, createdAt: t0, updatedAt: t0)
        let all = [byTitle, byText, neither]

        XCTAssertEqual(ThreadsPresenter.railThreads(all, filter: .all, search: "rate-limit").map(\.id), ["t1"])
        XCTAssertEqual(ThreadsPresenter.railThreads(all, filter: .all, search: "TOKEN").map(\.id), ["t2"])
        XCTAssertEqual(ThreadsPresenter.railThreads(all, filter: .all, search: "  ").map(\.id).count, 3,
                       "blank search is a no-op")
        XCTAssertTrue(ThreadsPresenter.railThreads(all, filter: .all, search: "zzz").isEmpty)
    }

    func testRailGroupsSplitPinnedFromRecent() {
        let pinned = thread("p", updatedAt: t0, pinned: true, turns: [turn(.teamRun, .done)])
        let recent = thread("r", updatedAt: t0.addingTimeInterval(100), turns: [turn(.teamRun, .done)])
        let sections = ThreadsPresenter.triageSections([recent, pinned], filter: .all, search: "")

        XCTAssertEqual(sections.map(\.id), ["recent"])
        XCTAssertEqual(sections.first?.threads.map(\.id), ["p", "r"])
    }

    func testRailGroupsOmitsEmptySections() {
        let recent = thread("r", updatedAt: t0)
        let sections = ThreadsPresenter.triageSections([recent], filter: .all, search: "")
        XCTAssertEqual(sections.map(\.id), ["recent"], "idle thread lands in Recent only")
    }

    func testTriagedArchivedExcludesActive() {
        let live = thread("live", updatedAt: t0)
        let archived = thread("archived", updatedAt: t0.addingTimeInterval(999), archived: true)
        XCTAssertEqual(ThreadsPresenter.triagedArchived([archived, live]).map(\.id), ["archived"])
        XCTAssertEqual(ThreadsPresenter.triagedActive([archived, live]).map(\.id), ["live"])
    }

    func testTriageSectionsMirrorFamiliesNotPinnedRecent() {
        let unread = thread("u", updatedAt: t0, readCursor: .empty(at: t0), turns: [turn(.workerChat, .done)])
        let running = thread("r", updatedAt: t0, turns: [turn(.workerChat, .running)])
        let sections = ThreadsPresenter.triageSections([running, unread], filter: .all, search: "")
        XCTAssertEqual(sections.map(\.title), ["Unread", "Running"])
    }

    func testUnreadBeatsRunningInBucket() {
        let unreadRunning = thread("ur", updatedAt: t0, readCursor: .empty(at: t0),
                                   turns: [turn(.workerChat, .running), turn(.workerChat, .done)])
        XCTAssertEqual(ThreadsPresenter.triageBucket(for: unreadRunning), .unread)
    }

    func testAttentionBeatsUnreadInBucket() {
        let both = thread("both", updatedAt: t0, readCursor: .empty(at: t0),
                          turns: [turn(.workerChat, .failed)])
        XCTAssertEqual(ThreadsPresenter.triageBucket(for: both), .attention)
        XCTAssertTrue(ThreadsPresenter.showsUnreadLight(both))
    }
}
