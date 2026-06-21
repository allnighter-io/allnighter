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

    func testPublisherEncryptsPlaintextBeforePublishingMedia() async throws {
        let activeKey = Curve25519.KeyAgreement.PrivateKey()
        let relay = MockRemoteMacRelay()
        let fixedNow = now
        let contentKey = Data((0..<RemoteMediaCrypto.contentKeyByteCount).map(UInt8.init))
        let publisher = RemoteMediaPublisher(
            relay: relay,
            now: { fixedNow },
            contentKeyFactory: { contentKey }
        )
        let plaintext = Data("secret board image bytes".utf8)

        let result = try await publisher.publishPlaintext(
            ref: "media_plain",
            macAgentId: "mac_1",
            r2Key: "r2/media_plain",
            contentType: "image/png",
            plaintextData: plaintext,
            trustedDevices: [
                device(deviceId: "device_active", sealingKey: activeKey),
            ],
            expiresAt: now.addingTimeInterval(60)
        )

        XCTAssertEqual(result.ref.ref, "media_plain")
        XCTAssertEqual(result.keyCount, 1)
        let fetchedEncryptedData = try await relay.mediaData(
            ref: "media_plain",
            macAgentId: "mac_1",
            at: now
        )
        let encryptedData = try XCTUnwrap(fetchedEncryptedData)
        XCTAssertNotEqual(encryptedData, plaintext)
        XCTAssertFalse(String(decoding: encryptedData, as: UTF8.self).contains("secret board image bytes"))
        let fetchedEnvelope = try await relay.mediaKey(
            ref: "media_plain",
            deviceId: "device_active",
            at: now
        )
        let envelope = try XCTUnwrap(fetchedEnvelope)
        let openedContentKey = try RemoteMediaCrypto.openContentKey(envelope, with: activeKey)
        XCTAssertEqual(openedContentKey, contentKey)
        XCTAssertEqual(try RemoteMediaCrypto.decrypt(encryptedData, contentKey: openedContentKey), plaintext)
    }

    func testPublisherResealsExistingContentKeyForLaterDevice() async throws {
        let firstKey = Curve25519.KeyAgreement.PrivateKey()
        let laterKey = Curve25519.KeyAgreement.PrivateKey()
        let revokedKey = Curve25519.KeyAgreement.PrivateKey()
        let relay = MockRemoteMacRelay()
        let fixedNow = now
        let contentKey = Data((0..<RemoteMediaCrypto.contentKeyByteCount).map(UInt8.init))
        let publisher = RemoteMediaPublisher(relay: relay, now: { fixedNow })
        _ = try await publisher.publish(
            ref: "media_reseal",
            macAgentId: "mac_1",
            r2Key: "r2/media_reseal",
            contentType: "image/png",
            encryptedData: Data("ciphertext".utf8),
            contentKey: contentKey,
            trustedDevices: [
                device(deviceId: "device_first", sealingKey: firstKey),
            ],
            expiresAt: now.addingTimeInterval(60)
        )

        let didResealLater = try await publisher.resealContentKey(
            ref: "media_reseal",
            contentKey: contentKey,
            trustedDevice: device(deviceId: "device_later", sealingKey: laterKey)
        )
        let didResealRevoked = try await publisher.resealContentKey(
            ref: "media_reseal",
            contentKey: contentKey,
            trustedDevice: device(deviceId: "device_revoked", sealingKey: revokedKey, revoked: true)
        )

        XCTAssertTrue(didResealLater)
        XCTAssertFalse(didResealRevoked)
        let data = try await relay.mediaData(ref: "media_reseal", macAgentId: "mac_1", at: now)
        XCTAssertEqual(data, Data("ciphertext".utf8))
        let fetchedLaterEnvelope = try await relay.mediaKey(
            ref: "media_reseal",
            deviceId: "device_later",
            at: now
        )
        let laterEnvelope = try XCTUnwrap(fetchedLaterEnvelope)
        XCTAssertEqual(try RemoteMediaCrypto.openContentKey(laterEnvelope, with: laterKey), contentKey)
        let revokedEnvelope = try await relay.mediaKey(
            ref: "media_reseal",
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
