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

    func testUpsertPendingPreservesSameDeviceOnOtherAccount() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let first = pairRequest(accountId: "acct_1", deviceId: "device_1", now: now)
        let second = pairRequest(accountId: "acct_2", deviceId: "device_1", now: now.addingTimeInterval(1))

        try store.upsertPending(first)
        try store.upsertPending(second)

        let requests = store.load().pendingRequests
        XCTAssertEqual(requests.map(\.accountId), ["acct_1", "acct_2"])
        XCTAssertEqual(Set(requests.map(\.deviceId)), ["device_1"])
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

    func testApprovePreservesSameDeviceOnOtherMac() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let existing = trustedDevice(deviceId: "device_1", macAgentId: "mac_1", now: now)
        let request = pairRequest(deviceId: "device_1", macAgentId: "mac_2", now: now)
        try store.save(TrustedRemoteRegistry(
            pendingRequests: [request],
            trustedDevices: [existing]
        ))

        let approved = try store.approve(deviceId: "device_1", now: now, validFor: 60)

        XCTAssertEqual(approved.macAgentId, "mac_2")
        let devices = store.load().trustedDevices
        XCTAssertEqual(devices.first { $0.macAgentId == "mac_1" }?.deviceSigningPubkey, "sign_device_1")
        XCTAssertEqual(devices.first { $0.macAgentId == "mac_2" }?.deviceSigningPubkey, "sign_device_1")
        XCTAssertEqual(Set(devices.map(\.macAgentId)), ["mac_1", "mac_2"])
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

    func testScopedRevokeTargetsOnlyMatchingMac() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let firstMac = trustedDevice(deviceId: "device_1", macAgentId: "mac_1", now: now)
        let secondMac = trustedDevice(deviceId: "device_1", macAgentId: "mac_2", now: now)
        try store.save(TrustedRemoteRegistry(trustedDevices: [firstMac, secondMac]))

        let revoked = try store.revoke(deviceId: "device_1", macAgentId: "mac_2", now: now.addingTimeInterval(10))

        XCTAssertEqual(revoked.macAgentId, "mac_2")
        let devices = store.load().trustedDevices
        XCTAssertEqual(devices.first { $0.macAgentId == "mac_1" }?.revoked, false)
        XCTAssertEqual(devices.first { $0.macAgentId == "mac_2" }?.revoked, true)
        XCTAssertEqual(devices.first { $0.macAgentId == "mac_2" }?.revokedAt, now.addingTimeInterval(10))
    }

    func testListExpiresStalePendingRequests() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var request = pairRequest(deviceId: "device_1", now: now)
        request.expiresAt = now.addingTimeInterval(-1)
        try store.upsertPending(request)

        let registry = store.list(now: now)

        XCTAssertEqual(registry.pendingRequests.first?.status, .expired)
    }

    func testSyncTrustedDevicesReplacesTargetMacOnlyAndPreservesPendingRequests() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let request = pairRequest(deviceId: "device_pending", now: now)
        let stale = trustedDevice(deviceId: "device_stale", macAgentId: "mac_1", now: now)
        let otherMac = trustedDevice(deviceId: "device_other", macAgentId: "mac_2", now: now)
        try store.save(TrustedRemoteRegistry(
            pendingRequests: [request],
            trustedDevices: [stale, otherMac]
        ))

        let fresh = trustedDevice(deviceId: "device_fresh", macAgentId: "mac_1", now: now)
        try store.syncTrustedDevices([fresh], accountId: "acct_1", macAgentId: "mac_1", now: now)

        let registry = store.load()
        XCTAssertEqual(registry.pendingRequests, [request])
        XCTAssertEqual(registry.trustedDevices.map(\.deviceId), ["device_fresh", "device_other"])
    }

    func testSyncTrustedDevicesPreservesSameMacForOtherAccount() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let stale = trustedDevice(accountId: "acct_1", deviceId: "device_stale", macAgentId: "mac_1", now: now)
        let otherAccount = trustedDevice(accountId: "acct_2", deviceId: "device_other", macAgentId: "mac_1", now: now)
        let fresh = trustedDevice(accountId: "acct_1", deviceId: "device_fresh", macAgentId: "mac_1", now: now)
        try store.save(TrustedRemoteRegistry(trustedDevices: [stale, otherAccount]))

        try store.syncTrustedDevices([fresh], accountId: "acct_1", macAgentId: "mac_1", now: now)

        let registry = store.load()
        XCTAssertNil(registry.trustedDevices.first { $0.deviceId == "device_stale" })
        XCTAssertEqual(registry.trustedDevices.first { $0.accountId == "acct_1" }?.deviceId, "device_fresh")
        XCTAssertEqual(registry.trustedDevices.first { $0.accountId == "acct_2" }?.deviceId, "device_other")
    }

    private func pairRequest(
        accountId: String = "acct_1",
        deviceId: String,
        macAgentId: String = "mac_1",
        now: Date
    ) -> RemotePairRequest {
        RemotePairRequest(
            id: "pair_\(deviceId)",
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: deviceId,
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "sign_\(deviceId)",
            deviceSealingPubkey: "seal_\(deviceId)",
            requestedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
    }

    private func trustedDevice(
        accountId: String = "acct_1",
        deviceId: String,
        macAgentId: String,
        now: Date
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: deviceId,
            deviceSigningPubkey: "sign_\(deviceId)",
            deviceSealingPubkey: "seal_\(deviceId)",
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now,
            validUntil: now.addingTimeInterval(300),
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}
