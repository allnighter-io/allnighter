#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

public enum RemoteMediaFetcherError: Error, Equatable, Sendable {
    case mediaKeyMismatch(
        expectedMacAgentId: String,
        actualMacAgentId: String,
        expectedRef: String,
        actualRef: String,
        expectedDeviceId: String,
        actualDeviceId: String
    )
}

public struct RemoteMediaBundle: Equatable, Sendable {
    public var ref: MediaRef
    public var encryptedData: Data
    public var keyEnvelope: MediaKeyEnvelope

    public init(
        ref: MediaRef,
        encryptedData: Data,
        keyEnvelope: MediaKeyEnvelope
    ) {
        self.ref = ref
        self.encryptedData = encryptedData
        self.keyEnvelope = keyEnvelope
    }

    public func decrypt(with deviceSealingKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        let contentKey = try RemoteMediaCrypto.openContentKey(keyEnvelope, with: deviceSealingKey)
        return try RemoteMediaCrypto.decrypt(encryptedData, contentKey: contentKey)
    }
}

public enum RemoteMediaFetcher {
    public static func fetchBundle(
        client: any RemoteClient,
        ref: MediaRef,
        deviceId: String
    ) async throws -> RemoteMediaBundle {
        async let encryptedData = client.fetchSealed(ref)
        async let keyEnvelope = client.fetchMediaKey(ref, deviceId: deviceId)
        let bundle = try await RemoteMediaBundle(
            ref: ref,
            encryptedData: encryptedData,
            keyEnvelope: keyEnvelope
        )
        guard bundle.keyEnvelope.macAgentId == ref.macAgentId,
              bundle.keyEnvelope.ref == ref.ref,
              bundle.keyEnvelope.deviceId == deviceId else {
            throw RemoteMediaFetcherError.mediaKeyMismatch(
                expectedMacAgentId: ref.macAgentId,
                actualMacAgentId: bundle.keyEnvelope.macAgentId,
                expectedRef: ref.ref,
                actualRef: bundle.keyEnvelope.ref,
                expectedDeviceId: deviceId,
                actualDeviceId: bundle.keyEnvelope.deviceId
            )
        }
        return bundle
    }

    public static func fetchAndDecrypt(
        client: any RemoteClient,
        ref: MediaRef,
        deviceId: String,
        deviceSealingKey: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> Data {
        let bundle = try await fetchBundle(client: client, ref: ref, deviceId: deviceId)
        return try bundle.decrypt(with: deviceSealingKey)
    }
}
