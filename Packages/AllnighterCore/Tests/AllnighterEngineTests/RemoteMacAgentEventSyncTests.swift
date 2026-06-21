import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteMacAgentEventSyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_300_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-mac-agent-event-sync-\(UUID().uuidString)", isDirectory: true)
    }

    func testPublishesBatchedEventsWithoutAdvancingPastUnpublishedSeq() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let relay = MockRemoteMacRelay()
        let cursorStore = RemoteMacAgentEventCursorStore(
            fileURL: root.appendingPathComponent("cursor.json")
        )
        let signingKey = Curve25519.Signing.PrivateKey()

        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_2", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_3", runId: "run_1", now: now))

        let firstSync = RemoteMacAgentEventSync(
            publisher: RemoteRunEventPublisher(
                accountId: "acct_1",
                macAgentId: "mac_1",
                journal: journal,
                relay: relay,
                signingKey: signingKey,
                batchLimit: 1
            ),
            cursorStore: cursorStore
        )
        let first = try await firstSync.publishNewEvents()

        XCTAssertEqual(first.publishedEventCount, 1)
        XCTAssertEqual(first.lastPublishedSeq, 1)
        XCTAssertEqual(first.journalLastSeq, 3)
        XCTAssertEqual(try cursorStore.load(), 1)

        let resumedSync = RemoteMacAgentEventSync(
            publisher: RemoteRunEventPublisher(
                accountId: "acct_1",
                macAgentId: "mac_1",
                journal: journal,
                relay: relay,
                signingKey: signingKey,
                batchLimit: 1
            ),
            cursorStore: RemoteMacAgentEventCursorStore(fileURL: root.appendingPathComponent("cursor.json"))
        )
        let second = try await resumedSync.publishNewEvents()

        XCTAssertEqual(second.publishedEventCount, 1)
        XCTAssertEqual(second.lastPublishedSeq, 2)
        XCTAssertEqual(try cursorStore.load(), 2)
        let published = await relay.publishedEvents
        XCTAssertEqual(published.map(\.event.id), ["evt_1", "evt_2"])
    }

    func testNoopsWithoutMovingCursorWhenThereAreNoNewEvents() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let relay = MockRemoteMacRelay()
        let cursorStore = RemoteMacAgentEventCursorStore(
            fileURL: root.appendingPathComponent("cursor.json")
        )

        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        let sync = RemoteMacAgentEventSync(
            publisher: RemoteRunEventPublisher(
                accountId: "acct_1",
                macAgentId: "mac_1",
                journal: journal,
                relay: relay,
                signingKey: Curve25519.Signing.PrivateKey()
            ),
            cursorStore: cursorStore
        )

        _ = try await sync.publishNewEvents()
        let second = try await sync.publishNewEvents()

        XCTAssertEqual(second.publishedEventCount, 0)
        XCTAssertEqual(second.lastPublishedSeq, 1)
        XCTAssertEqual(second.journalLastSeq, 1)
        XCTAssertEqual(try cursorStore.load(), 1)
        let published = await relay.publishedEvents
        XCTAssertEqual(published.map(\.event.id), ["evt_1"])
    }

    func testCursorStoreRejectsNegativeSeq() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cursorStore = RemoteMacAgentEventCursorStore(
            fileURL: root.appendingPathComponent("cursor.json")
        )

        XCTAssertThrowsError(try cursorStore.save(-1)) { error in
            XCTAssertEqual(error as? RemoteMacAgentEventCursorStoreError, .corruptCursor("-1"))
        }
    }

    private static func event(id: String, runId: String, now: Date) -> RunEvent {
        RunEvent(
            id: id,
            seq: 0,
            ts: now,
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(runId),
                "to": .string(RunStatus.fanningOut.rawValue),
            ]
        )
    }
}
