import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteSnapshotServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_100_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-snapshot-service-\(UUID().uuidString)", isDirectory: true)
    }

    func testSnapshotIncludesRecentCompletedRunsAndJournalSeq() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runStore = RunStore(rootDirectory: root)
        let journal = RemoteRunEventJournal(rootDirectory: root)

        _ = try runStore.save(Self.run(
            id: "older_done",
            prompt: "Older result",
            status: .complete,
            origin: .gui,
            createdAt: now.addingTimeInterval(-200),
            teamDisplayName: "Older Team"
        ), models: [])
        _ = try runStore.save(Self.run(
            id: "recent_done",
            prompt: String(repeating: "r", count: 40),
            status: .complete,
            origin: .ios,
            createdAt: now.addingTimeInterval(-100),
            teamDisplayName: "Night Team"
        ), models: [])
        _ = try runStore.save(Self.run(
            id: "running",
            prompt: "Still running",
            status: .fanningOut,
            origin: .ios,
            createdAt: now
        ), models: [])
        _ = try journal.append(Self.event(id: "evt_1", runId: "running", now: now))
        let fixedNow = now

        let service = RemoteSnapshotService(
            runStore: runStore,
            journal: journal,
            policy: RemoteSnapshotPolicy(maxRuns: 2, promptExcerptLimit: 12),
            now: { fixedNow }
        )
        let snapshot = try service.snapshot()

        XCTAssertEqual(snapshot.lastSeq, 1)
        XCTAssertEqual(snapshot.serverTime, now)
        XCTAssertEqual(snapshot.runs.map(\.id), ["running", "recent_done"])
        XCTAssertEqual(snapshot.runs[0].status, .running)
        XCTAssertEqual(snapshot.runs[1].status, .done)
        XCTAssertEqual(snapshot.runs[1].origin, .ios)
        XCTAssertEqual(snapshot.runs[1].teamDisplayName, "Night Team")
        XCTAssertEqual(snapshot.runs[1].completedAt, now.addingTimeInterval(-100))
        XCTAssertEqual(snapshot.runs.map(\.promptExcerpt), ["", ""])
        XCTAssertFalse(String(decoding: try CoreJSON.encode(snapshot), as: UTF8.self).contains(String(repeating: "r", count: 40)))
    }

    func testResumeAtZeroReturnsSnapshot() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runStore = RunStore(rootDirectory: root)
        let journal = RemoteRunEventJournal(rootDirectory: root)
        _ = try runStore.save(Self.run(id: "run_1", prompt: "Prompt", createdAt: now), models: [])
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        let fixedNow = now

        let service = RemoteSnapshotService(runStore: runStore, journal: journal, now: { fixedNow })
        guard case let .snapshot(snapshot) = try service.resume(since: 0) else {
            return XCTFail("Expected seq=0 resume to return a snapshot")
        }

        XCTAssertEqual(snapshot.runs.map(\.id), ["run_1"])
        XCTAssertEqual(snapshot.lastSeq, 1)
    }

    func testResumeReturnsEventsWithinBoundedWindow() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_2", runId: "run_1", now: now))
        let fixedNow = now

        let service = RemoteSnapshotService(
            runStore: RunStore(rootDirectory: root),
            journal: journal,
            policy: RemoteSnapshotPolicy(replayEventLimit: 2),
            now: { fixedNow }
        )
        guard case let .events(events, lastSeq) = try service.resume(since: 1) else {
            return XCTFail("Expected missed events inside the replay window")
        }

        XCTAssertEqual(events.map(\.id), ["evt_2"])
        XCTAssertEqual(lastSeq, 2)
    }

    func testResumeEventsAreContentLight() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(RunEvent(
            id: "evt_secret",
            seq: 0,
            ts: now,
            kind: RunEventKind.workerAnswerDelta,
            payload: [
                "runId": .string("run_1"),
                "workerId": .string("worker_1"),
                "text": .string("secret replay text"),
                "truncated": .bool(false),
            ]
        ))
        let fixedNow = now

        let service = RemoteSnapshotService(
            runStore: RunStore(rootDirectory: root),
            journal: journal,
            policy: RemoteSnapshotPolicy(replayEventLimit: 10),
            now: { fixedNow }
        )
        guard case let .events(events, _) = try service.resume(since: 1) else {
            return XCTFail("Expected missed events inside the replay window")
        }

        XCTAssertEqual(events.map(\.id), ["evt_secret"])
        XCTAssertEqual(events.first?.payload["runId"], .string("run_1"))
        XCTAssertEqual(events.first?.payload["workerId"], .string("worker_1"))
        XCTAssertEqual(events.first?.payload["truncated"], .bool(false))
        XCTAssertNil(events.first?.payload["text"])
        XCTAssertFalse(String(decoding: try CoreJSON.encode(events), as: UTF8.self).contains("secret replay text"))
    }

    func testResumeRequiresResyncWhenEventWindowIsExceeded() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_2", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_3", runId: "run_1", now: now))
        let fixedNow = now

        let service = RemoteSnapshotService(
            runStore: RunStore(rootDirectory: root),
            journal: journal,
            policy: RemoteSnapshotPolicy(replayEventLimit: 1),
            now: { fixedNow }
        )
        guard case let .resyncRequired(resync) = try service.resume(since: 1) else {
            return XCTFail("Expected replay overflow to require a snapshot resync")
        }

        XCTAssertEqual(resync.reason, "eventWindowExceeded")
        XCTAssertEqual(resync.snapshotHint, "Fetch a snapshot, then resume from its lastSeq.")
    }

    private static func run(
        id: String,
        prompt: String,
        status: RunStatus = .complete,
        origin: RunOrigin = .gui,
        createdAt: Date,
        teamDisplayName: String? = nil
    ) -> TeamRun {
        TeamRun(
            id: id,
            prompt: prompt,
            status: status,
            origin: origin,
            createdAt: createdAt,
            teamDisplayName: teamDisplayName
        )
    }

    private static func event(id: String, runId: String, now: Date) -> RunEvent {
        RunEvent(
            id: id,
            seq: 0,
            ts: now,
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(runId),
                "to": .string(RunStatus.fanningOut.rawValue)
            ]
        )
    }
}
