import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteSnapshotPublisherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_700_000)

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-snapshot-publisher-\(UUID().uuidString)", isDirectory: true)
    }

    func testPublisherPublishesMacSnapshotToRelay() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runStore = RunStore(rootDirectory: root)
        let journal = RemoteRunEventJournal(rootDirectory: root)
        _ = try runStore.save(Self.run(id: "run_1", createdAt: now), models: [])
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        let fixedNow = now
        let service = RemoteSnapshotService(
            runStore: runStore,
            journal: journal,
            now: { fixedNow }
        )
        let relay = MockRemoteMacRelay()
        let publisher = RemoteSnapshotPublisher(
            accountId: "acct_1",
            macAgentId: "mac_1",
            service: service,
            relay: relay
        )

        let result = try await publisher.publish()

        XCTAssertEqual(result.runCount, 1)
        XCTAssertEqual(result.lastSeq, 1)
        let snapshot = try await relay.snapshot(accountId: "acct_1", macAgentId: "mac_1", since: nil)
        XCTAssertEqual(snapshot?.runs.map(\.id), ["run_1"])
        XCTAssertEqual(snapshot?.lastSeq, 1)
        XCTAssertEqual(snapshot?.serverTime, now)
    }

    private static func run(id: String, createdAt: Date) -> TeamRun {
        TeamRun(
            id: id,
            prompt: "Sensitive prompt stays local",
            status: .fanningOut,
            origin: .ios,
            createdAt: createdAt,
            teamDisplayName: "Remote Team"
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
