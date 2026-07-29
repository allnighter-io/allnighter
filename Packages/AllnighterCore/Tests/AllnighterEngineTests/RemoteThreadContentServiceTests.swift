import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteThreadContentServiceTests: XCTestCase {
    private var root: URL!
    private var threadStore: ThreadStore!
    private var trustedStore: TrustedRemoteStore!
    private var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private let now = Date(timeIntervalSince1970: 1_750_500_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-thread-content-\(UUID().uuidString)", isDirectory: true)
        threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSealedDetailOpensForActiveTrustedDeviceAndCarriesThreadTextOnlyInsideCiphertext() throws {
        try threadStore.saveForImport(threadWithSensitiveTurns())
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [trustedDevice()]))
        let service = makeService()

        let blob = try service.sealedDetail(threadId: "thread_1", forDeviceId: "device_1")
        let encodedBlob = String(decoding: try CoreJSON.encode(blob), as: UTF8.self)
        let opened = try RemoteCrypto.open(blob, with: deviceSealingKey)
        let openedJSON = String(decoding: opened, as: UTF8.self)
        let detail = try CoreJSON.decode(RemoteThreadDetail.self, from: opened)

        XCTAssertEqual(blob.contentType, RemoteThreadDetail.sealedContentType)
        XCTAssertEqual(blob.sealedForKeyId, "device_1")
        XCTAssertFalse(encodedBlob.contains("private prompt with token"))
        XCTAssertFalse(encodedBlob.contains("private worker reply"))
        XCTAssertFalse(encodedBlob.contains("private reasoning trace"))
        XCTAssertFalse(encodedBlob.contains("/Users/mike/private/repo"))
        XCTAssertEqual(detail.summary.id, "thread_1")
        XCTAssertEqual(detail.summary.readState.firstUnreadTurnId, "w1")
        XCTAssertEqual(detail.turns.map(\.id), ["u1", "w1"])
        XCTAssertEqual(detail.turns.first?.text, "private prompt with token")
        XCTAssertEqual(detail.turns.last?.text, "private worker reply")
        XCTAssertTrue(openedJSON.contains("private prompt with token"))
        XCTAssertTrue(openedJSON.contains("private worker reply"))
        XCTAssertFalse(openedJSON.contains("private reasoning trace"))
        XCTAssertFalse(openedJSON.contains("/Users/mike/private/repo"))
    }

    func testSealedDetailRejectsRevokedExpiredAndWrongScopeDevices() throws {
        try threadStore.saveForImport(threadWithSensitiveTurns())
        var revoked = trustedDevice(deviceId: "revoked")
        revoked.revoked = true
        var expired = trustedDevice(deviceId: "expired")
        expired.validUntil = now.addingTimeInterval(-1)
        let otherAccount = trustedDevice(accountId: "acct_2", deviceId: "other_account")
        let otherMac = trustedDevice(deviceId: "other_mac", macAgentId: "mac_2")
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [
            revoked,
            expired,
            otherAccount,
            otherMac,
        ]))
        let service = makeService()

        for deviceId in ["revoked", "expired", "other_account", "other_mac", "missing"] {
            XCTAssertThrowsError(try service.sealedDetail(threadId: "thread_1", forDeviceId: deviceId)) { error in
                XCTAssertEqual(error as? RemoteThreadContentServiceError, .deviceNotTrusted(deviceId))
            }
        }
    }

    func testSealedDetailRejectsMissingThreadBeforeSealing() throws {
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [trustedDevice()]))
        let service = makeService()

        XCTAssertThrowsError(try service.sealedDetail(threadId: "missing", forDeviceId: "device_1")) { error in
            XCTAssertEqual(error as? RemoteThreadContentServiceError, .threadNotFound("missing"))
        }
    }

    func testSealedDetailCannotOpenWithAnotherDeviceKey() throws {
        try threadStore.saveForImport(threadWithSensitiveTurns())
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [trustedDevice()]))
        let service = makeService()

        let blob = try service.sealedDetail(threadId: "thread_1", forDeviceId: "device_1")

        XCTAssertThrowsError(try RemoteCrypto.open(blob, with: Curve25519.KeyAgreement.PrivateKey()))
    }

    private func makeService() -> RemoteThreadContentService {
        let fixedNow = now
        return RemoteThreadContentService(
            accountId: "acct_1",
            macAgentId: "mac_1",
            threadStore: threadStore,
            trustedStore: trustedStore,
            now: { fixedNow }
        )
    }

    private func trustedDevice(
        accountId: String = "acct_1",
        deviceId: String = "device_1",
        macAgentId: String = "mac_1"
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: "iPhone",
            deviceSigningPubkey: "sign_\(deviceId)",
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
    }

    private func threadWithSensitiveTurns() -> WorkThread {
        let userTurn = ThreadTurn(
            id: "u1",
            threadId: "thread_1",
            kind: .userMessage,
            status: .done,
            createdAt: now.addingTimeInterval(-20),
            completedAt: now.addingTimeInterval(-20),
            author: .user,
            text: "private prompt with token"
        )
        let workerTurn = ThreadTurn(
            id: "w1",
            threadId: "thread_1",
            kind: .workerChat,
            status: .done,
            createdAt: now.addingTimeInterval(-10),
            completedAt: now.addingTimeInterval(-10),
            author: .worker,
            text: "private worker reply",
            modelId: "codex",
            reasoningText: "private reasoning trace"
        )
        return WorkThread(
            id: "thread_1",
            title: "Visible title",
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-10),
            workingDir: "/Users/mike/private/repo",
            readCursor: ThreadReadCursor(
                lastReadTurnId: "u1",
                lastReadTurnCreatedAt: userTurn.createdAt,
                readAt: userTurn.createdAt
            ),
            turns: [userTurn, workerTurn]
        )
    }
}
