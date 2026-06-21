import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteRunEventJournalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-run-event-journal-\(UUID().uuidString)", isDirectory: true)
    }

    func testAppendAssignsMonotonicSeqAcrossInstancesAndMirrorsPerRun() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let journal = RemoteRunEventJournal(rootDirectory: root)
        let first = try journal.append(Self.event(id: "evt_1", seq: 99, runId: "run_1", now: now))
        let second = try RemoteRunEventJournal(rootDirectory: root)
            .append(Self.event(id: "evt_2", seq: 1, runId: "run_2", now: now))

        XCTAssertEqual(first.seq, 1)
        XCTAssertEqual(second.seq, 2)
        XCTAssertEqual(try journal.lastSeq(), 2)
        XCTAssertEqual(try journal.events(after: 0).map(\.id), ["evt_1", "evt_2"])
        XCTAssertEqual(try journal.events(forRunId: "run_1").map(\.id), ["evt_1"])
        XCTAssertEqual(try journal.events(forRunId: "run_2").map(\.id), ["evt_2"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.globalIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.eventsURL(forRunId: "run_1").path))
    }

    func testReplayAfterSeqIsBoundedAndOrdered() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)

        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_2", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_3", runId: "run_1", now: now))

        XCTAssertEqual(try journal.events(after: 1).map(\.id), ["evt_2", "evt_3"])
        XCTAssertEqual(try journal.events(after: 1, limit: 1).map(\.id), ["evt_2"])
        XCTAssertEqual(try journal.events(after: 1, limit: 0), [])
        XCTAssertEqual(try journal.events(forRunId: "run_1", after: 2).map(\.id), ["evt_3"])
        XCTAssertEqual(try journal.events(forRunId: "run_1", after: 2, limit: 0), [])
    }

    func testAppendRequiresRunId() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)

        XCTAssertThrowsError(try journal.append(RunEvent(
            id: "evt_missing",
            seq: 0,
            ts: now,
            kind: RunEventKind.runStatusChanged,
            payload: [:]
        ))) { error in
            XCTAssertEqual(error as? RemoteRunEventJournalError, .missingRunId(eventId: "evt_missing"))
        }
        XCTAssertEqual(try journal.lastSeq(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.globalIndexURL.path))
    }

    func testConcurrentAppendsProduceUniqueMonotonicSeq() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let fixedNow = now

        let persisted = await withTaskGroup(of: RunEvent?.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try? journal.append(Self.event(id: "evt_\(index)", runId: "run_shared", now: fixedNow))
                }
            }

            var events: [RunEvent] = []
            for await event in group {
                if let event { events.append(event) }
            }
            return events
        }

        XCTAssertEqual(persisted.count, 20)
        XCTAssertEqual(Set(persisted.map(\.seq)).count, 20)
        XCTAssertEqual(try journal.events(after: 0).map(\.seq), Array(1...20).map(Int64.init))
        XCTAssertEqual(try journal.events(forRunId: "run_shared").count, 20)
        XCTAssertEqual(try journal.lastSeq(), 20)
    }

    private static func event(id: String, seq: Int64 = 0, runId: String, now: Date) -> RunEvent {
        RunEvent(
            id: id,
            seq: seq,
            ts: now,
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(runId),
                "to": .string(RunStatus.fanningOut.rawValue)
            ]
        )
    }
}
