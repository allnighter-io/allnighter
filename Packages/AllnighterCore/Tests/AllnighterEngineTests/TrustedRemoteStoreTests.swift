import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class TrustedRemoteStoreTests: XCTestCase {
    private var root: URL!
    private var store: TrustedRemoteStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trusted-remote-\(UUID().uuidString)", isDirectory: true)
        store = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUpsertPendingPersistsAcrossStoreInstances() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let request = pairRequest(deviceId: "device_1", now: now)
        try store.upsertPending(request)

        let reopened = TrustedRemoteStore(fileURL: store.fileURL)
        let registry = reopened.load()
        XCTAssertEqual(registry.pendingRequests, [request])
        XCTAssertTrue(registry.trustedDevices.isEmpty)
    }

    func testApprovePinsDeviceKeysAndMarksRequestApproved() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let request = pairRequest(deviceId: "device_1", now: now)
        try store.upsertPending(request)

        let device = try store.approve(deviceId: "device_1", now: now, validFor: 60)

        XCTAssertEqual(device.deviceId, request.deviceId)
        XCTAssertEqual(device.deviceSigningPubkey, request.deviceSigningPubkey)
        XCTAssertEqual(device.deviceSealingPubkey, request.deviceSealingPubkey)
        XCTAssertEqual(device.pairedAt, now)
        XCTAssertEqual(device.validUntil, now.addingTimeInterval(60))
        XCTAssertFalse(device.revoked)
        XCTAssertEqual(device.capabilities, Set(RemoteCapability.allCases))

        let registry = store.load()
        XCTAssertEqual(registry.pendingRequests.first?.status, .approved)
        XCTAssertEqual(registry.pendingRequests.first?.approvedAt, now)
        XCTAssertEqual(registry.trustedDevices.map(\.deviceId), ["device_1"])
    }

    func testExpiredPendingRequestCannotBeApproved() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var request = pairRequest(deviceId: "device_1", now: now)
        request.expiresAt = now.addingTimeInterval(-1)
        try store.upsertPending(request)

        XCTAssertThrowsError(try store.approve(deviceId: "device_1", now: now)) { error in
            XCTAssertEqual(error as? TrustedRemoteStoreError, .pairRequestExpired("device_1"))
        }
        XCTAssertEqual(store.load().pendingRequests.first?.status, .expired)
    }

    func testRevokeIsForwardOnly() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try store.upsertPending(pairRequest(deviceId: "device_1", now: now))
        _ = try store.approve(deviceId: "device_1", now: now)

        let revoked = try store.revoke(deviceId: "device_1", now: now.addingTimeInterval(10))

        XCTAssertTrue(revoked.revoked)
        XCTAssertEqual(revoked.revokedAt, now.addingTimeInterval(10))
        XCTAssertEqual(store.load().trustedDevices.count, 1)
        XCTAssertEqual(store.load().trustedDevices.first?.deviceSigningPubkey, "sign_device_1")
    }

    func testListExpiresStalePendingRequests() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var request = pairRequest(deviceId: "device_1", now: now)
        request.expiresAt = now.addingTimeInterval(-1)
        try store.upsertPending(request)

        let registry = store.list(now: now)

        XCTAssertEqual(registry.pendingRequests.first?.status, .expired)
    }

    private func pairRequest(deviceId: String, now: Date) -> RemotePairRequest {
        RemotePairRequest(
            id: "pair_\(deviceId)",
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: deviceId,
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "sign_\(deviceId)",
            deviceSealingPubkey: "seal_\(deviceId)",
            requestedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
    }
}
