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

    private func pairDraft(
        accountId: String = "acct_1",
        macAgentId: String = "mac_1",
        deviceId: String,
        displayName: String = "Mike's iPhone",
        requestedAt: Date? = nil
    ) -> RemotePairRequestDraft {
        RemotePairRequestDraft(
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: "sign-\(deviceId)",
            deviceSealingPubkey: "seal-\(deviceId)",
            requestedAt: requestedAt ?? now,
            expiresAt: now.addingTimeInterval(300)
        )
    }
}
