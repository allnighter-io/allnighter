import Foundation
import AllnighterCore

public protocol RemotePendingCommandExecuting: Sendable {
    func cancel(pendingItemId: String) throws
    func edit(
        pendingItemId: String,
        prompt: String?,
        workerToken: String?,
        teamPresetId: String?
    ) throws
    func submit(pendingItemId: String) throws
}

public struct PendingServiceRemoteCommandExecutor: RemotePendingCommandExecuting {
    private let service: PendingService

    public init(service: PendingService) {
        self.service = service
    }

    public func cancel(pendingItemId: String) throws {
        _ = try service.cancel(id: pendingItemId)
    }

    public func edit(
        pendingItemId: String,
        prompt: String?,
        workerToken: String?,
        teamPresetId: String?
    ) throws {
        _ = try service.edit(
            id: pendingItemId,
            .init(prompt: prompt, workerToken: workerToken, teamPresetId: teamPresetId)
        )
    }

    public func submit(pendingItemId: String) throws {
        _ = try service.submit(id: pendingItemId)
    }
}
