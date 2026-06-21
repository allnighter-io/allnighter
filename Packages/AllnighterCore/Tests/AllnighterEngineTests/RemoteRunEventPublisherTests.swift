import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteRunEventPublisherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_200_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-run-event-publisher-\(UUID().uuidString)", isDirectory: true)
    }

    func testPublishSignsJournalEventsAndNormalizesRemoteKinds() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let signingKey = Curve25519.Signing.PrivateKey()
        let relay = MockRemoteMacRelay()

        _ = try journal.append(Self.event(id: "evt_1", kind: RunEventKind.runStatusChanged, runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_2", kind: RunEventKind.synthesisCompleted, runId: "run_1", now: now))

        let publisher = RemoteRunEventPublisher(
            accountId: "acct_1",
            macAgentId: "mac_1",
            journal: journal,
            relay: relay,
            signingKey: signingKey
        )
        let result = try await publisher.publish(after: 0)

        XCTAssertEqual(result.publishedEventCount, 2)
        XCTAssertEqual(result.lastSeq, 2)
        let published = await relay.publishedEvents
        XCTAssertEqual(published.map(\.event.id), ["evt_1", "evt_2"])
        XCTAssertEqual(published.map(\.event.kind), [RunEventKind.runStatusChanged, RunEventKind.stageCompleted])
        for envelope in published {
            XCTAssertEqual(envelope.macAgentId, "mac_1")
            XCTAssertTrue(try RemoteCrypto.verifyRemoteRunEventEnvelope(
                envelope,
                signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
            ))
        }
    }

    func testPublishOnlyReplaysEventsAfterSeqWithinBatchLimit() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let relay = MockRemoteMacRelay()

        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_2", runId: "run_1", now: now))
        _ = try journal.append(Self.event(id: "evt_3", runId: "run_1", now: now))

        let publisher = RemoteRunEventPublisher(
            accountId: "acct_1",
            macAgentId: "mac_1",
            journal: journal,
            relay: relay,
            signingKey: Curve25519.Signing.PrivateKey(),
            batchLimit: 1
        )
        let result = try await publisher.publish(after: 1)

        XCTAssertEqual(result.publishedEventCount, 1)
        XCTAssertEqual(result.lastSeq, 3)
        let published = await relay.publishedEvents
        XCTAssertEqual(published.map(\.event.id), ["evt_2"])
    }

    func testPublishNoopsWhenThereAreNoMissedEvents() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = RemoteRunEventJournal(rootDirectory: root)
        let relay = MockRemoteMacRelay()

        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        let publisher = RemoteRunEventPublisher(
            accountId: "acct_1",
            macAgentId: "mac_1",
            journal: journal,
            relay: relay,
            signingKey: Curve25519.Signing.PrivateKey()
        )

        let result = try await publisher.publish(after: 1)

        XCTAssertEqual(result.publishedEventCount, 0)
        XCTAssertEqual(result.lastSeq, 1)
        let eventLog = await relay.eventLog
        XCTAssertFalse(eventLog.contains("publishEvents"))
    }

    private static func event(
        id: String,
        kind: String = RunEventKind.runStatusChanged,
        runId: String,
        now: Date
    ) -> RunEvent {
        RunEvent(
            id: id,
            seq: 0,
            ts: now,
            kind: kind,
            payload: [
                "runId": .string(runId),
                "to": .string(RunStatus.fanningOut.rawValue)
            ]
        )
    }
}
