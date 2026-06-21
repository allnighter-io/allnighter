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
    public var publishedTrustedDeviceCount: Int
    public var syncedTrustedDeviceCount: Int
    public var processedCommandCount: Int
    public var publishedEventCount: Int
    public var lastPublishedEventSeq: Int64?
    public var journalLastEventSeq: Int64?
    public var publishedSnapshotRunCount: Int
    public var publishedSnapshotLastSeq: Int64?
    public var acknowledgements: [CommandAck]

    public init(
        mac: MacAgentRef,
        syncedPendingPairRequestCount: Int = 0,
        publishedTrustedDeviceCount: Int = 0,
        syncedTrustedDeviceCount: Int,
        processedCommandCount: Int,
        publishedEventCount: Int = 0,
        lastPublishedEventSeq: Int64? = nil,
        journalLastEventSeq: Int64? = nil,
        publishedSnapshotRunCount: Int = 0,
        publishedSnapshotLastSeq: Int64? = nil,
        acknowledgements: [CommandAck]
    ) {
        self.mac = mac
        self.syncedPendingPairRequestCount = syncedPendingPairRequestCount
        self.publishedTrustedDeviceCount = publishedTrustedDeviceCount
        self.syncedTrustedDeviceCount = syncedTrustedDeviceCount
        self.processedCommandCount = processedCommandCount
        self.publishedEventCount = publishedEventCount
        self.lastPublishedEventSeq = lastPublishedEventSeq
        self.journalLastEventSeq = journalLastEventSeq
        self.publishedSnapshotRunCount = publishedSnapshotRunCount
        self.publishedSnapshotLastSeq = publishedSnapshotLastSeq
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
    private let eventSync: RemoteMacAgentEventSync?
    private let snapshotPublisher: RemoteSnapshotPublisher?
    private let now: @Sendable () -> Date
    private let commandBatchLimit: Int

    public init(
        identity: RemoteMacAgentIdentity,
        relay: RemoteMacRelay,
        trustedStore: TrustedRemoteStore,
        router: RemoteCommandRouting,
        auditRecorder: any RemoteAuditRecording = NoopRemoteAuditRecorder(),
        eventSync: RemoteMacAgentEventSync? = nil,
        snapshotPublisher: RemoteSnapshotPublisher? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        commandBatchLimit: Int = 100
    ) {
        self.identity = identity
        self.relay = relay
        self.trustedStore = trustedStore
        self.router = router
        self.auditRecorder = auditRecorder
        self.eventSync = eventSync
        self.snapshotPublisher = snapshotPublisher
        self.now = now
        self.commandBatchLimit = max(1, commandBatchLimit)
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
        let localRegistryBeforePairImport = trustedStore.list(now: serverTime)
        let locallyTrustedDeviceIds = Set(localRegistryBeforePairImport.trustedDevices.compactMap { device -> String? in
            guard device.accountId == identity.account.accountId,
                  device.macAgentId == identity.macAgentId,
                  !device.revoked,
                  device.validUntil >= serverTime else {
                return nil
            }
            return device.deviceId
        })
        let locallyApprovedPairDeviceIds = Set(localRegistryBeforePairImport.pendingRequests.compactMap { request -> String? in
            guard request.accountId == identity.account.accountId,
                  request.macAgentId == identity.macAgentId,
                  request.status == RemotePairRequestStatus.approved else {
                return nil
            }
            return request.deviceId
        })
        var syncedPendingPairRequestCount = 0
        for request in pendingPairRequests {
            guard request.accountId == identity.account.accountId,
                  request.macAgentId == identity.macAgentId,
                  request.status == RemotePairRequestStatus.pending,
                  request.expiresAt >= serverTime,
                  !locallyTrustedDeviceIds.contains(request.deviceId),
                  !locallyApprovedPairDeviceIds.contains(request.deviceId) else {
                continue
            }
            try trustedStore.upsertPending(request)
            syncedPendingPairRequestCount += 1
        }

        var trustedDevices = try await relay.trustedDevices(
            accountId: identity.account.accountId,
            macAgentId: identity.macAgentId
        )
        let publishedTrustedDeviceCount = try await publishLocalApprovals(
            relayTrustedDevices: trustedDevices,
            serverTime: serverTime
        )
        if publishedTrustedDeviceCount > 0 {
            trustedDevices = try await relay.trustedDevices(
                accountId: identity.account.accountId,
                macAgentId: identity.macAgentId
            )
        }
        try trustedStore.syncTrustedDevices(
            trustedDevices,
            accountId: identity.account.accountId,
            macAgentId: identity.macAgentId,
            now: serverTime
        )

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

        let eventSyncResult = try await eventSync?.publishNewEvents()
        let snapshotPublishResult = try await snapshotPublisher?.publish()

        return RemoteMacAgentDrainResult(
            mac: mac,
            syncedPendingPairRequestCount: syncedPendingPairRequestCount,
            publishedTrustedDeviceCount: publishedTrustedDeviceCount,
            syncedTrustedDeviceCount: trustedDevices.count,
            processedCommandCount: inbox.count,
            publishedEventCount: eventSyncResult?.publishedEventCount ?? 0,
            lastPublishedEventSeq: eventSyncResult?.lastPublishedSeq,
            journalLastEventSeq: eventSyncResult?.journalLastSeq,
            publishedSnapshotRunCount: snapshotPublishResult?.runCount ?? 0,
            publishedSnapshotLastSeq: snapshotPublishResult?.lastSeq,
            acknowledgements: acknowledgements
        )
    }

    private func publishLocalApprovals(
        relayTrustedDevices: [TrustedDevice],
        serverTime: Date
    ) async throws -> Int {
        let registry = trustedStore.list(now: serverTime)
        let relayDevicesById = Dictionary(uniqueKeysWithValues: relayTrustedDevices.map { ($0.deviceId, $0) })
        var publishedCount = 0

        for request in registry.pendingRequests where request.accountId == identity.account.accountId
            && request.macAgentId == identity.macAgentId
            && request.status == RemotePairRequestStatus.approved {
            _ = try await relay.updatePairRequest(request)
        }

        for device in registry.trustedDevices where device.accountId == identity.account.accountId
            && device.macAgentId == identity.macAgentId
            && device.validUntil >= serverTime {
            if relayDevicesById[device.deviceId]?.revoked == true {
                continue
            }
            guard relayDevicesById[device.deviceId] == nil else {
                continue
            }
            try await relay.upsertTrustedDevice(device)
            publishedCount += 1
        }

        return publishedCount
    }
}
