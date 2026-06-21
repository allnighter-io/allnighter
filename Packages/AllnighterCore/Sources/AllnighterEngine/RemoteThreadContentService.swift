import Foundation
import AllnighterCore

public enum RemoteThreadContentServiceError: Error, Equatable, Sendable {
    case threadNotFound(String)
    case deviceNotTrusted(String)
}

public struct RemoteThreadContentService: Sendable {
    public static let detailContentType = "application/vnd.allnighter.remote-thread-detail+json"

    public let accountId: String
    public let macAgentId: String
    public let threadStore: ThreadStore
    public let trustedStore: TrustedRemoteStore
    private let now: @Sendable () -> Date

    public init(
        accountId: String,
        macAgentId: String,
        threadStore: ThreadStore = ThreadStore(),
        trustedStore: TrustedRemoteStore = TrustedRemoteStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.threadStore = threadStore
        self.trustedStore = trustedStore
        self.now = now
    }

    func detail(threadId: String, pendingThreadIds: Set<String> = []) throws -> RemoteThreadDetail {
        guard let thread = threadStore.get(threadId) else {
            throw RemoteThreadContentServiceError.threadNotFound(threadId)
        }
        return RemoteThreadProjection.detail(
            from: thread,
            hasPendingItem: pendingThreadIds.contains(thread.id)
        )
    }

    public func sealedDetail(
        threadId: String,
        forDeviceId deviceId: String,
        pendingThreadIds: Set<String> = []
    ) throws -> SealedBlob {
        let device = try trustedDevice(deviceId: deviceId)
        let detail = try detail(threadId: threadId, pendingThreadIds: pendingThreadIds)
        return try RemoteCrypto.seal(
            CoreJSON.encode(detail),
            to: device.deviceSealingPubkey,
            sealedForKeyId: device.deviceId,
            contentType: Self.detailContentType
        )
    }

    private func trustedDevice(deviceId: String) throws -> TrustedDevice {
        let serverTime = now()
        let registry = try trustedStore.list(now: serverTime)
        guard let device = registry.trustedDevices.first(where: {
            $0.accountId == accountId
                && $0.macAgentId == macAgentId
                && $0.deviceId == deviceId
                && !$0.revoked
                && $0.validUntil >= serverTime
        }) else {
            throw RemoteThreadContentServiceError.deviceNotTrusted(deviceId)
        }
        return device
    }
}
