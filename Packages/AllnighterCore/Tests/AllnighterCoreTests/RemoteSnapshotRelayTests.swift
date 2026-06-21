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

    func testThreadSnapshotIsScopedByAccountAndMac() async throws {
        let relay = MockRemoteMacRelay()
        let snapshot = threadSnapshotEnvelope(threadId: "thread_1")

        try await relay.publishThreadSnapshot(accountId: "acct_1", macAgentId: "mac_1", snapshot: snapshot)

        let fetched = try await relay.threadSnapshot(accountId: "acct_1", macAgentId: "mac_1")
        let wrongAccount = try await relay.threadSnapshot(accountId: "acct_2", macAgentId: "mac_1")
        let wrongMac = try await relay.threadSnapshot(accountId: "acct_1", macAgentId: "mac_2")

        XCTAssertEqual(fetched, snapshot)
        XCTAssertNil(wrongAccount)
        XCTAssertNil(wrongMac)
    }

    func testSealedThreadDetailIsScopedByAccountMacThreadAndDevice() async throws {
        let relay = MockRemoteMacRelay()
        let blob = sealedThreadDetail(deviceId: "device_1")

        try await relay.publishThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_1",
            sealedDetail: blob
        )

        let fetched = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_1"
        )
        let wrongDevice = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_2"
        )
        let wrongThread = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_2",
            deviceId: "device_1"
        )
        let wrongAccount = try await relay.sealedThreadDetail(
            accountId: "acct_2",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_1"
        )

        XCTAssertEqual(fetched, blob)
        XCTAssertNil(wrongDevice)
        XCTAssertNil(wrongThread)
        XCTAssertNil(wrongAccount)
    }

    func testPublishingThreadDetailRejectsWrongDeviceAndContentType() async throws {
        let relay = MockRemoteMacRelay()

        do {
            try await relay.publishThreadDetail(
                accountId: "acct_1",
                macAgentId: "mac_1",
                threadId: "thread_1",
                deviceId: "device_1",
                sealedDetail: sealedThreadDetail(deviceId: "device_2")
            )
            XCTFail("wrong-device sealed detail should be rejected")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(error, .threadDetailDeviceMismatch(
                threadId: "thread_1",
                expectedDeviceId: "device_1",
                actualSealedForKeyId: "device_2"
            ))
        }

        do {
            try await relay.publishThreadDetail(
                accountId: "acct_1",
                macAgentId: "mac_1",
                threadId: "thread_1",
                deviceId: "device_1",
                sealedDetail: SealedBlob(
                    ciphertext: Data("ciphertext".utf8),
                    encapsulatedKey: Data("encapsulated".utf8),
                    sealedForKeyId: "device_1",
                    contentType: "application/octet-stream"
                )
            )
            XCTFail("wrong-content-type sealed detail should be rejected")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(error, .threadDetailContentTypeMismatch(
                threadId: "thread_1",
                expectedContentType: RemoteThreadDetail.sealedContentType,
                actualContentType: "application/octet-stream"
            ))
        }
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

    private func threadSnapshotEnvelope(threadId: String) -> RemoteThreadSnapshotEnvelope {
        RemoteThreadSnapshotEnvelope(
            threads: [
                RemoteThreadSummary(
                    id: threadId,
                    title: "Thread",
                    status: .active,
                    projectId: nil,
                    createdAt: now.addingTimeInterval(-60),
                    updatedAt: now,
                    pinnedAt: nil,
                    displayState: .replied,
                    readState: RemoteThreadReadState(
                        readCursor: nil,
                        hasUnread: true,
                        unreadNeedsAttention: true,
                        firstUnreadTurnId: "turn_1",
                        latestUnreadTurnId: "turn_1"
                    ),
                    turnCount: 1,
                    latestTurn: nil
                ),
            ],
            serverTime: now
        )
    }

    private func sealedThreadDetail(deviceId: String) -> SealedBlob {
        SealedBlob(
            ciphertext: Data("thread-detail-ciphertext".utf8),
            encapsulatedKey: Data("thread-detail-encapsulated".utf8),
            sealedForKeyId: deviceId,
            contentType: RemoteThreadDetail.sealedContentType
        )
    }
}
