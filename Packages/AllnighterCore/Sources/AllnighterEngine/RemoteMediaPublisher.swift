import Foundation
import AllnighterCore

public struct RemoteMediaPublishResult: Equatable, Sendable {
    public var ref: MediaRef
    public var keyCount: Int

    public init(ref: MediaRef, keyCount: Int) {
        self.ref = ref
        self.keyCount = keyCount
    }
}

public struct RemoteMediaPublisher: Sendable {
    public let relay: RemoteMacRelay
    private let now: @Sendable () -> Date
    private let contentKeyFactory: @Sendable () -> Data

    public init(
        relay: RemoteMacRelay,
        now: @escaping @Sendable () -> Date = Date.init,
        contentKeyFactory: @escaping @Sendable () -> Data = RemoteMediaCrypto.randomContentKey
    ) {
        self.relay = relay
        self.now = now
        self.contentKeyFactory = contentKeyFactory
    }

    public func publishPlaintext(
        ref: String,
        macAgentId: String,
        r2Key: String,
        contentType: String,
        plaintextData: Data,
        trustedDevices: [TrustedDevice],
        expiresAt: Date
    ) async throws -> RemoteMediaPublishResult {
        let contentKey = contentKeyFactory()
        let encryptedData = try RemoteMediaCrypto.encrypt(plaintextData, contentKey: contentKey)
        return try await publish(
            ref: ref,
            macAgentId: macAgentId,
            r2Key: r2Key,
            contentType: contentType,
            encryptedData: encryptedData,
            contentKey: contentKey,
            trustedDevices: trustedDevices,
            expiresAt: expiresAt
        )
    }

    @discardableResult
    public func resealContentKey(
        ref: String,
        contentKey: Data,
        trustedDevice: TrustedDevice
    ) async throws -> Bool {
        let keys = try RemoteMediaCrypto.sealContentKey(
            contentKey,
            ref: ref,
            for: [trustedDevice],
            now: now()
        )
        guard let key = keys.first else {
            return false
        }
        try await relay.upsertMediaKey(key)
        return true
    }

    public func publish(
        ref: String,
        macAgentId: String,
        r2Key: String,
        contentType: String,
        encryptedData: Data,
        contentKey: Data,
        trustedDevices: [TrustedDevice],
        expiresAt: Date
    ) async throws -> RemoteMediaPublishResult {
        let mediaRef = MediaRef(
            ref: ref,
            macAgentId: macAgentId,
            r2Key: r2Key,
            contentType: contentType,
            expiresAt: expiresAt
        )
        let keys = try RemoteMediaCrypto.sealContentKey(
            contentKey,
            ref: ref,
            for: trustedDevices,
            now: now()
        )
        try await relay.publishMedia(ref: mediaRef, data: encryptedData, keys: keys)
        return RemoteMediaPublishResult(ref: mediaRef, keyCount: keys.count)
    }
}
