import Foundation
import AllnighterCore

public struct RemoteThreadPublishResult: Equatable, Sendable {
    public var threadCount: Int
    public var sealedDetailCount: Int

    public init(threadCount: Int, sealedDetailCount: Int) {
        self.threadCount = threadCount
        self.sealedDetailCount = sealedDetailCount
    }
}

public struct RemoteThreadPublisher: Sendable {
    public let accountId: String
    public let macAgentId: String
    public let snapshotService: RemoteThreadSnapshotService
    public let contentService: RemoteThreadContentService
    public let relay: RemoteMacRelay
    private let pendingQueueProvider: @Sendable () -> PendingQueueJSON?
    private let now: @Sendable () -> Date

    public init(
        accountId: String,
        macAgentId: String,
        snapshotService: RemoteThreadSnapshotService,
        contentService: RemoteThreadContentService,
        relay: RemoteMacRelay,
        pendingQueueProvider: @escaping @Sendable () -> PendingQueueJSON? = { nil },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.snapshotService = snapshotService
        self.contentService = contentService
        self.relay = relay
        self.pendingQueueProvider = pendingQueueProvider
        self.now = now
    }

    public func publish(pendingThreadIds: Set<String> = []) async throws -> RemoteThreadPublishResult {
        var snapshot = snapshotService.snapshot(pendingThreadIds: pendingThreadIds)
        snapshot.pendingQueue = pendingQueueProvider()
        try await relay.publishThreadSnapshot(
            accountId: accountId,
            macAgentId: macAgentId,
            snapshot: snapshot
        )

        let devices = try activeDevices(at: now())
        var sealedDetailCount = 0
        for thread in snapshot.threads {
            for device in devices {
                let detail = try contentService.sealedDetail(
                    threadId: thread.id,
                    forDeviceId: device.deviceId,
                    pendingThreadIds: pendingThreadIds
                )
                try await relay.publishThreadDetail(
                    accountId: accountId,
                    macAgentId: macAgentId,
                    threadId: thread.id,
                    deviceId: device.deviceId,
                    sealedDetail: detail
                )
                sealedDetailCount += 1
            }
        }

        return RemoteThreadPublishResult(
            threadCount: snapshot.threads.count,
            sealedDetailCount: sealedDetailCount
        )
    }

    private func activeDevices(at serverTime: Date) throws -> [TrustedDevice] {
        try contentService.trustedStore.list(now: serverTime).trustedDevices
            .filter {
                $0.accountId == accountId
                    && $0.macAgentId == macAgentId
                    && !$0.revoked
                    && $0.validUntil >= serverTime
            }
            .sorted { lhs, rhs in
                lhs.deviceId < rhs.deviceId
            }
    }
}
