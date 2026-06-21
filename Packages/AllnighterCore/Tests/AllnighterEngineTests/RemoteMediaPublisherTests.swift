import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteMediaPublisherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_751_900_000)

    func testPublisherStoresEncryptedMediaAndFanoutKeysForActiveDevices() async throws {
        let activeKey = Curve25519.KeyAgreement.PrivateKey()
        let revokedKey = Curve25519.KeyAgreement.PrivateKey()
        let relay = MockRemoteMacRelay()
        let fixedNow = now
        let publisher = RemoteMediaPublisher(relay: relay, now: { fixedNow })
        let contentKey = Data("content-key".utf8)
        let encryptedData = Data("encrypted-image-bytes".utf8)

        let result = try await publisher.publish(
            ref: "media_1",
            macAgentId: "mac_1",
            r2Key: "r2/media_1",
            contentType: "image/png",
            encryptedData: encryptedData,
            contentKey: contentKey,
            trustedDevices: [
                device(deviceId: "device_revoked", sealingKey: revokedKey, revoked: true),
                device(deviceId: "device_active", sealingKey: activeKey),
            ],
            expiresAt: now.addingTimeInterval(60)
        )

        XCTAssertEqual(result.ref.ref, "media_1")
        XCTAssertEqual(result.keyCount, 1)
        let data = try await relay.mediaData(ref: "media_1", macAgentId: "mac_1", at: now)
        XCTAssertEqual(data, encryptedData)
        let fetchedActiveEnvelope = try await relay.mediaKey(
            ref: "media_1",
            deviceId: "device_active",
            at: now
        )
        let activeEnvelope = try XCTUnwrap(fetchedActiveEnvelope)
        XCTAssertEqual(try RemoteMediaCrypto.openContentKey(activeEnvelope, with: activeKey), contentKey)
        let revokedEnvelope = try await relay.mediaKey(
            ref: "media_1",
            deviceId: "device_revoked",
            at: now
        )
        XCTAssertNil(revokedEnvelope)
    }

    private func device(
        deviceId: String,
        sealingKey: Curve25519.KeyAgreement.PrivateKey,
        revoked: Bool = false
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: deviceId,
            deviceSigningPubkey: "sign_\(deviceId)",
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            revoked: revoked,
            revokedAt: revoked ? now : nil,
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}
