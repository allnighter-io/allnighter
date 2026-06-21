import Foundation
import AllnighterCore

public protocol RemoteCommandRouting: Sendable {
    func route(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandRoutingResult
}

extension RemoteCommandRouter: RemoteCommandRouting {}

public struct RemoteMacAgentIdentity: Equatable, Sendable {
    public var account: RemoteAccountSession
    public var macAgentId: String
    public var displayName: String
    public var agentSigningPubkey: String
    public var agentSealingPubkey: String

    public init(
        account: RemoteAccountSession,
        macAgentId: String,
        displayName: String,
        agentSigningPubkey: String,
        agentSealingPubkey: String
    ) {
        self.account = account
        self.macAgentId = macAgentId
        self.displayName = displayName
        self.agentSigningPubkey = agentSigningPubkey
        self.agentSealingPubkey = agentSealingPubkey
    }

    public var registration: RemoteMacAgentRegistration {
        RemoteMacAgentRegistration(
            accountId: account.accountId,
            macAgentId: macAgentId,
            displayName: displayName,
            agentSigningPubkey: agentSigningPubkey,
            agentSealingPubkey: agentSealingPubkey
        )
    }
}

public struct RemoteMacAgentDrainResult: Equatable, Sendable {
    public var mac: MacAgentRef
    public var syncedPendingPairRequestCount: Int
    public var syncedTrustedDeviceCount: Int
    public var processedCommandCount: Int
    public var acknowledgements: [CommandAck]

    public init(
        mac: MacAgentRef,
        syncedPendingPairRequestCount: Int = 0,
        syncedTrustedDeviceCount: Int,
        processedCommandCount: Int,
        acknowledgements: [CommandAck]
    ) {
        self.mac = mac
        self.syncedPendingPairRequestCount = syncedPendingPairRequestCount
        self.syncedTrustedDeviceCount = syncedTrustedDeviceCount
        self.processedCommandCount = processedCommandCount
        self.acknowledgements = acknowledgements
    }
}

public enum RemoteMacAgentError: Error, Equatable, Sendable {
    case macAgentMismatch(expected: String, actual: String)
    case inboxEntryMismatch(
        requestId: String,
        expectedAccountId: String,
        actualAccountId: String,
        expectedMacAgentId: String,
        actualMacAgentId: String
    )
}

public final class RemoteMacAgent: @unchecked Sendable {
    private let identity: RemoteMacAgentIdentity
    private let relay: RemoteMacRelay
    private let trustedStore: TrustedRemoteStore
    private let router: RemoteCommandRouting
    private let auditRecorder: any RemoteAuditRecording
    private let now: @Sendable () -> Date
    private let commandBatchLimit: Int

    public init(
        identity: RemoteMacAgentIdentity,
        relay: RemoteMacRelay,
        trustedStore: TrustedRemoteStore,
        router: RemoteCommandRouting,
        auditRecorder: any RemoteAuditRecording = NoopRemoteAuditRecorder(),
        now: @escaping @Sendable () -> Date = Date.init,
        commandBatchLimit: Int = 100
    ) {
        self.identity = identity
        self.relay = relay
        self.trustedStore = trustedStore
        self.router = router
        self.auditRecorder = auditRecorder
        self.now = now
        self.commandBatchLimit = commandBatchLimit
    }

    public func drainOnce() async throws -> RemoteMacAgentDrainResult {
        let serverTime = now()
        let mac = try await relay.registerMacAgent(identity.registration)
        guard mac.macAgentId == identity.macAgentId else {
            throw RemoteMacAgentError.macAgentMismatch(expected: identity.macAgentId, actual: mac.macAgentId)
        }
        try await relay.heartbeat(RemoteMacAgentHeartbeat(
            accountId: identity.account.accountId,
            macAgentId: identity.macAgentId,
            at: serverTime
        ))

        let pendingPairRequests = try await relay.pendingPairRequests(
            accountId: identity.account.accountId,
            macAgentId: identity.macAgentId
        )
        var syncedPendingPairRequestCount = 0
        for request in pendingPairRequests {
            guard request.accountId == identity.account.accountId,
                  request.macAgentId == identity.macAgentId,
                  request.status == RemotePairRequestStatus.pending,
                  request.expiresAt >= serverTime else {
                continue
            }
            try trustedStore.upsertPending(request)
            syncedPendingPairRequestCount += 1
        }

        let trustedDevices = try await relay.trustedDevices(
            accountId: identity.account.accountId,
            macAgentId: identity.macAgentId
        )
        try trustedStore.syncTrustedDevices(trustedDevices, macAgentId: identity.macAgentId, now: serverTime)

        let inbox = try await relay.pendingCommands(
            accountId: identity.account.accountId,
            macAgentId: identity.macAgentId,
            limit: commandBatchLimit
        )
        var acknowledgements: [CommandAck] = []
        for entry in inbox {
            guard entry.accountId == identity.account.accountId,
                  entry.macAgentId == identity.macAgentId else {
                throw RemoteMacAgentError.inboxEntryMismatch(
                    requestId: entry.requestId,
                    expectedAccountId: identity.account.accountId,
                    actualAccountId: entry.accountId,
                    expectedMacAgentId: identity.macAgentId,
                    actualMacAgentId: entry.macAgentId
                )
            }
            let result = try await router.route(entry)
            let envelope = RemoteCommandAckEnvelope(
                requestId: entry.requestId,
                accountId: entry.accountId,
                macAgentId: entry.macAgentId,
                ack: result.ack,
                auditEvent: result.auditEvent,
                createdAt: now()
            )
            try auditRecorder.record(envelope)
            try await relay.acknowledge(envelope)
            acknowledgements.append(result.ack)
        }

        return RemoteMacAgentDrainResult(
            mac: mac,
            syncedPendingPairRequestCount: syncedPendingPairRequestCount,
            syncedTrustedDeviceCount: trustedDevices.count,
            processedCommandCount: inbox.count,
            acknowledgements: acknowledgements
        )
    }
}
