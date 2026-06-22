import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteThreadSnapshotServiceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)
    private let t3 = Date(timeIntervalSince1970: 4_000)

    func testSnapshotListsActiveThreadsNewestFirstWithLimit() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThreadStore(rootDirectory: root)
        try save(thread(id: "old", updatedAt: t0), store: store)
        try save(thread(id: "archived", status: .archived, updatedAt: t3), store: store)
        try save(thread(id: "new", updatedAt: t2), store: store)
        try save(thread(id: "middle", updatedAt: t1), store: store)
        let fixedNow = t3
        let service = RemoteThreadSnapshotService(
            threadStore: store,
            policy: RemoteThreadSnapshotPolicy(maxThreads: 2),
            now: { fixedNow }
        )

        let snapshot = service.snapshot()

        XCTAssertEqual(snapshot.protocolVersion, RemoteProtocol.currentMajor)
        XCTAssertEqual(snapshot.serverTime, t3)
        XCTAssertEqual(snapshot.threads.map(\.id), ["new", "middle"])
        XCTAssertFalse(snapshot.threads.contains { $0.status == .archived })
    }

    func testSnapshotCanIncludeArchivedThreadsWhenPolicyAllows() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThreadStore(rootDirectory: root)
        try save(thread(id: "active", updatedAt: t1), store: store)
        try save(thread(id: "archived", status: .archived, updatedAt: t2), store: store)
        let fixedNow = t3
        let service = RemoteThreadSnapshotService(
            threadStore: store,
            policy: RemoteThreadSnapshotPolicy(includeArchived: true),
            now: { fixedNow }
        )

        let snapshot = service.snapshot()

        XCTAssertEqual(snapshot.threads.map(\.id), ["archived", "active"])
        XCTAssertEqual(snapshot.thread(id: "archived")?.status, .archived)
    }

    func testPendingThreadIdsDriveDisplayStateWithoutStoreMutation() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThreadStore(rootDirectory: root)
        let readCursor = ThreadReadCursor(lastReadTurnId: "w1", lastReadTurnCreatedAt: t1, readAt: t2)
        try save(thread(id: "pending", turns: [turn("w1", createdAt: t1)], readCursor: readCursor), store: store)
        let fixedNow = t3
        let service = RemoteThreadSnapshotService(threadStore: store, now: { fixedNow })

        let snapshot = service.snapshot(pendingThreadIds: ["pending"])

        XCTAssertEqual(snapshot.thread(id: "pending")?.displayState, .pending)
        XCTAssertEqual(store.get("pending")?.updatedAt, t2)
    }

    func testSnapshotEncodingStaysContentLight() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ThreadStore(rootDirectory: root)
        let privateThread = thread(
            id: "secret",
            title: "Visible title",
            workingDir: "/Users/mike/private/repo",
            projectLabel: "Secret project label",
            projectId: "project_1",
            localRootPathSnapshot: "/Users/mike/private/repo-old",
            defaultWorkerId: "secret_default_worker",
            turns: [
                turn("u1", kind: .userMessage, author: .user, createdAt: t0,
                     text: "private prompt with production token"),
                turn("w1", status: .running, createdAt: t1, workerId: "public_worker",
                     text: "visible worker body", reasoningText: "private reasoning trace")
            ],
            readCursor: ThreadReadCursor(lastReadTurnId: "u1", lastReadTurnCreatedAt: t0, readAt: t0)
        )
        try save(privateThread, store: store)
        let fixedNow = t3
        let service = RemoteThreadSnapshotService(threadStore: store, now: { fixedNow })

        let json = String(decoding: try CoreJSON.encode(service.snapshot()), as: UTF8.self)

        XCTAssertFalse(json.contains("private prompt with production token"))
        XCTAssertFalse(json.contains("visible worker body"))
        XCTAssertFalse(json.contains("private reasoning trace"))
        XCTAssertFalse(json.contains("/Users/mike/private/repo"))
        XCTAssertFalse(json.contains("Secret project label"))
        XCTAssertFalse(json.contains("secret_default_worker"))
        XCTAssertTrue(json.contains("Visible title"))
        XCTAssertTrue(json.contains("project_1"))
    }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-thread-snapshot-service-\(UUID().uuidString)", isDirectory: true)
    }

    private func save(_ thread: WorkThread, store: ThreadStore) throws {
        try store.saveForImport(thread)
    }

    private func thread(
        id: String,
        title: String = "Thread",
        status: ThreadStatus = .active,
        updatedAt: Date? = nil,
        workingDir: String? = nil,
        projectLabel: String? = nil,
        projectId: String? = nil,
        localRootPathSnapshot: String? = nil,
        defaultWorkerId: String? = nil,
        turns: [ThreadTurn] = [],
        readCursor: ThreadReadCursor? = .empty(at: Date(timeIntervalSince1970: 1_000))
    ) -> WorkThread {
        WorkThread(
            id: id,
            title: title,
            status: status,
            createdAt: t0,
            updatedAt: updatedAt ?? t2,
            workingDir: workingDir,
            projectLabel: projectLabel,
            projectId: projectId,
            localRootPathSnapshot: localRootPathSnapshot,
            defaultWorkerId: defaultWorkerId,
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
        workerId: String? = nil,
        text: String? = nil,
        reasoningText: String? = nil
    ) -> ThreadTurn {
        ThreadTurn(
            id: id,
            threadId: "thread_1",
            kind: kind,
            status: status,
            createdAt: createdAt ?? t1,
            completedAt: status.isTerminal ? (createdAt ?? t1) : nil,
            author: author,
            text: text ?? (author == .worker ? "reply" : "message"),
            workerId: workerId,
            reasoningText: reasoningText
        )
    }
}
