import XCTest
@testable import AllnighterCore
@testable import AllnighterEngine

/// ThreadStore CRUD, append/update lifecycle guard, archive, and the derived
/// run→thread inverse index (PWT-S02 + PWT-S03).
final class ThreadStoreTests: XCTestCase {

    private func tempStore() -> (ThreadStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("threadstore-\(UUID().uuidString)")
        return (ThreadStore(rootDirectory: dir), dir)
    }

    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)
    private let t3 = Date(timeIntervalSince1970: 4_000)

    private func thread(_ id: String, updatedAt: Date) -> WorkThread {
        WorkThread(id: id, title: "Thread \(id)", createdAt: t0, updatedAt: updatedAt)
    }

    private func userTurn(_ id: String, threadId: String) -> ThreadTurn {
        ThreadTurn(id: id, threadId: threadId, kind: .userMessage, status: .done,
                   createdAt: t0, author: .user, text: "hello")
    }

    func testSaveGetRoundTrip() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        let loaded = store.get("a")
        XCTAssertEqual(loaded?.title, "Thread a")
        XCTAssertNil(store.get("missing"))
    }

    func testSaveWritesDerivedTranscript() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var t = thread("a", updatedAt: t0)
        t.turns = [userTurn("u1", threadId: "a")]
        let folder = try store.saveForImport(t)
        let transcript = try String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8)
        XCTAssertTrue(transcript.contains("# Thread a"))
        XCTAssertTrue(transcript.contains("hello"))
    }

    func testListSortsByUpdatedAtNewestFirst() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("old", updatedAt: t0))
        try store.saveForImport(thread("new", updatedAt: t1))
        XCTAssertEqual(store.list().map(\.id), ["new", "old"])
    }

    func testAppendBumpsUpdatedAtAndNormalizesThreadId() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        // Turn carries a stale threadId; append normalizes it.
        let stray = ThreadTurn(id: "u1", threadId: "WRONG", kind: .userMessage,
                               status: .done, createdAt: t0, author: .user, text: "hi")
        let updated = try store.appendTurn(stray, toThreadId: "a", now: t1)
        XCTAssertEqual(updated.turns.count, 1)
        XCTAssertEqual(updated.turns[0].threadId, "a")
        XCTAssertEqual(updated.updatedAt, t1)
    }

    func testUpdateSettlesRunningTurn() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        let running = ThreadTurn(id: "w1", threadId: "a", kind: .workerChat, status: .running,
                                 createdAt: t0, author: .worker, workerId: "model_opus")
        try store.appendTurn(running, toThreadId: "a", now: t0)

        var done = running
        done.status = .done
        done.text = "answer"
        let updated = try store.updateTurn(done, inThreadId: "a", now: t1)
        XCTAssertEqual(updated.turns[0].status, .done)
        XCTAssertEqual(updated.turns[0].text, "answer")
    }

    func testUpdateRejectsIllegalTransition() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        let done = ThreadTurn(id: "w1", threadId: "a", kind: .workerChat, status: .done,
                              createdAt: t0, author: .worker, text: "x", workerId: "model_opus")
        try store.appendTurn(done, toThreadId: "a", now: t0)

        var revived = done
        revived.status = .running   // done -> running is illegal
        XCTAssertThrowsError(try store.updateTurn(revived, inThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError,
                           .illegalTurnTransition(turnId: "w1", from: .done, to: .running))
        }
    }

    func testUpdateMissingTurnThrows() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveForImport(thread("a", updatedAt: t0))
        let ghost = userTurn("ghost", threadId: "a")
        XCTAssertThrowsError(try store.updateTurn(ghost, inThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .turnNotFound("ghost"))
        }
    }

    func testAppendToMissingThreadThrows() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try store.appendTurn(userTurn("u", threadId: "nope"), toThreadId: "nope", now: t0)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .threadNotFound("nope"))
        }
    }

    func testCreateRejectsDuplicateThreadId() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try store.create(id: "a", title: "First", now: t0)
        XCTAssertThrowsError(try store.create(id: "a", title: "Second", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .threadAlreadyExists("a"))
        }
        XCTAssertEqual(store.get("a")?.title, "First")
    }

    func testAppendRejectsDuplicateTurnId() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        try store.appendTurn(userTurn("u1", threadId: "a"), toThreadId: "a", now: t0)
        XCTAssertThrowsError(try store.appendTurn(userTurn("u1", threadId: "a"), toThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .duplicateTurnId("u1"))
        }
        XCTAssertEqual(store.get("a")?.turns.count, 1)
    }

    func testSaveWritesCurrentFormatVersion() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try store.create(id: "a", title: "Thread a", now: t0)
        let json = try Data(contentsOf: dir.appendingPathComponent("thread_a/thread.json"))
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(object?["formatVersion"] as? Int, WorkThread.currentFormatVersion)
        XCTAssertEqual(store.get("a")?.formatVersion, WorkThread.currentFormatVersion)
    }

    func testLegacyThreadUpgradesFormatVersionOnSave() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var legacy = try Fixtures.thread(.threadChat)
        XCTAssertEqual(legacy.formatVersion, 0)
        legacy.id = "legacy"
        try store.saveForImport(legacy)
        XCTAssertEqual(store.get("legacy")?.formatVersion, WorkThread.currentFormatVersion)
    }

    func testArchiveThreadPreservesUpdatedAtAndClearsPin() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.pinnedAt = t0
        try store.saveForImport(seeded)
        let archived = try store.archiveThread(threadId: "a")
        XCTAssertEqual(archived.status, .archived)
        XCTAssertNil(archived.pinnedAt)
        XCTAssertEqual(archived.updatedAt, t0)
        XCTAssertEqual(store.get("a")?.updatedAt, t0)
    }

    func testRenameThreadPreservesUpdatedAt() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        let renamed = try store.renameThread(threadId: "a", title: "Renamed")
        XCTAssertEqual(renamed.title, "Renamed")
        XCTAssertEqual(renamed.updatedAt, t0)
        XCTAssertEqual(store.list().map(\.id), ["a"])
    }

    func testRenameThreadRejectsEmptyTitle() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveForImport(thread("a", updatedAt: t0))
        XCTAssertThrowsError(try store.renameThread(threadId: "a", title: "   ")) { error in
            XCTAssertEqual(error as? ThreadStoreError, .emptyTitle)
        }
    }

    func testSetPinnedDoesNotChangeTranscriptBytes() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [userTurn("u1", threadId: "a")]
        let folder = try store.saveForImport(seeded)
        let transcriptURL = folder.appendingPathComponent("transcript.md")
        let before = try Data(contentsOf: transcriptURL)

        _ = try store.setPinned(threadId: "a", pinned: true, now: t1)
        let after = try Data(contentsOf: transcriptURL)
        XCTAssertEqual(before, after)
        XCTAssertEqual(store.get("a")?.updatedAt, t0)
        XCTAssertEqual(store.get("a")?.pinnedAt, t1)
    }

    func testCannotPinArchivedThread() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveForImport(thread("a", updatedAt: t0))
        _ = try store.archiveThread(threadId: "a")
        XCTAssertThrowsError(try store.setPinned(threadId: "a", pinned: true, now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .cannotPinArchivedThread("a"))
        }
    }

    func testUnarchiveThread() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveForImport(thread("a", updatedAt: t0))
        _ = try store.archiveThread(threadId: "a")
        let restored = try store.unarchiveThread(threadId: "a")
        XCTAssertEqual(restored.status, .active)
        XCTAssertNil(restored.pinnedAt)
        XCTAssertEqual(restored.updatedAt, t0)
    }

    func testArchive() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveForImport(thread("a", updatedAt: t0))
        let archived = try store.archiveThread(threadId: "a")
        XCTAssertEqual(archived.status, .archived)
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(store.get("a")?.status, .archived)
    }

    func testArchiveDoesNotRegenerateTranscriptBytes() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [userTurn("u1", threadId: "a")]
        let folder = try store.saveForImport(seeded)
        let transcriptURL = folder.appendingPathComponent("transcript.md")
        let before = try Data(contentsOf: transcriptURL)

        _ = try store.archiveThread(threadId: "a")
        let after = try Data(contentsOf: transcriptURL)
        XCTAssertEqual(before, after)
    }

    func testPersistCursorLeavesTranscriptBytesIdentical() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [userTurn("u1", threadId: "a")]
        let folder = try store.saveForImport(seeded)
        let transcriptURL = folder.appendingPathComponent("transcript.md")
        let before = try Data(contentsOf: transcriptURL)
        let updatedAt = seeded.updatedAt

        guard store.get("a") != nil else {
            return XCTFail("missing thread")
        }
        _ = try store.testPersistCursor(threadId: "a")
        let after = try Data(contentsOf: transcriptURL)
        XCTAssertEqual(before, after)
        XCTAssertEqual(store.get("a")?.updatedAt, updatedAt)
    }

    func testAppendTurnRejectsMissingContextPacket() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        let turn = ThreadTurn(
            id: "w1", threadId: "a", kind: .workerChat, status: .done,
            createdAt: t0, author: .worker, text: "hi", workerId: "model_opus",
            contextPacketId: "missing-packet"
        )
        XCTAssertThrowsError(try store.appendTurn(turn, toThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .missingContextPacket("missing-packet"))
        }
        XCTAssertTrue(store.get("a")?.turns.isEmpty ?? false)
    }

    func testUpdateTurnRejectsMissingContextPacket() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("a", updatedAt: t0))
        let running = ThreadTurn(
            id: "w1", threadId: "a", kind: .workerChat, status: .running,
            createdAt: t0, author: .worker, workerId: "model_opus"
        )
        try store.appendTurn(running, toThreadId: "a", now: t0)

        var settled = running
        settled.status = .done
        settled.text = "answer"
        settled.contextPacketId = "missing-packet"
        XCTAssertThrowsError(try store.updateTurn(settled, inThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .missingContextPacket("missing-packet"))
        }
        XCTAssertEqual(store.get("a")?.turns.first?.status, .running)
    }

    func testRenameAloneDoesNotChangeListRecencyOrder() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveForImport(thread("old", updatedAt: t0))
        try store.saveForImport(thread("new", updatedAt: t1))
        _ = try store.renameThread(threadId: "old", title: "Renamed old")
        XCTAssertEqual(store.list().map(\.id), ["new", "old"])
    }

    func testSaveForImportPreservesCallerUpdatedAt() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let imported = thread("a", updatedAt: t0)
        _ = try store.saveForImport(imported)
        XCTAssertEqual(store.get("a")?.updatedAt, t0)
    }

    // MARK: - Derived run -> thread index (PWT-S02)

    func testRunToThreadIndexIsDerivedFromTurns() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var t = thread("a", updatedAt: t0)
        t.turns = [
            userTurn("u1", threadId: "a"),
            ThreadTurn(id: "c1", threadId: "a", kind: .teamRun, status: .done,
                       createdAt: t0, author: .system, runId: "run_42"),
        ]
        try store.saveForImport(t)
        try store.saveForImport(thread("b", updatedAt: t1))   // no runs

        XCTAssertEqual(store.threadId(forRunId: "run_42"), "a")
        XCTAssertNil(store.threadId(forRunId: "run_unknown"))
        XCTAssertEqual(store.runToThreadIndex(), ["run_42": "a"])
    }

    // MARK: - Read cursor (UNR-S02)

    private func workerTurn(
        _ id: String, threadId: String, status: ThreadTurnStatus, at: Date, text: String? = "reply"
    ) -> ThreadTurn {
        ThreadTurn(
            id: id, threadId: threadId, kind: .workerChat, status: status,
            createdAt: at, completedAt: status.isTerminal ? at : nil,
            author: .worker, text: text, workerId: "model_opus"
        )
    }

    func testCreateInitializesEmptyReadCursor() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let created = try store.create(id: "a", title: "A", now: t0)
        XCTAssertEqual(created.readCursor?.lastReadTurnId, nil)
        XCTAssertEqual(created.readCursor?.readAt, t0)
        XCTAssertFalse(created.hasUnread)
    }

    func testMarkReadPreservesUpdatedAtAndTranscript() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [
            userTurn("u1", threadId: "a"),
            workerTurn("w1", threadId: "a", status: .done, at: t1),
        ]
        seeded.readCursor = ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0)
        let folder = try store.saveForImport(seeded)
        let transcriptURL = folder.appendingPathComponent("transcript.md")
        let before = try Data(contentsOf: transcriptURL)

        let marked = try store.markRead(threadId: "a", throughTurnId: "w1", now: t2)
        let after = try Data(contentsOf: transcriptURL)
        XCTAssertEqual(before, after)
        XCTAssertEqual(marked.updatedAt, t0)
        XCTAssertEqual(marked.readCursor?.lastReadTurnId, "w1")
        XCTAssertFalse(marked.hasUnread)
    }

    func testLegacyThreadBaselinesOnAppendWithoutUnreadStorm() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var legacy = thread("a", updatedAt: t0)
        legacy.turns = [workerTurn("w-old", threadId: "a", status: .done, at: t0)]
        legacy.readCursor = nil
        try store.saveForImport(legacy)

        let updated = try store.appendTurn(
            workerTurn("w-new", threadId: "a", status: .done, at: t1),
            toThreadId: "a",
            now: t1
        )
        XCTAssertEqual(updated.readCursor?.lastReadTurnId, "w-old")
        XCTAssertTrue(updated.hasUnread)
        XCTAssertEqual(updated.firstUnreadTurnId, "w-new")
        XCTAssertFalse(UnreadDerivation.unreadTurnIds(thread: updated).contains("w-old"))
    }

    func testLegacyRunningSettleBaselinesThroughPriorTurn() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var legacy = thread("a", updatedAt: t0)
        legacy.turns = [
            userTurn("u1", threadId: "a"),
            workerTurn("w-run", threadId: "a", status: .running, at: t0),
        ]
        legacy.readCursor = nil
        try store.saveForImport(legacy)

        var settled = legacy.turns[1]
        settled.status = .done
        settled.text = "landed"
        settled.completedAt = t1
        let updated = try store.updateTurn(settled, inThreadId: "a", now: t1)

        XCTAssertEqual(updated.readCursor?.lastReadTurnId, "u1")
        XCTAssertTrue(updated.hasUnread)
        XCTAssertEqual(updated.firstUnreadTurnId, "w-run")
    }

    func testMarkReadToLatestVisibleRequiresContiguousPrefix() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [
            userTurn("u1", threadId: "a"),
            workerTurn("w1", threadId: "a", status: .done, at: t1),
            userTurn("u2", threadId: "a"),
            workerTurn("w2", threadId: "a", status: .done, at: t2),
        ]
        seeded.readCursor = ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0)
        try store.saveForImport(seeded)

        let noop = try store.markReadToLatestVisible(threadId: "a", visibleTurnIds: ["w2"], now: t2)
        XCTAssertTrue(noop.hasUnread)
        XCTAssertEqual(noop.firstUnreadTurnId, "w1")

        let partial = try store.markReadToLatestVisible(
            threadId: "a", visibleTurnIds: ["w1", "u2"], now: t2
        )
        XCTAssertTrue(partial.hasUnread)
        XCTAssertEqual(partial.readCursor?.lastReadTurnId, "w1")

        let cleared = try store.markReadToLatestVisible(
            threadId: "a", visibleTurnIds: ["w1", "u2", "w2"], now: t3
        )
        XCTAssertFalse(cleared.hasUnread)
        XCTAssertEqual(cleared.readCursor?.lastReadTurnId, "w2")
    }

    func testMarkReadDoesNotAdvanceThroughUserTurnWithEarlierUnread() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [
            userTurn("u1", threadId: "a"),
            workerTurn("w1", threadId: "a", status: .done, at: t1),
            userTurn("u2", threadId: "a"),
        ]
        seeded.readCursor = ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0)
        try store.saveForImport(seeded)

        let result = try store.markRead(threadId: "a", throughTurnId: "u2", now: t2)
        XCTAssertTrue(result.hasUnread)
        XCTAssertEqual(result.readCursor?.lastReadTurnId, "u1")
    }

    func testMarkReadNeverMovesCursorBackward() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded = thread("a", updatedAt: t0)
        seeded.turns = [
            workerTurn("w1", threadId: "a", status: .done, at: t0),
            userTurn("u1", threadId: "a"),
            workerTurn("w2", threadId: "a", status: .done, at: t2),
        ]
        seeded.readCursor = ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t1, readAt: t1)
        try store.saveForImport(seeded)

        _ = try store.markRead(threadId: "a", throughTurnId: "w1", now: t2)
        let loaded = store.get("a")
        XCTAssertEqual(loaded?.readCursor?.lastReadTurnId, "u1")
    }
}
