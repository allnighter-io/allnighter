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

    public init(
        relay: RemoteMacRelay,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.relay = relay
        self.now = now
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
