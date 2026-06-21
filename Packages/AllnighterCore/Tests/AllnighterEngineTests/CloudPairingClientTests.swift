import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class CloudPairingClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_100_000)

    func testClientListsMacsAndSubmitsPairRequest() async throws {
        let relay = MockRemoteMacRelay(pairRequestIdFactory: { "pair_request_1" })
        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_1",
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: "mac_seal"
        ))
        _ = try await relay.registerMacAgent(RemoteMacAgentRegistration(
            accountId: "acct_other",
            macAgentId: "mac_other",
            displayName: "Other Mac",
            agentSigningPubkey: "other_sign",
            agentSealingPubkey: "other_seal"
        ))
        let fixedNow = now
        let client = CloudPairingClient(relay: relay, now: { fixedNow }, defaultTTL: 120)
        try await client.connect(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            mode: ConnectionMode.cloudRelay
        )

        let macs = try await client.macs()
        XCTAssertEqual(macs.map(\.macAgentId), ["mac_1"])
        let mac = try XCTUnwrap(macs.first)

        let request = try await client.requestPairing(
            mac: mac,
            device: RemotePairingDeviceIdentity(
                deviceId: " device_1 ",
                displayName: " Mike's iPhone ",
                deviceSigningPubkey: " device_sign ",
                deviceSealingPubkey: " device_seal "
            )
        )

        XCTAssertEqual(request.id, "pair_request_1")
        XCTAssertEqual(request.accountId, "acct_1")
        XCTAssertEqual(request.macAgentId, "mac_1")
        XCTAssertEqual(request.deviceId, "device_1")
        XCTAssertEqual(request.displayName, "Mike's iPhone")
        XCTAssertEqual(request.deviceSigningPubkey, "device_sign")
        XCTAssertEqual(request.deviceSealingPubkey, "device_seal")
        XCTAssertEqual(request.requestedAt, now)
        XCTAssertEqual(request.expiresAt, now.addingTimeInterval(120))

        let pending = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(pending, [request])

        let status = try await client.status(mac: mac, requestId: " pair_request_1 ", deviceId: " device_1 ")
        XCTAssertEqual(status.status, .pending)
        XCTAssertEqual(status.pairRequest, request)
        XCTAssertNil(status.trustedDevice)
        XCTAssertEqual(status.checkedAt, now)
    }

    func testClientReportsApprovedAndRevokedCloudStatus() async throws {
        let relay = MockRemoteMacRelay(pairRequestIdFactory: { "pair_request_1" })
        let fixedNow = now
        let client = CloudPairingClient(relay: relay, now: { fixedNow }, defaultTTL: 120)
        try await client.connect(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            mode: ConnectionMode.cloudRelay
        )
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: "mac_seal"
        )
        let request = try await client.requestPairing(
            mac: mac,
            device: RemotePairingDeviceIdentity(
                deviceId: "device_1",
                displayName: "Mike's iPhone",
                deviceSigningPubkey: "device_sign",
                deviceSealingPubkey: "device_seal"
            )
        )
        var approvedRequest = request
        approvedRequest.status = .approved
        approvedRequest.approvedAt = now
        _ = try await relay.updatePairRequest(approvedRequest)
        var device = trustedDevice()
        try await relay.upsertTrustedDevice(device)

        let approved = try await client.status(mac: mac, requestId: request.id, deviceId: "device_1")

        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(approved.pairRequest, approvedRequest)
        XCTAssertEqual(approved.trustedDevice, device)

        device.revoked = true
        device.revokedAt = now.addingTimeInterval(10)
        try await relay.upsertTrustedDevice(device)

        let revoked = try await client.status(mac: mac, requestId: request.id, deviceId: "device_1")

        XCTAssertEqual(revoked.status, .revoked)
        XCTAssertEqual(revoked.trustedDevice, device)
    }

    func testClientScopesStatusToSelectedMac() async throws {
        var otherMacRequest = RemotePairRequest(
            id: "pair_shared",
            accountId: "acct_1",
            macAgentId: "mac_2",
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            requestedAt: now,
            expiresAt: now.addingTimeInterval(120)
        )
        otherMacRequest.status = .approved
        otherMacRequest.approvedAt = now
        let relay = MockRemoteMacRelay(
            pairRequests: [otherMacRequest],
            trustedDevices: [trustedDevice(macAgentId: "mac_2")]
        )
        let fixedNow = now
        let client = CloudPairingClient(relay: relay, now: { fixedNow })
        try await client.connect(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            mode: ConnectionMode.cloudRelay
        )
        let selectedMac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: "mac_seal"
        )

        let status = try await client.status(
            mac: selectedMac,
            requestId: "pair_shared",
            deviceId: "device_1"
        )

        XCTAssertEqual(status.status, .notFound)
        XCTAssertNil(status.pairRequest)
        XCTAssertNil(status.trustedDevice)
    }

    func testClientRequiresConnectionAndCloudMode() async throws {
        let relay = MockRemoteMacRelay()
        let client = CloudPairingClient(relay: relay)

        do {
            _ = try await client.macs()
            XCTFail("mac discovery should require a connected account")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .notConnected)
        }

        do {
            try await client.connect(
                account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
                mode: ConnectionMode.tailscaleDirect
            )
            XCTFail("cloud pairing client should only connect in cloud relay mode")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .unsupportedMode(ConnectionMode.tailscaleDirect))
        }
    }

    func testClientValidatesPairingDraftFields() async throws {
        let relay = MockRemoteMacRelay()
        let fixedNow = now
        let client = CloudPairingClient(relay: relay, now: { fixedNow })
        try await client.connect(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            mode: ConnectionMode.cloudRelay
        )
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: "mac_seal"
        )

        do {
            _ = try await client.requestPairing(
                mac: mac,
                device: RemotePairingDeviceIdentity(
                    deviceId: "",
                    displayName: "Mike's iPhone",
                    deviceSigningPubkey: "device_sign",
                    deviceSealingPubkey: "device_seal"
                )
            )
            XCTFail("empty device id should be rejected")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .emptyDeviceId)
        }

        do {
            _ = try await client.requestPairing(
                mac: mac,
                device: RemotePairingDeviceIdentity(
                    deviceId: "device_1",
                    displayName: "Mike's iPhone",
                    deviceSigningPubkey: "device_sign",
                    deviceSealingPubkey: "device_seal"
                ),
                ttl: 0
            )
            XCTFail("non-positive ttl should be rejected")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .invalidTTL(0))
        }
    }

    func testClientValidatesStatusFields() async throws {
        let relay = MockRemoteMacRelay()
        let fixedNow = now
        let client = CloudPairingClient(relay: relay, now: { fixedNow })
        try await client.connect(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            mode: ConnectionMode.cloudRelay
        )
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "mac_sign",
            agentSealingPubkey: "mac_seal"
        )

        do {
            _ = try await client.status(mac: mac, requestId: " ", deviceId: "device_1")
            XCTFail("empty request id should be rejected")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .emptyRequestId)
        }

        do {
            _ = try await client.status(mac: mac, requestId: "pair_request_1", deviceId: " ")
            XCTFail("empty device id should be rejected")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .emptyDeviceId)
        }

        do {
            _ = try await client.status(
                mac: MacAgentRef(
                    macAgentId: " ",
                    displayName: "Studio Mac",
                    agentSigningPubkey: "mac_sign",
                    agentSealingPubkey: "mac_seal"
                ),
                requestId: "pair_request_1",
                deviceId: "device_1"
            )
            XCTFail("empty mac id should be rejected")
        } catch let error as CloudPairingClientError {
            XCTAssertEqual(error, .emptyMacAgentId)
        }
    }

    private func trustedDevice(macAgentId: String = "mac_1") -> TrustedDevice {
        TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            accountId: "acct_1",
            macAgentId: macAgentId,
            pairedAt: now,
            validUntil: now.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}
