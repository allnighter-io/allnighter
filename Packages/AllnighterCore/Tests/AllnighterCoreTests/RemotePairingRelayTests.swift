import XCTest
@testable import AllnighterCore

final class RemotePairingRelayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_800_000)

    func testSubmitPairRequestStoresPendingRequestForMacAgentImport() async throws {
        let relay = MockRemoteMacRelay(pairRequestIdFactory: { "pair_request_1" })
        let draft = pairDraft(deviceId: "device_1")

        let request = try await relay.submitPairRequest(draft)

        XCTAssertEqual(request, draft.pairRequest(id: "pair_request_1"))
        let pending = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(pending, [request])

        let wrongAccount = try await relay.pendingPairRequests(accountId: "acct_other", macAgentId: "mac_1")
        XCTAssertTrue(wrongAccount.isEmpty)

        let eventLog = await relay.eventLog
        XCTAssertEqual(Array(eventLog.prefix(2)), ["submitPairRequest", "pendingPairRequests"])
    }

    func testPendingPairRequestsFiltersStatusAndSortsByRequestedAt() async throws {
        let later = pairDraft(deviceId: "device_later", requestedAt: now.addingTimeInterval(10))
            .pairRequest(id: "pair_later")
        let earlier = pairDraft(deviceId: "device_earlier", requestedAt: now)
            .pairRequest(id: "pair_earlier")
        let approved = RemotePairRequest(
            id: "pair_approved",
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: "device_approved",
            displayName: "Approved iPhone",
            deviceSigningPubkey: "sign-approved",
            deviceSealingPubkey: "seal-approved",
            status: RemotePairRequestStatus.approved,
            requestedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(300)
        )
        let otherMac = pairDraft(macAgentId: "mac_other", deviceId: "device_other")
            .pairRequest(id: "pair_other")
        let relay = MockRemoteMacRelay(pairRequests: [later, approved, earlier, otherMac])

        let pending = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")

        XCTAssertEqual(pending.map(\.id), ["pair_earlier", "pair_later"])
    }

    func testSubmitPairRequestReplacesExistingDeviceRequestForMac() async throws {
        let old = pairDraft(deviceId: "device_1", displayName: "Old iPhone")
            .pairRequest(id: "pair_old")
        let relay = MockRemoteMacRelay(
            pairRequests: [old],
            pairRequestIdFactory: { "pair_new" }
        )

        let new = try await relay.submitPairRequest(pairDraft(
            deviceId: "device_1",
            displayName: "New iPhone"
        ))

        let pending = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(pending, [new])
        XCTAssertEqual(pending.first?.displayName, "New iPhone")
    }

    func testSubmitPairRequestPreservesSameDeviceForOtherAccount() async throws {
        let existing = pairDraft(accountId: "acct_1", deviceId: "device_1")
            .pairRequest(id: "pair_existing")
        let relay = MockRemoteMacRelay(
            pairRequests: [existing],
            pairRequestIdFactory: { "pair_new" }
        )

        let new = try await relay.submitPairRequest(pairDraft(
            accountId: "acct_2",
            deviceId: "device_1",
            displayName: "Other Account iPhone"
        ))

        let firstAccount = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        let secondAccount = try await relay.pendingPairRequests(accountId: "acct_2", macAgentId: "mac_1")
        XCTAssertEqual(firstAccount, [existing])
        XCTAssertEqual(secondAccount, [new])
    }

    func testUpdatePairRequestPreservesSameDeviceForOtherAccount() async throws {
        let existing = pairDraft(accountId: "acct_1", deviceId: "device_1")
            .pairRequest(id: "pair_existing")
        var updated = pairDraft(accountId: "acct_2", deviceId: "device_1")
            .pairRequest(id: "pair_updated")
        updated.status = .approved
        let relay = MockRemoteMacRelay(pairRequests: [existing])

        _ = try await relay.updatePairRequest(updated)

        let firstAccount = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        let secondAccountStatus = try await relay.pairRequestStatus(
            accountId: "acct_2",
            requestId: "pair_updated",
            deviceId: "device_1",
            checkedAt: now
        )
        XCTAssertEqual(firstAccount, [existing])
        XCTAssertEqual(secondAccountStatus.pairRequest, updated)
    }

    func testUpsertTrustedDevicePreservesSameDeviceForOtherAccount() async throws {
        let existing = trustedDevice(accountId: "acct_1", deviceId: "device_1")
        let otherAccount = trustedDevice(accountId: "acct_2", deviceId: "device_1")
        let relay = MockRemoteMacRelay(trustedDevices: [existing])

        try await relay.upsertTrustedDevice(otherAccount)

        let firstAccount = try await relay.trustedDevices(accountId: "acct_1", macAgentId: "mac_1")
        let secondAccount = try await relay.trustedDevices(accountId: "acct_2", macAgentId: "mac_1")
        XCTAssertEqual(firstAccount, [existing])
        XCTAssertEqual(secondAccount, [otherAccount])
    }

    func testPairRequestStatusReportsPendingExpiredAndNotFound() async throws {
        let pending = pairDraft(deviceId: "device_1")
            .pairRequest(id: "pair_request_1")
        let expired = pairDraft(
            deviceId: "device_expired",
            expiresAt: now.addingTimeInterval(-1)
        ).pairRequest(id: "pair_expired")
        let relay = MockRemoteMacRelay(pairRequests: [pending, expired])

        let pendingStatus = try await relay.pairRequestStatus(
            accountId: "acct_1",
            requestId: "pair_request_1",
            deviceId: "device_1",
            checkedAt: now
        )
        let expiredStatus = try await relay.pairRequestStatus(
            accountId: "acct_1",
            requestId: "pair_expired",
            deviceId: "device_expired",
            checkedAt: now
        )
        let missingStatus = try await relay.pairRequestStatus(
            accountId: "acct_other",
            requestId: "pair_request_1",
            deviceId: "device_1",
            checkedAt: now
        )

        XCTAssertEqual(pendingStatus.status, .pending)
        XCTAssertEqual(pendingStatus.pairRequest, pending)
        XCTAssertEqual(expiredStatus.status, .expired)
        XCTAssertEqual(expiredStatus.pairRequest?.status, .expired)
        XCTAssertEqual(missingStatus.status, .notFound)
        XCTAssertNil(missingStatus.pairRequest)
        XCTAssertNil(missingStatus.trustedDevice)
    }

    func testPairRequestStatusPrefersTrustedDeviceState() async throws {
        var approved = pairDraft(deviceId: "device_approved")
            .pairRequest(id: "pair_approved")
        approved.status = .approved
        let revoked = pairDraft(deviceId: "device_revoked")
            .pairRequest(id: "pair_revoked")
        let expired = pairDraft(deviceId: "device_expired_trusted")
            .pairRequest(id: "pair_expired_trusted")
        let relay = MockRemoteMacRelay(
            pairRequests: [approved, revoked, expired],
            trustedDevices: [
                trustedDevice(deviceId: "device_approved"),
                trustedDevice(deviceId: "device_revoked", revoked: true),
                trustedDevice(
                    deviceId: "device_expired_trusted",
                    validUntil: now.addingTimeInterval(-1)
                )
            ]
        )

        let approvedStatus = try await relay.pairRequestStatus(
            accountId: "acct_1",
            requestId: "pair_approved",
            deviceId: "device_approved",
            checkedAt: now
        )
        let revokedStatus = try await relay.pairRequestStatus(
            accountId: "acct_1",
            requestId: "pair_revoked",
            deviceId: "device_revoked",
            checkedAt: now
        )
        let expiredStatus = try await relay.pairRequestStatus(
            accountId: "acct_1",
            requestId: "pair_expired_trusted",
            deviceId: "device_expired_trusted",
            checkedAt: now
        )

        XCTAssertEqual(approvedStatus.status, .approved)
        XCTAssertEqual(approvedStatus.trustedDevice?.deviceId, "device_approved")
        XCTAssertEqual(revokedStatus.status, .revoked)
        XCTAssertEqual(revokedStatus.trustedDevice?.revoked, true)
        XCTAssertEqual(expiredStatus.status, .expired)
        XCTAssertEqual(expiredStatus.trustedDevice?.validUntil, now.addingTimeInterval(-1))
    }

    private func pairDraft(
        accountId: String = "acct_1",
        macAgentId: String = "mac_1",
        deviceId: String,
        displayName: String = "Mike's iPhone",
        requestedAt: Date? = nil,
        expiresAt: Date? = nil
    ) -> RemotePairRequestDraft {
        RemotePairRequestDraft(
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: "sign-\(deviceId)",
            deviceSealingPubkey: "seal-\(deviceId)",
            requestedAt: requestedAt ?? now,
            expiresAt: expiresAt ?? now.addingTimeInterval(300)
        )
    }

    private func trustedDevice(
        accountId: String = "acct_1",
        macAgentId: String = "mac_1",
        deviceId: String,
        revoked: Bool = false,
        validUntil: Date? = nil
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "sign-\(deviceId)",
            deviceSealingPubkey: "seal-\(deviceId)",
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now,
            validUntil: validUntil ?? now.addingTimeInterval(3_600),
            revoked: revoked,
            revokedAt: revoked ? now : nil,
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}
