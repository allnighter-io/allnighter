import CryptoKit
import XCTest
@testable import AllnighterCore

final class RemoteMediaFetcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_410_000)

    func testFetcherDownloadsMediaBundleAndDecryptsLocally() async throws {
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let contentKey = Data((0..<RemoteMediaCrypto.contentKeyByteCount).map(UInt8.init))
        let plaintext = Data("private board image bytes".utf8)
        let encryptedData = try RemoteMediaCrypto.encrypt(plaintext, contentKey: contentKey)
        let ref = mediaRef()
        let keyEnvelope = try XCTUnwrap(RemoteMediaCrypto.sealContentKey(
            contentKey,
            ref: ref.ref,
            for: [trustedDevice(deviceId: "device_1", sealingKey: deviceSealingKey)],
            now: now
        ).first)
        let client = MockiOSClient(
            macs: [mac()],
            media: [ref.ref: encryptedData],
            mediaKeys: [ref.ref: ["device_1": keyEnvelope]],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let bundle = try await RemoteMediaFetcher.fetchBundle(client: client, ref: ref, deviceId: "device_1")
        let decrypted = try await RemoteMediaFetcher.fetchAndDecrypt(
            client: client,
            ref: ref,
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey
        )

        XCTAssertEqual(bundle.ref, ref)
        XCTAssertEqual(bundle.encryptedData, encryptedData)
        XCTAssertEqual(bundle.keyEnvelope, keyEnvelope)
        XCTAssertNotEqual(bundle.encryptedData, plaintext)
        XCTAssertEqual(try bundle.decrypt(with: deviceSealingKey), plaintext)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testFetcherPropagatesMissingMediaKey() async throws {
        let ref = mediaRef()
        let client = MockiOSClient(
            macs: [mac()],
            media: [ref.ref: Data("ciphertext".utf8)],
            mediaKeys: [:],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        do {
            _ = try await RemoteMediaFetcher.fetchBundle(client: client, ref: ref, deviceId: "device_missing")
            XCTFail("missing media key should propagate")
        } catch let error as MockRemoteClientError {
            XCTAssertEqual(error, .mediaKeyNotFound(ref: ref.ref, deviceId: "device_missing"))
        }
    }

    func testFetcherRejectsMismatchedMediaKeyEnvelope() async throws {
        let ref = mediaRef()
        let mismatchedKey = MediaKeyEnvelope(
            ref: "media_other",
            deviceId: "device_other",
            sealedKey: SealedBlob(
                ciphertext: Data("ciphertext".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: "device_other",
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
        let client = MockiOSClient(
            macs: [mac()],
            media: [ref.ref: Data("ciphertext".utf8)],
            mediaKeys: [ref.ref: ["device_1": mismatchedKey]],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        do {
            _ = try await RemoteMediaFetcher.fetchBundle(client: client, ref: ref, deviceId: "device_1")
            XCTFail("mismatched media key envelope should be rejected")
        } catch let error as RemoteMediaFetcherError {
            XCTAssertEqual(error, .mediaKeyMismatch(
                expectedRef: "media_1",
                actualRef: "media_other",
                expectedDeviceId: "device_1",
                actualDeviceId: "device_other"
            ))
        }
    }

    func testMockClientRejectsExpiredMediaData() async throws {
        let ref = mediaRef(expiresAt: now.addingTimeInterval(-1))
        let client = MockiOSClient(
            macs: [mac()],
            media: [ref.ref: Data("ciphertext".utf8)],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        do {
            _ = try await client.fetchSealed(ref)
            XCTFail("expired media should not return sealed data")
        } catch let error as MockRemoteClientError {
            XCTAssertEqual(error, .mediaNotFound(ref.ref))
        }
    }

    func testMockClientRejectsExpiredMediaKey() async throws {
        let ref = mediaRef(expiresAt: now.addingTimeInterval(-1))
        let keyEnvelope = MediaKeyEnvelope(
            ref: ref.ref,
            deviceId: "device_1",
            sealedKey: SealedBlob(
                ciphertext: Data("sealed-key".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: "device_1",
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
        let client = MockiOSClient(
            macs: [mac()],
            mediaKeys: [ref.ref: ["device_1": keyEnvelope]],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        do {
            _ = try await client.fetchMediaKey(ref, deviceId: "device_1")
            XCTFail("expired media should not return device keys")
        } catch let error as MockRemoteClientError {
            XCTAssertEqual(error, .mediaKeyNotFound(ref: ref.ref, deviceId: "device_1"))
        }
    }

    func testMockClientScopesMediaByMacAgent() async throws {
        let ref = mediaRef(ref: "media_shared", macAgentId: "mac_1")
        let sameRefOtherMac = mediaRef(ref: "media_shared", macAgentId: "mac_2")
        let keyEnvelope = MediaKeyEnvelope(
            ref: "media_shared",
            deviceId: "device_1",
            sealedKey: SealedBlob(
                ciphertext: Data("sealed-key".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: "device_1",
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
        let client = MockiOSClient(
            macs: [mac(macAgentId: "mac_1"), mac(macAgentId: "mac_2")],
            media: [ref.ref: Data("mac-1-ciphertext".utf8)],
            mediaKeys: [ref.ref: ["device_1": keyEnvelope]],
            serverNow: now
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let fetchedData = try await client.fetchSealed(ref)
        let fetchedKey = try await client.fetchMediaKey(ref, deviceId: "device_1")
        XCTAssertEqual(fetchedData, Data("mac-1-ciphertext".utf8))
        XCTAssertEqual(fetchedKey, keyEnvelope)
        do {
            _ = try await client.fetchSealed(sameRefOtherMac)
            XCTFail("same media ref on another Mac should not return this Mac's data")
        } catch let error as MockRemoteClientError {
            XCTAssertEqual(error, .mediaNotFound("media_shared"))
        }
        do {
            _ = try await client.fetchMediaKey(sameRefOtherMac, deviceId: "device_1")
            XCTFail("same media ref on another Mac should not return this Mac's key")
        } catch let error as MockRemoteClientError {
            XCTAssertEqual(error, .mediaKeyNotFound(ref: "media_shared", deviceId: "device_1"))
        }
    }

    private func mediaRef(
        ref: String = "media_1",
        macAgentId: String = "mac_1",
        expiresAt: Date? = nil
    ) -> MediaRef {
        MediaRef(
            ref: ref,
            macAgentId: macAgentId,
            r2Key: "r2/\(ref)",
            contentType: "image/png",
            expiresAt: expiresAt ?? now.addingTimeInterval(60)
        )
    }

    private func mac(macAgentId: String = "mac_1") -> MacAgentRef {
        MacAgentRef(
            macAgentId: macAgentId,
            displayName: "Studio \(macAgentId)",
            agentSigningPubkey: "sign_\(macAgentId)",
            agentSealingPubkey: "seal_\(macAgentId)"
        )
    }

    private func trustedDevice(
        deviceId: String,
        sealingKey: Curve25519.KeyAgreement.PrivateKey
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
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}
