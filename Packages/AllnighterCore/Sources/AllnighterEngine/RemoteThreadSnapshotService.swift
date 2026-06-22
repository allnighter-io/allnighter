import Foundation
import AllnighterCore

public struct RemoteThreadSnapshotPolicy: Equatable, Sendable {
    public var maxThreads: Int
    public var includeArchived: Bool

    public init(maxThreads: Int = 100, includeArchived: Bool = false) {
        self.maxThreads = max(0, maxThreads)
        self.includeArchived = includeArchived
    }
}

public struct RemoteThreadSnapshotService: Sendable {
    public let threadStore: ThreadStore
    public let policy: RemoteThreadSnapshotPolicy
    private let now: @Sendable () -> Date

    public init(
        threadStore: ThreadStore = ThreadStore(),
        policy: RemoteThreadSnapshotPolicy = RemoteThreadSnapshotPolicy(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.threadStore = threadStore
        self.policy = policy
        self.now = now
    }

    public func snapshot(pendingThreadIds: Set<String> = []) -> RemoteThreadSnapshotEnvelope {
        let threads = threadStore.list()
            .filter { policy.includeArchived || !$0.isArchived }
            .prefix(policy.maxThreads)
        return RemoteThreadSnapshotEnvelope(
            threads: RemoteThreadProjection.summaries(
                from: Array(threads),
                pendingThreadIds: pendingThreadIds
            ),
            serverTime: now()
        )
    }
}
