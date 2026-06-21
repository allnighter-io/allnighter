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

    func testSameMacSnapshotStaysScopedByAccount() async throws {
        let relay = MockRemoteMacRelay()
        let first = snapshotEnvelope(runId: "run_acct_1")
        let second = snapshotEnvelope(runId: "run_acct_2")

        try await relay.publishSnapshot(accountId: "acct_1", macAgentId: "mac_1", snapshot: first)
        try await relay.publishSnapshot(accountId: "acct_2", macAgentId: "mac_1", snapshot: second)

        let firstFetched = try await relay.snapshot(accountId: "acct_1", macAgentId: "mac_1", since: nil)
        let secondFetched = try await relay.snapshot(accountId: "acct_2", macAgentId: "mac_1", since: nil)

        XCTAssertEqual(firstFetched, first)
        XCTAssertEqual(secondFetched, second)
    }

    private func snapshotEnvelope(runId: String = "run_1") -> SnapshotEnvelope {
        SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: runId,
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
