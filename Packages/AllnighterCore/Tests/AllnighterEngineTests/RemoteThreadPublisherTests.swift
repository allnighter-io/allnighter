import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteThreadPublisherTests: XCTestCase {
    private var root: URL!
    private var threadStore: ThreadStore!
    private var trustedStore: TrustedRemoteStore!
    private var activeDeviceKey: Curve25519.KeyAgreement.PrivateKey!
    private let now = Date(timeIntervalSince1970: 1_750_900_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-thread-publisher-\(UUID().uuidString)", isDirectory: true)
        threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        activeDeviceKey = Curve25519.KeyAgreement.PrivateKey()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testPublishWritesThreadSnapshotAndSealsDetailOnlyForActiveScopedDevices() async throws {
        try threadStore.saveForImport(thread())
        let active = trustedDevice(deviceId: "device_active", sealingKey: activeDeviceKey)
        var revoked = trustedDevice(deviceId: "device_revoked", sealingKey: Curve25519.KeyAgreement.PrivateKey())
        revoked.revoked = true
        var expired = trustedDevice(deviceId: "device_expired", sealingKey: Curve25519.KeyAgreement.PrivateKey())
        expired.validUntil = now.addingTimeInterval(-1)
        let otherAccount = trustedDevice(
            accountId: "acct_2",
            deviceId: "device_other_account",
            sealingKey: Curve25519.KeyAgreement.PrivateKey()
        )
        let otherMac = trustedDevice(
            macAgentId: "mac_2",
            deviceId: "device_other_mac",
            sealingKey: Curve25519.KeyAgreement.PrivateKey()
        )
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [
            active,
            revoked,
            expired,
            otherAccount,
            otherMac,
        ]))
        let relay = MockRemoteMacRelay()
        let publisher = makePublisher(relay: relay)

        let result = try await publisher.publish()

        XCTAssertEqual(result.threadCount, 1)
        XCTAssertEqual(result.sealedDetailCount, 1)
        let snapshot = try await relay.threadSnapshot(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(snapshot?.threads.map(\.id), ["thread_1"])
        let snapshotJSON = String(decoding: try CoreJSON.encode(snapshot), as: UTF8.self)
        XCTAssertFalse(snapshotJSON.contains("private prompt"))
        XCTAssertFalse(snapshotJSON.contains("private reply"))

        let activeDetailBlob = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_active"
        )
        let detailBlob = try XCTUnwrap(activeDetailBlob)
        let encodedBlob = String(decoding: try CoreJSON.encode(detailBlob), as: UTF8.self)
        XCTAssertFalse(encodedBlob.contains("private prompt"))
        XCTAssertFalse(encodedBlob.contains("private reply"))
        let opened = try RemoteCrypto.open(detailBlob, with: activeDeviceKey)
        let detail = try CoreJSON.decode(RemoteThreadDetail.self, from: opened)
        XCTAssertEqual(detail.turns.map(\.text), ["private prompt", "private reply"])

        let revokedDetail = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_revoked"
        )
        XCTAssertNil(revokedDetail)
        let expiredDetail = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_expired"
        )
        XCTAssertNil(expiredDetail)
        let otherAccountDetail = try await relay.sealedThreadDetail(
            accountId: "acct_2",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_other_account"
        )
        XCTAssertNil(otherAccountDetail)
        let otherMacDetail = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_2",
            threadId: "thread_1",
            deviceId: "device_other_mac"
        )
        XCTAssertNil(otherMacDetail)
    }

    func testPublishStillWritesSnapshotWhenNoActiveDevicesExist() async throws {
        try threadStore.saveForImport(thread())
        var revoked = trustedDevice(deviceId: "device_revoked", sealingKey: Curve25519.KeyAgreement.PrivateKey())
        revoked.revoked = true
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [revoked]))
        let relay = MockRemoteMacRelay()
        let publisher = makePublisher(relay: relay)

        let result = try await publisher.publish()

        XCTAssertEqual(result.threadCount, 1)
        XCTAssertEqual(result.sealedDetailCount, 0)
        let snapshot = try await relay.threadSnapshot(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(snapshot?.threads.map(\.id), ["thread_1"])
        let detail = try await relay.sealedThreadDetail(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadId: "thread_1",
            deviceId: "device_revoked"
        )
        XCTAssertNil(detail)
    }

    private func makePublisher(relay: MockRemoteMacRelay) -> RemoteThreadPublisher {
        let fixedNow = now
        return RemoteThreadPublisher(
            accountId: "acct_1",
            macAgentId: "mac_1",
            snapshotService: RemoteThreadSnapshotService(threadStore: threadStore, now: { fixedNow }),
            contentService: RemoteThreadContentService(
                accountId: "acct_1",
                macAgentId: "mac_1",
                threadStore: threadStore,
                trustedStore: trustedStore,
                now: { fixedNow }
            ),
            relay: relay,
            now: { fixedNow }
        )
    }

    private func trustedDevice(
        accountId: String = "acct_1",
        macAgentId: String = "mac_1",
        deviceId: String,
        sealingKey: Curve25519.KeyAgreement.PrivateKey
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: deviceId,
            deviceSigningPubkey: "sign_\(deviceId)",
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
    }

    private func thread() -> WorkThread {
        let userTurn = ThreadTurn(
            id: "u1",
            threadId: "thread_1",
            kind: .userMessage,
            status: .done,
            createdAt: now.addingTimeInterval(-20),
            completedAt: now.addingTimeInterval(-20),
            author: .user,
            text: "private prompt"
        )
        let workerTurn = ThreadTurn(
            id: "w1",
            threadId: "thread_1",
            kind: .workerChat,
            status: .done,
            createdAt: now.addingTimeInterval(-10),
            completedAt: now.addingTimeInterval(-10),
            author: .worker,
            text: "private reply",
            workerId: "codex"
        )
        return WorkThread(
            id: "thread_1",
            title: "Visible title",
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-10),
            turns: [userTurn, workerTurn]
        )
    }
}
