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
            macs: [],
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
            macs: [],
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

    private func mediaRef() -> MediaRef {
        MediaRef(
            ref: "media_1",
            macAgentId: "mac_1",
            r2Key: "r2/media_1",
            contentType: "image/png",
            expiresAt: now.addingTimeInterval(60)
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
