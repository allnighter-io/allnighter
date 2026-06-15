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

        try store.save(thread("a", updatedAt: t0))
        let loaded = store.get("a")
        XCTAssertEqual(loaded?.title, "Thread a")
        XCTAssertNil(store.get("missing"))
    }

    func testSaveWritesDerivedTranscript() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var t = thread("a", updatedAt: t0)
        t.turns = [userTurn("u1", threadId: "a")]
        let folder = try store.save(t)
        let transcript = try String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8)
        XCTAssertTrue(transcript.contains("# Thread a"))
        XCTAssertTrue(transcript.contains("hello"))
    }

    func testListSortsByUpdatedAtNewestFirst() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.save(thread("old", updatedAt: t0))
        try store.save(thread("new", updatedAt: t1))
        XCTAssertEqual(store.list().map(\.id), ["new", "old"])
    }

    func testAppendBumpsUpdatedAtAndNormalizesThreadId() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.save(thread("a", updatedAt: t0))
        // Turn carries a stale threadId; append normalizes it.
        let stray = ThreadTurn(id: "u1", threadId: "WRONG", kind: .userMessage,
                               status: .done, createdAt: t0, author: .user, text: "hi")
        let updated = try store.append(stray, toThreadId: "a", now: t1)
        XCTAssertEqual(updated.turns.count, 1)
        XCTAssertEqual(updated.turns[0].threadId, "a")
        XCTAssertEqual(updated.updatedAt, t1)
    }

    func testUpdateSettlesRunningTurn() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.save(thread("a", updatedAt: t0))
        let running = ThreadTurn(id: "w1", threadId: "a", kind: .workerChat, status: .running,
                                 createdAt: t0, author: .worker, workerId: "model_opus")
        try store.append(running, toThreadId: "a", now: t0)

        var done = running
        done.status = .done
        done.text = "answer"
        let updated = try store.update(done, inThreadId: "a", now: t1)
        XCTAssertEqual(updated.turns[0].status, .done)
        XCTAssertEqual(updated.turns[0].text, "answer")
    }

    func testUpdateRejectsIllegalTransition() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.save(thread("a", updatedAt: t0))
        let done = ThreadTurn(id: "w1", threadId: "a", kind: .workerChat, status: .done,
                              createdAt: t0, author: .worker, text: "x", workerId: "model_opus")
        try store.append(done, toThreadId: "a", now: t0)

        var revived = done
        revived.status = .running   // done -> running is illegal
        XCTAssertThrowsError(try store.update(revived, inThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError,
                           .illegalTurnTransition(turnId: "w1", from: .done, to: .running))
        }
    }

    func testUpdateMissingTurnThrows() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(thread("a", updatedAt: t0))
        let ghost = userTurn("ghost", threadId: "a")
        XCTAssertThrowsError(try store.update(ghost, inThreadId: "a", now: t1)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .turnNotFound("ghost"))
        }
    }

    func testAppendToMissingThreadThrows() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try store.append(userTurn("u", threadId: "nope"), toThreadId: "nope", now: t0)) { error in
            XCTAssertEqual(error as? ThreadStoreError, .threadNotFound("nope"))
        }
    }

    func testArchive() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(thread("a", updatedAt: t0))
        let archived = try store.archive("a", now: t1)
        XCTAssertEqual(archived.status, .archived)
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(store.get("a")?.status, .archived)
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
        try store.save(t)
        try store.save(thread("b", updatedAt: t1))   // no runs

        XCTAssertEqual(store.threadId(forRunId: "run_42"), "a")
        XCTAssertNil(store.threadId(forRunId: "run_unknown"))
        XCTAssertEqual(store.runToThreadIndex(), ["run_42": "a"])
    }
}
