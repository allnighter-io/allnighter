import Foundation
import AllnighterCore

public struct RemoteSnapshotPublishResult: Equatable, Sendable {
    public var runCount: Int
    public var lastSeq: Int64

    public init(runCount: Int, lastSeq: Int64) {
        self.runCount = runCount
        self.lastSeq = lastSeq
    }
}

public struct RemoteSnapshotPublisher: Sendable {
    public let accountId: String
    public let macAgentId: String
    public let service: RemoteSnapshotService
    public let relay: RemoteMacRelay

    public init(
        accountId: String,
        macAgentId: String,
        service: RemoteSnapshotService,
        relay: RemoteMacRelay
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.service = service
        self.relay = relay
    }

    public func publish(since: Int64? = nil) async throws -> RemoteSnapshotPublishResult {
        let snapshot = try service.snapshot(since: since)
        try await relay.publishSnapshot(
            accountId: accountId,
            macAgentId: macAgentId,
            snapshot: snapshot
        )
        return RemoteSnapshotPublishResult(
            runCount: snapshot.runs.count,
            lastSeq: snapshot.lastSeq
        )
    }
}
