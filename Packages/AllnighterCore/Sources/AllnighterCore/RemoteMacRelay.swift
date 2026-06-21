import Foundation

public struct RemoteMacAgentRegistration: Codable, Equatable, Sendable {
    public var accountId: String
    public var macAgentId: String
    public var displayName: String
    public var agentSigningPubkey: String
    public var agentSealingPubkey: String
    public var protocolVersion: Int

    public init(
        accountId: String,
        macAgentId: String,
        displayName: String,
        agentSigningPubkey: String,
        agentSealingPubkey: String,
        protocolVersion: Int = RemoteProtocol.currentMajor
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.displayName = displayName
        self.agentSigningPubkey = agentSigningPubkey
        self.agentSealingPubkey = agentSealingPubkey
        self.protocolVersion = protocolVersion
    }
}

public struct RemoteMacAgentHeartbeat: Codable, Equatable, Sendable {
    public var accountId: String
    public var macAgentId: String
    public var at: Date
    public var protocolVersion: Int

    public init(
        accountId: String,
        macAgentId: String,
        at: Date,
        protocolVersion: Int = RemoteProtocol.currentMajor
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.at = at
        self.protocolVersion = protocolVersion
    }
}

public enum RemoteMacRelayError: Error, Equatable, Sendable {
    case unsupportedProtocolVersion(expected: Int, actual: Int)
}

public enum RemoteCommandInboxStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case acked
}

public struct RemoteCommandInboxEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { requestId }
    public var requestId: String
    public var accountId: String
    public var macAgentId: String
    public var fromDeviceId: String
    public var command: RemoteCommand
    public var createdAt: Date
    public var status: RemoteCommandInboxStatus

    public init(
        requestId: String,
        accountId: String,
        macAgentId: String,
        fromDeviceId: String,
        command: RemoteCommand,
        createdAt: Date,
        status: RemoteCommandInboxStatus = .pending
    ) {
        self.requestId = requestId
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.fromDeviceId = fromDeviceId
        self.command = command
        self.createdAt = createdAt
        self.status = status
    }
}

public struct RemoteCommandAckEnvelope: Codable, Equatable, Sendable {
    public var requestId: String
    public var accountId: String
    public var macAgentId: String
    public var ack: CommandAck
    public var auditEvent: RemoteAuditEvent
    public var createdAt: Date

    public init(
        requestId: String,
        accountId: String,
        macAgentId: String,
        ack: CommandAck,
        auditEvent: RemoteAuditEvent,
        createdAt: Date
    ) {
        self.requestId = requestId
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.ack = ack
        self.auditEvent = auditEvent
        self.createdAt = createdAt
    }
}

public protocol RemoteMacRelay: Sendable {
    func registerMacAgent(_ registration: RemoteMacAgentRegistration) async throws -> MacAgentRef
    func heartbeat(_ heartbeat: RemoteMacAgentHeartbeat) async throws
    func macAgents(accountId: String) async throws -> [MacAgentRef]
    func submitPairRequest(_ request: RemotePairRequestDraft) async throws -> RemotePairRequest
    func pendingPairRequests(accountId: String, macAgentId: String) async throws -> [RemotePairRequest]
    func pairRequestStatus(
        accountId: String,
        macAgentId: String,
        requestId: String,
        deviceId: String,
        checkedAt: Date
    ) async throws -> RemotePairingStatusResponse
    func updatePairRequest(_ request: RemotePairRequest) async throws -> RemotePairRequest
    func trustedDevices(accountId: String, macAgentId: String) async throws -> [TrustedDevice]
    func upsertTrustedDevice(_ device: TrustedDevice) async throws
    func submitCommand(_ entry: RemoteCommandInboxEntry) async throws
    func commandAck(
        accountId: String,
        macAgentId: String,
        requestId: String
    ) async throws -> RemoteCommandAckEnvelope?
    func pendingCommands(accountId: String, macAgentId: String, limit: Int) async throws -> [RemoteCommandInboxEntry]
    func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws
    func runEvents(
        accountId: String,
        macAgentId: String,
        after seq: Int64,
        limit: Int
    ) async throws -> [RemoteRunEventEnvelope]
    func publishEvents(accountId: String, macAgentId: String, events: [RemoteRunEventEnvelope]) async throws
    func publishSnapshot(accountId: String, macAgentId: String, snapshot: SnapshotEnvelope) async throws
    func snapshot(accountId: String, macAgentId: String, since: Int64?) async throws -> SnapshotEnvelope?
    func publishMedia(ref: MediaRef, data: Data, keys: [MediaKeyEnvelope]) async throws
    func upsertMediaKey(_ key: MediaKeyEnvelope, macAgentId: String) async throws
    func mediaData(ref: String, macAgentId: String, at: Date) async throws -> Data?
    func mediaKey(ref: String, macAgentId: String, deviceId: String, at: Date) async throws -> MediaKeyEnvelope?
}

public actor MockRemoteMacRelay: RemoteMacRelay {
    public private(set) var registrations: [RemoteMacAgentRegistration] = []
    public private(set) var heartbeats: [RemoteMacAgentHeartbeat] = []
    public private(set) var acknowledgements: [RemoteCommandAckEnvelope] = []
    public private(set) var publishedEvents: [RemoteRunEventEnvelope] = []
    public private(set) var mediaRefs: [MediaRef] = []
    public private(set) var eventLog: [String] = []

    private var macs: [MacStorageKey: MacAgentRef]
    private var pairRequestsByMac: [String: [RemotePairRequest]]
    private var trustedByMac: [String: [TrustedDevice]]
    private var inboxByMac: [String: [RemoteCommandInboxEntry]]
    private var publishedEventScopes: Set<PublishedEventKey>
    private var snapshotsByScope: [SnapshotStorageKey: SnapshotEnvelope]
    private var mediaRefsById: [MediaStorageKey: MediaRef]
    private var mediaDataByRef: [MediaStorageKey: Data]
    private var mediaKeysByRef: [MediaStorageKey: [String: MediaKeyEnvelope]]
    private let pairRequestIdFactory: @Sendable () -> String

    public init(
        macs: [MacAgentRef] = [],
        macAccountIds: [String: String] = [:],
        pairRequests: [RemotePairRequest] = [],
        trustedDevices: [TrustedDevice] = [],
        inbox: [RemoteCommandInboxEntry] = [],
        pairRequestIdFactory: @escaping @Sendable () -> String = {
            "pair_\(UUID().uuidString.lowercased())"
        }
    ) {
        self.macs = Dictionary(macs.compactMap { mac in
            guard let accountId = macAccountIds[mac.macAgentId] else { return nil }
            return (MacStorageKey(accountId: accountId, macAgentId: mac.macAgentId), mac)
        }, uniquingKeysWith: { _, replacement in replacement })
        self.pairRequestsByMac = Dictionary(grouping: pairRequests, by: \.macAgentId)
        self.trustedByMac = Dictionary(grouping: trustedDevices, by: \.macAgentId)
        self.inboxByMac = Dictionary(grouping: inbox, by: \.macAgentId)
        self.publishedEventScopes = Set()
        self.snapshotsByScope = [:]
        self.mediaRefsById = [:]
        self.mediaDataByRef = [:]
        self.mediaKeysByRef = [:]
        self.pairRequestIdFactory = pairRequestIdFactory
    }

    public func registerMacAgent(_ registration: RemoteMacAgentRegistration) async throws -> MacAgentRef {
        try Self.validateProtocolVersion(registration.protocolVersion)
        eventLog.append("register")
        registrations.append(registration)
        let ref = MacAgentRef(
            macAgentId: registration.macAgentId,
            displayName: registration.displayName,
            agentSigningPubkey: registration.agentSigningPubkey,
            agentSealingPubkey: registration.agentSealingPubkey
        )
        macs[MacStorageKey(accountId: registration.accountId, macAgentId: registration.macAgentId)] = ref
        return ref
    }

    public func heartbeat(_ heartbeat: RemoteMacAgentHeartbeat) async throws {
        try Self.validateProtocolVersion(heartbeat.protocolVersion)
        eventLog.append("heartbeat")
        heartbeats.append(heartbeat)
        let key = MacStorageKey(accountId: heartbeat.accountId, macAgentId: heartbeat.macAgentId)
        guard var ref = macs[key] else { return }
        ref.lastSeenAt = heartbeat.at
        macs[key] = ref
    }

    public func macAgents(accountId: String) async throws -> [MacAgentRef] {
        eventLog.append("macAgents")
        return macs
            .filter { $0.key.accountId == accountId }
            .map(\.value)
            .sorted { lhs, rhs in
                let displayOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if displayOrder == .orderedSame { return lhs.macAgentId < rhs.macAgentId }
                return displayOrder == .orderedAscending
            }
    }

    public func submitPairRequest(_ request: RemotePairRequestDraft) async throws -> RemotePairRequest {
        eventLog.append("submitPairRequest")
        let pairRequest = request.pairRequest(id: pairRequestIdFactory())
        var requests = pairRequestsByMac[pairRequest.macAgentId, default: []]
        requests.removeAll {
            $0.accountId == pairRequest.accountId
                && $0.macAgentId == pairRequest.macAgentId
                && $0.deviceId == pairRequest.deviceId
        }
        requests.append(pairRequest)
        requests.sort {
            if $0.requestedAt == $1.requestedAt { return $0.deviceId < $1.deviceId }
            return $0.requestedAt < $1.requestedAt
        }
        pairRequestsByMac[pairRequest.macAgentId] = requests
        return pairRequest
    }

    public func pendingPairRequests(accountId: String, macAgentId: String) async throws -> [RemotePairRequest] {
        eventLog.append("pendingPairRequests")
        return (pairRequestsByMac[macAgentId] ?? [])
            .filter { $0.accountId == accountId && $0.status == .pending }
            .sorted {
                if $0.requestedAt == $1.requestedAt { return $0.deviceId < $1.deviceId }
                return $0.requestedAt < $1.requestedAt
            }
    }

    public func pairRequestStatus(
        accountId: String,
        macAgentId: String,
        requestId: String,
        deviceId: String,
        checkedAt: Date
    ) async throws -> RemotePairingStatusResponse {
        eventLog.append("pairRequestStatus")
        guard let request = (pairRequestsByMac[macAgentId] ?? [])
            .first(where: {
                $0.accountId == accountId
                    && $0.macAgentId == macAgentId
                    && $0.id == requestId
                    && $0.deviceId == deviceId
            }) else {
            return RemotePairingStatusResponse(
                requestId: requestId,
                deviceId: deviceId,
                status: .notFound,
                checkedAt: checkedAt
            )
        }
        let trustedDevice = (trustedByMac[request.macAgentId] ?? []).first {
            $0.accountId == accountId && $0.macAgentId == macAgentId && $0.deviceId == deviceId
        }
        let status: RemotePairingStatusKind
        var responseRequest = request
        if let trustedDevice, trustedDevice.revoked {
            status = .revoked
        } else if let trustedDevice, trustedDevice.validUntil < checkedAt {
            status = .expired
        } else if trustedDevice != nil {
            status = .approved
        } else {
            status = Self.statusKind(for: request, at: checkedAt)
            if status == .expired, responseRequest.status == .pending {
                responseRequest.status = .expired
            }
        }
        return RemotePairingStatusResponse(
            requestId: requestId,
            deviceId: deviceId,
            status: status,
            pairRequest: responseRequest,
            trustedDevice: trustedDevice,
            checkedAt: checkedAt
        )
    }

    public func updatePairRequest(_ request: RemotePairRequest) async throws -> RemotePairRequest {
        eventLog.append("updatePairRequest")
        var requests = pairRequestsByMac[request.macAgentId, default: []]
        requests.removeAll {
            $0.accountId == request.accountId
                && ($0.id == request.id || ($0.macAgentId == request.macAgentId && $0.deviceId == request.deviceId))
        }
        requests.append(request)
        requests.sort {
            if $0.requestedAt == $1.requestedAt { return $0.deviceId < $1.deviceId }
            return $0.requestedAt < $1.requestedAt
        }
        pairRequestsByMac[request.macAgentId] = requests
        return request
    }

    public func trustedDevices(accountId: String, macAgentId: String) async throws -> [TrustedDevice] {
        eventLog.append("trustedDevices")
        return (trustedByMac[macAgentId] ?? [])
            .filter { $0.accountId == accountId }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func upsertTrustedDevice(_ device: TrustedDevice) async throws {
        eventLog.append("upsertTrustedDevice")
        var devices = trustedByMac[device.macAgentId, default: []]
        devices.removeAll {
            $0.accountId == device.accountId && $0.deviceId == device.deviceId
        }
        devices.append(device)
        devices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        trustedByMac[device.macAgentId] = devices
    }

    public func submitCommand(_ entry: RemoteCommandInboxEntry) async throws {
        eventLog.append("submitCommand")
        var entries = inboxByMac[entry.macAgentId, default: []]
        entries.removeAll {
            $0.accountId == entry.accountId && $0.requestId == entry.requestId
        }
        entries.append(entry)
        entries.sort {
            if $0.createdAt == $1.createdAt { return $0.requestId < $1.requestId }
            return $0.createdAt < $1.createdAt
        }
        inboxByMac[entry.macAgentId] = entries
    }

    public func commandAck(
        accountId: String,
        macAgentId: String,
        requestId: String
    ) async throws -> RemoteCommandAckEnvelope? {
        eventLog.append("commandAck")
        return acknowledgements.last {
            $0.accountId == accountId
                && $0.macAgentId == macAgentId
                && $0.requestId == requestId
        }
    }

    public func pendingCommands(
        accountId: String,
        macAgentId: String,
        limit: Int
    ) async throws -> [RemoteCommandInboxEntry] {
        eventLog.append("pendingCommands")
        return Array((inboxByMac[macAgentId] ?? [])
            .filter { $0.accountId == accountId && $0.status == .pending }
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.requestId < $1.requestId }
                return $0.createdAt < $1.createdAt
            }
            .prefix(max(0, limit)))
    }

    public func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws {
        eventLog.append("acknowledge")
        acknowledgements.append(envelope)
        guard var entries = inboxByMac[envelope.macAgentId],
              let index = entries.firstIndex(where: {
                  $0.accountId == envelope.accountId && $0.requestId == envelope.requestId
              }) else {
            return
        }
        entries[index].status = .acked
        inboxByMac[envelope.macAgentId] = entries
    }

    public func runEvents(
        accountId: String,
        macAgentId: String,
        after seq: Int64,
        limit: Int
    ) async throws -> [RemoteRunEventEnvelope] {
        eventLog.append("runEvents")
        guard limit > 0 else { return [] }
        return Array(publishedEvents
            .filter { envelope in
                let key = PublishedEventKey(
                    accountId: accountId,
                    macAgentId: macAgentId,
                    eventId: envelope.event.id,
                    seq: envelope.event.seq
                )
                return publishedEventScopes.contains(key)
                    && envelope.macAgentId == macAgentId
                    && envelope.event.seq > seq
            }
            .sorted { lhs, rhs in
                if lhs.event.seq == rhs.event.seq { return lhs.event.id < rhs.event.id }
                return lhs.event.seq < rhs.event.seq
            }
            .prefix(limit))
    }

    public func publishEvents(
        accountId: String,
        macAgentId: String,
        events: [RemoteRunEventEnvelope]
    ) async throws {
        eventLog.append("publishEvents")
        for event in events {
            publishedEventScopes.insert(PublishedEventKey(
                accountId: accountId,
                macAgentId: macAgentId,
                eventId: event.event.id,
                seq: event.event.seq
            ))
        }
        publishedEvents.append(contentsOf: events)
    }

    public func publishSnapshot(
        accountId: String,
        macAgentId: String,
        snapshot: SnapshotEnvelope
    ) async throws {
        eventLog.append("publishSnapshot")
        snapshotsByScope[SnapshotStorageKey(accountId: accountId, macAgentId: macAgentId)] = snapshot
    }

    public func snapshot(
        accountId: String,
        macAgentId: String,
        since _: Int64?
    ) async throws -> SnapshotEnvelope? {
        eventLog.append("snapshot")
        return snapshotsByScope[SnapshotStorageKey(accountId: accountId, macAgentId: macAgentId)]
    }

    public func publishMedia(ref: MediaRef, data: Data, keys: [MediaKeyEnvelope]) async throws {
        eventLog.append("publishMedia")
        let key = MediaStorageKey(macAgentId: ref.macAgentId, ref: ref.ref)
        mediaRefs.removeAll { $0.macAgentId == ref.macAgentId && $0.ref == ref.ref }
        mediaRefs.append(ref)
        mediaRefs.sort { $0.ref < $1.ref }
        mediaRefsById[key] = ref
        mediaDataByRef[key] = data
        mediaKeysByRef[key] = Dictionary(keys.map { ($0.deviceId, $0) }, uniquingKeysWith: { _, replacement in
            replacement
        })
    }

    public func upsertMediaKey(_ key: MediaKeyEnvelope, macAgentId: String) async throws {
        eventLog.append("upsertMediaKey")
        mediaKeysByRef[MediaStorageKey(macAgentId: macAgentId, ref: key.ref), default: [:]][key.deviceId] = key
    }

    public func mediaData(ref: String, macAgentId: String, at now: Date) async throws -> Data? {
        eventLog.append("mediaData")
        let key = MediaStorageKey(macAgentId: macAgentId, ref: ref)
        guard let mediaRef = mediaRefsById[key],
              mediaRef.macAgentId == macAgentId,
              mediaRef.expiresAt >= now else {
            return nil
        }
        return mediaDataByRef[key]
    }

    public func mediaKey(ref: String, macAgentId: String, deviceId: String, at now: Date) async throws -> MediaKeyEnvelope? {
        eventLog.append("mediaKey")
        let key = MediaStorageKey(macAgentId: macAgentId, ref: ref)
        guard let mediaRef = mediaRefsById[key],
              mediaRef.expiresAt >= now else {
            return nil
        }
        return mediaKeysByRef[key]?[deviceId]
    }

    public func setTrustedDevices(_ devices: [TrustedDevice], macAgentId: String) {
        trustedByMac[macAgentId] = devices
    }

    public func setPairRequests(_ requests: [RemotePairRequest], macAgentId: String) {
        pairRequestsByMac[macAgentId] = requests
    }

    public func enqueue(_ entry: RemoteCommandInboxEntry) {
        inboxByMac[entry.macAgentId, default: []].append(entry)
    }

    private static func statusKind(
        for request: RemotePairRequest,
        at now: Date
    ) -> RemotePairingStatusKind {
        switch request.status {
        case .pending:
            return request.isPending(at: now) ? .pending : .expired
        case .approved:
            return .approved
        case .rejected:
            return .rejected
        case .expired:
            return .expired
        }
    }

    private static func validateProtocolVersion(_ protocolVersion: Int) throws {
        guard protocolVersion == RemoteProtocol.currentMajor else {
            throw RemoteMacRelayError.unsupportedProtocolVersion(
                expected: RemoteProtocol.currentMajor,
                actual: protocolVersion
            )
        }
    }

    private struct SnapshotStorageKey: Hashable, Sendable {
        var accountId: String
        var macAgentId: String
    }

    private struct MacStorageKey: Hashable, Sendable {
        var accountId: String
        var macAgentId: String
    }

    private struct PublishedEventKey: Hashable, Sendable {
        var accountId: String
        var macAgentId: String
        var eventId: String
        var seq: Int64
    }

    private struct MediaStorageKey: Hashable, Sendable {
        var macAgentId: String
        var ref: String
    }
}
