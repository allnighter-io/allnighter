import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModePairingStatusReaderTests: XCTestCase {
    private var root: URL!
    private var store: TrustedRemoteStore!
    private let now = Date(timeIntervalSince1970: 1_750_600_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-mode-pair-status-\(UUID().uuidString)", isDirectory: true)
        store = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testStatusReportsExpiredPendingRequest() throws {
        try store.upsertPending(pairRequest(expiresAt: now.addingTimeInterval(-1)))
        let reader = makeReader()

        let response = try reader.status(DirectModePairingStatusRequest(
            requestId: "pair_request_1",
            deviceId: "device_1"
        ))

        XCTAssertEqual(response.status, .expired)
        XCTAssertEqual(response.pairRequest?.status, .expired)
        XCTAssertNil(response.trustedDevice)
    }

    func testStatusReportsRevokedTrustedDevice() throws {
        try store.save(TrustedRemoteRegistry(trustedDevices: [trustedDevice(revoked: true)]))
        let reader = makeReader()

        let response = try reader.status(DirectModePairingStatusRequest(
            requestId: "pair_request_1",
            deviceId: "device_1"
        ))

        XCTAssertEqual(response.status, .revoked)
        XCTAssertEqual(response.trustedDevice?.deviceId, "device_1")
        XCTAssertEqual(response.trustedDevice?.revoked, true)
    }

    func testStatusReportsNotFoundOutsideScopedAccountOrMac() throws {
        try store.upsertPending(pairRequest(accountId: "acct_other"))
        try store.save(TrustedRemoteRegistry(trustedDevices: [trustedDevice(macAgentId: "mac_other")]))
        let reader = makeReader()

        let response = try reader.status(DirectModePairingStatusRequest(
            requestId: "pair_request_1",
            deviceId: "device_1"
        ))

        XCTAssertEqual(response.status, .notFound)
        XCTAssertNil(response.pairRequest)
        XCTAssertNil(response.trustedDevice)
    }

    private func makeReader() -> DirectModePairingStatusReader {
        let fixedNow = now
        return DirectModePairingStatusReader(
            accountId: "acct_1",
            macAgentId: "mac_1",
            trustedStore: store,
            now: { fixedNow }
        )
    }

    private func pairRequest(
        accountId: String = "acct_1",
        macAgentId: String = "mac_1",
        expiresAt: Date? = nil
    ) -> RemotePairRequest {
        RemotePairRequest(
            id: "pair_request_1",
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            requestedAt: now.addingTimeInterval(-60),
            expiresAt: expiresAt ?? now.addingTimeInterval(120)
        )
    }

    private func trustedDevice(
        accountId: String = "acct_1",
        macAgentId: String = "mac_1",
        revoked: Bool = false
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now,
            validUntil: now.addingTimeInterval(120),
            revoked: revoked,
            revokedAt: revoked ? now : nil,
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}
