import XCTest
@testable import AllnighterCore

final class RemoteThreadProjectionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)
    private let t3 = Date(timeIntervalSince1970: 4_000)

    func testReadStateMirrorsUnreadDerivation() {
        let thread = thread(
            turns: [
                turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0),
                turn("w1", status: .done, createdAt: t1, completedAt: t1),
                turn("w2", status: .failed, createdAt: t2, completedAt: t2)
            ],
            readCursor: ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0)
        )

        let readState = RemoteThreadProjection.readState(from: thread)

        XCTAssertEqual(readState.readCursor, thread.readCursor)
        XCTAssertEqual(readState.hasUnread, UnreadDerivation.hasUnread(thread: thread))
        XCTAssertEqual(readState.unreadNeedsAttention, UnreadDerivation.unreadNeedsAttention(thread: thread))
        XCTAssertEqual(readState.firstUnreadTurnId, "w1")
        XCTAssertEqual(readState.latestUnreadTurnId, "w2")
    }

    func testSummaryUsesMacDerivedDisplayStateAndContentLightTurnMetadata() {
        var thread = thread(
            id: "thread_1",
            title: "Design follow-up",
            status: .archived,
            projectId: "project_1",
            pinnedAt: t3,
            turns: [
                turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0),
                turn("run_1", kind: .teamRun, status: .done, author: .worker, createdAt: t1,
                     completedAt: t2, workerId: "codex", runId: "team_run_1", stageId: "stage_1")
            ],
            readCursor: ThreadReadCursor(lastReadTurnId: "run_1", lastReadTurnCreatedAt: t1, readAt: t2)
        )
        thread.updatedAt = t3

        let summary = RemoteThreadProjection.summary(from: thread, hasPendingItem: true)

        XCTAssertEqual(summary.id, "thread_1")
        XCTAssertEqual(summary.title, "Design follow-up")
        XCTAssertEqual(summary.status, .archived)
        XCTAssertEqual(summary.projectId, "project_1")
        XCTAssertEqual(summary.pinnedAt, t3)
        XCTAssertEqual(summary.displayState, .pending)
        XCTAssertEqual(summary.turnCount, 2)
        XCTAssertEqual(summary.latestTurn?.id, "run_1")
        XCTAssertEqual(summary.latestTurn?.kind, .teamRun)
        XCTAssertEqual(summary.latestTurn?.status, .done)
        XCTAssertEqual(summary.latestTurn?.workerId, "codex")
        XCTAssertEqual(summary.latestTurn?.runId, "team_run_1")
        XCTAssertEqual(summary.latestTurn?.stageId, "stage_1")
    }

    func testEncodedSummaryOmitsThreadBodiesReasoningAndLocalPaths() throws {
        let secretText = "private prompt with production token"
        let secretReasoning = "private reasoning trace"
        let thread = WorkThread(
            id: "thread_secret",
            title: "Visible title",
            createdAt: t0,
            updatedAt: t2,
            workingDir: "/Users/mike/private/repo",
            projectLabel: "Secret project label",
            projectId: "project_1",
            localRootPathSnapshot: "/Users/mike/private/repo-old",
            defaultWorkerId: "secret_default_worker",
            readCursor: ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0),
            turns: [
                turn("u1", kind: .userMessage, status: .done, author: .user, createdAt: t0, text: secretText),
                turn("w1", status: .running, createdAt: t1, workerId: "public_worker",
                     text: "visible worker body", reasoningText: secretReasoning)
            ]
        )

        let data = try CoreJSON.encode(RemoteThreadProjection.summary(from: thread))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains(secretText))
        XCTAssertFalse(json.contains(secretReasoning))
        XCTAssertFalse(json.contains("visible worker body"))
        XCTAssertFalse(json.contains("/Users/mike/private/repo"))
        XCTAssertFalse(json.contains("/Users/mike/private/repo-old"))
        XCTAssertFalse(json.contains("Secret project label"))
        XCTAssertFalse(json.contains("secret_default_worker"))
        XCTAssertTrue(json.contains("Visible title"))
        XCTAssertTrue(json.contains("project_1"))
    }

    func testSummariesMarksPendingThreadsById() {
        let first = thread(id: "a", turns: [turn("w1", status: .done)])
        let second = thread(id: "b", turns: [turn("w2", status: .done)])

        let summaries = RemoteThreadProjection.summaries(from: [first, second], pendingThreadIds: ["b"])

        XCTAssertEqual(summaries.map(\.id), ["a", "b"])
        XCTAssertEqual(summaries.first?.displayState, .replied)
        XCTAssertEqual(summaries.last?.displayState, .pending)
    }

    func testSummaryRoundTripsThroughCoreJSON() throws {
        let thread = thread(
            turns: [turn("w1", status: .done, createdAt: t1, completedAt: t1)],
            readCursor: .empty(at: t0)
        )
        let summary = RemoteThreadProjection.summary(from: thread)

        let decoded = try CoreJSON.decode(RemoteThreadSummary.self, from: CoreJSON.encode(summary))

        XCTAssertEqual(decoded, summary)
    }

    private func thread(
        id: String = "thread_1",
        title: String = "Thread",
        status: ThreadStatus = .active,
        projectId: String? = nil,
        pinnedAt: Date? = nil,
        turns: [ThreadTurn],
        readCursor: ThreadReadCursor? = .empty(at: Date(timeIntervalSince1970: 1_000))
    ) -> WorkThread {
        WorkThread(
            id: id,
            title: title,
            status: status,
            createdAt: t0,
            updatedAt: t2,
            pinnedAt: pinnedAt,
            projectId: projectId,
            readCursor: readCursor,
            turns: turns
        )
    }

    private func turn(
        _ id: String,
        kind: ThreadTurnKind = .workerChat,
        status: ThreadTurnStatus = .done,
        author: TurnAuthor = .worker,
        createdAt: Date? = nil,
        completedAt: Date? = nil,
        workerId: String? = nil,
        runId: String? = nil,
        stageId: String? = nil,
        text: String? = nil,
        reasoningText: String? = nil
    ) -> ThreadTurn {
        ThreadTurn(
            id: id,
            threadId: "thread_1",
            kind: kind,
            status: status,
            createdAt: createdAt ?? t1,
            completedAt: completedAt,
            author: author,
            text: text ?? (author == .worker ? "reply" : "message"),
            workerId: workerId,
            runId: runId,
            stageId: stageId,
            reasoningText: reasoningText
        )
    }
}
