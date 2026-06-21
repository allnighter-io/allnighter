import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteDeviceRevocationCoordinatorTests: XCTestCase {
    private var root: URL!
    private var store: TrustedRemoteStore!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-revocation-\(UUID().uuidString)", isDirectory: true)
        store = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRevokeTearsDownOnlyTheTargetDeviceScope() async throws {
        let target = trustedDevice(deviceId: "device_1", macAgentId: "mac_1")
        let sameMacOtherDevice = trustedDevice(deviceId: "device_2", macAgentId: "mac_1")
        let otherMacSameDeviceId = trustedDevice(deviceId: "device_1", macAgentId: "mac_2")
        try store.save(TrustedRemoteRegistry(trustedDevices: [
            target,
            sameMacOtherDevice,
            otherMacSameDeviceId,
        ]))
        let teardown = CapturingRevocationTeardown()
        let fixedNow = now
        let coordinator = RemoteDeviceRevocationCoordinator(
            store: store,
            teardown: teardown,
            now: { fixedNow }
        )

        let result = try await coordinator.revoke(deviceId: "device_1", macAgentId: "mac_1")

        XCTAssertEqual(result.revokedDevice.deviceId, "device_1")
        XCTAssertEqual(result.revokedDevice.macAgentId, "mac_1")
        XCTAssertEqual(result.teardownScope, RemoteDeviceRevocationScope(
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: "device_1",
            revokedAt: now
        ))
        let scopes = await teardown.scopes()
        XCTAssertEqual(scopes, [result.teardownScope])

        let devices = try store.load().trustedDevices
        XCTAssertEqual(devices.first { $0.deviceId == "device_1" && $0.macAgentId == "mac_1" }?.revoked, true)
        XCTAssertEqual(devices.first { $0.deviceId == "device_2" && $0.macAgentId == "mac_1" }?.revoked, false)
        XCTAssertEqual(devices.first { $0.deviceId == "device_1" && $0.macAgentId == "mac_2" }?.revoked, false)
    }

    func testMissingScopedDeviceDoesNotRunTeardown() async throws {
        try store.save(TrustedRemoteRegistry(trustedDevices: [
            trustedDevice(deviceId: "device_1", macAgentId: "mac_1"),
        ]))
        let teardown = CapturingRevocationTeardown()
        let fixedNow = now
        let coordinator = RemoteDeviceRevocationCoordinator(
            store: store,
            teardown: teardown,
            now: { fixedNow }
        )

        do {
            _ = try await coordinator.revoke(deviceId: "device_1", macAgentId: "mac_2")
            XCTFail("missing scoped device should not revoke")
        } catch let error as TrustedRemoteStoreError {
            XCTAssertEqual(error, .trustedDeviceNotFound("device_1"))
        }

        let scopes = await teardown.scopes()
        XCTAssertEqual(scopes, [])
        XCTAssertEqual(try store.load().trustedDevices.first?.revoked, false)
    }

    func testRevokeCanTargetSpecificAccountScope() async throws {
        let target = trustedDevice(accountId: "acct_1", deviceId: "device_1", macAgentId: "mac_1")
        let otherAccount = trustedDevice(accountId: "acct_2", deviceId: "device_1", macAgentId: "mac_1")
        try store.save(TrustedRemoteRegistry(trustedDevices: [
            otherAccount,
            target,
        ]))
        let teardown = CapturingRevocationTeardown()
        let fixedNow = now
        let coordinator = RemoteDeviceRevocationCoordinator(
            store: store,
            teardown: teardown,
            now: { fixedNow }
        )

        let result = try await coordinator.revoke(
            deviceId: "device_1",
            accountId: "acct_1",
            macAgentId: "mac_1"
        )

        XCTAssertEqual(result.teardownScope.accountId, "acct_1")
        let devices = try store.load().trustedDevices
        XCTAssertEqual(devices.first { $0.accountId == "acct_1" }?.revoked, true)
        XCTAssertEqual(devices.first { $0.accountId == "acct_2" }?.revoked, false)
        let scopes = await teardown.scopes()
        XCTAssertEqual(scopes.map(\.accountId), ["acct_1"])
    }

    private func trustedDevice(
        accountId: String = "acct_1",
        deviceId: String,
        macAgentId: String
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: deviceId,
            deviceSigningPubkey: "sign_\(deviceId)_\(macAgentId)",
            deviceSealingPubkey: "seal_\(deviceId)_\(macAgentId)",
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(300),
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}

private actor CapturingRevocationTeardown: RemoteDeviceRevocationTearingDown {
    private var capturedScopes: [RemoteDeviceRevocationScope] = []

    func tearDown(_ scope: RemoteDeviceRevocationScope) async throws {
        capturedScopes.append(scope)
    }

    func scopes() -> [RemoteDeviceRevocationScope] {
        capturedScopes
    }
}
