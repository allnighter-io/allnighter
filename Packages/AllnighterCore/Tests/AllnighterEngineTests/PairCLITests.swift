import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

final class PairCLITests: XCTestCase {
    func testListJSONUsesTrustedRemoteEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-cli-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try store.upsertPending(RemotePairRequest(
            id: "pair_1",
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "sign",
            deviceSealingPubkey: "seal",
            requestedAt: now,
            expiresAt: now.addingTimeInterval(300)
        ))

        let payload = PairCLI.listJSON(store: store, now: now)

        XCTAssertEqual(payload.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(payload.pendingRequests.map(\.deviceId), ["device_1"])
        XCTAssertTrue(payload.trustedDevices.isEmpty)
    }
}
