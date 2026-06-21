import XCTest
@testable import AllnighterCore

final class RemoteSnapshotRelayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_600_000)

    func testSnapshotIsScopedByAccountAndMac() async throws {
        let relay = MockRemoteMacRelay()
        let snapshot = snapshotEnvelope()

        try await relay.publishSnapshot(accountId: "acct_1", macAgentId: "mac_1", snapshot: snapshot)

        let fetched = try await relay.snapshot(accountId: "acct_1", macAgentId: "mac_1", since: nil)
        let wrongAccount = try await relay.snapshot(accountId: "acct_2", macAgentId: "mac_1", since: nil)
        let wrongMac = try await relay.snapshot(accountId: "acct_1", macAgentId: "mac_2", since: nil)

        XCTAssertEqual(fetched, snapshot)
        XCTAssertNil(wrongAccount)
        XCTAssertNil(wrongMac)
    }

    private func snapshotEnvelope() -> SnapshotEnvelope {
        SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .running,
                    origin: .ios,
                    promptExcerpt: "",
                    teamDisplayName: "Remote Team",
                    createdAt: now
                )
            ],
            lastSeq: 12,
            serverTime: now
        )
    }
}
