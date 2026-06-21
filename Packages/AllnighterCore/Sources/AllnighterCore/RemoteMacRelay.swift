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
    func submitPairRequest(_ request: RemotePairRequestDraft) async throws -> RemotePairRequest
    func pendingPairRequests(accountId: String, macAgentId: String) async throws -> [RemotePairRequest]
    func updatePairRequest(_ request: RemotePairRequest) async throws -> RemotePairRequest
    func trustedDevices(accountId: String, macAgentId: String) async throws -> [TrustedDevice]
    func upsertTrustedDevice(_ device: TrustedDevice) async throws
    func pendingCommands(accountId: String, macAgentId: String, limit: Int) async throws -> [RemoteCommandInboxEntry]
    func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws
    func publishEvents(accountId: String, macAgentId: String, events: [RemoteRunEventEnvelope]) async throws
}

public actor MockRemoteMacRelay: RemoteMacRelay {
    public private(set) var registrations: [RemoteMacAgentRegistration] = []
    public private(set) var heartbeats: [RemoteMacAgentHeartbeat] = []
    public private(set) var acknowledgements: [RemoteCommandAckEnvelope] = []
    public private(set) var publishedEvents: [RemoteRunEventEnvelope] = []
    public private(set) var eventLog: [String] = []

    private var macs: [String: MacAgentRef]
    private var pairRequestsByMac: [String: [RemotePairRequest]]
    private var trustedByMac: [String: [TrustedDevice]]
    private var inboxByMac: [String: [RemoteCommandInboxEntry]]
    private let pairRequestIdFactory: @Sendable () -> String

    public init(
        macs: [MacAgentRef] = [],
        pairRequests: [RemotePairRequest] = [],
        trustedDevices: [TrustedDevice] = [],
        inbox: [RemoteCommandInboxEntry] = [],
        pairRequestIdFactory: @escaping @Sendable () -> String = {
            "pair_\(UUID().uuidString.lowercased())"
        }
    ) {
        self.macs = Dictionary(uniqueKeysWithValues: macs.map { ($0.macAgentId, $0) })
        self.pairRequestsByMac = Dictionary(grouping: pairRequests, by: \.macAgentId)
        self.trustedByMac = Dictionary(grouping: trustedDevices, by: \.macAgentId)
        self.inboxByMac = Dictionary(grouping: inbox, by: \.macAgentId)
        self.pairRequestIdFactory = pairRequestIdFactory
    }

    public func registerMacAgent(_ registration: RemoteMacAgentRegistration) async throws -> MacAgentRef {
        eventLog.append("register")
        registrations.append(registration)
        let ref = MacAgentRef(
            macAgentId: registration.macAgentId,
            displayName: registration.displayName,
            agentSigningPubkey: registration.agentSigningPubkey,
            agentSealingPubkey: registration.agentSealingPubkey
        )
        macs[registration.macAgentId] = ref
        return ref
    }

    public func heartbeat(_ heartbeat: RemoteMacAgentHeartbeat) async throws {
        eventLog.append("heartbeat")
        heartbeats.append(heartbeat)
        guard var ref = macs[heartbeat.macAgentId] else { return }
        ref.lastSeenAt = heartbeat.at
        macs[heartbeat.macAgentId] = ref
    }

    public func submitPairRequest(_ request: RemotePairRequestDraft) async throws -> RemotePairRequest {
        eventLog.append("submitPairRequest")
        let pairRequest = request.pairRequest(id: pairRequestIdFactory())
        var requests = pairRequestsByMac[pairRequest.macAgentId, default: []]
        requests.removeAll {
            $0.macAgentId == pairRequest.macAgentId && $0.deviceId == pairRequest.deviceId
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

    public func updatePairRequest(_ request: RemotePairRequest) async throws -> RemotePairRequest {
        eventLog.append("updatePairRequest")
        var requests = pairRequestsByMac[request.macAgentId, default: []]
        requests.removeAll { $0.id == request.id || ($0.macAgentId == request.macAgentId && $0.deviceId == request.deviceId) }
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
        devices.removeAll { $0.deviceId == device.deviceId }
        devices.append(device)
        devices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        trustedByMac[device.macAgentId] = devices
    }

    public func pendingCommands(
        accountId: String,
        macAgentId: String,
        limit: Int
    ) async throws -> [RemoteCommandInboxEntry] {
        eventLog.append("pendingCommands")
        return Array((inboxByMac[macAgentId] ?? [])
            .filter { $0.accountId == accountId && $0.status == .pending }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(max(0, limit)))
    }

    public func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws {
        eventLog.append("acknowledge")
        acknowledgements.append(envelope)
        guard var entries = inboxByMac[envelope.macAgentId],
              let index = entries.firstIndex(where: { $0.requestId == envelope.requestId }) else {
            return
        }
        entries[index].status = .acked
        inboxByMac[envelope.macAgentId] = entries
    }

    public func publishEvents(
        accountId _: String,
        macAgentId _: String,
        events: [RemoteRunEventEnvelope]
    ) async throws {
        eventLog.append("publishEvents")
        publishedEvents.append(contentsOf: events)
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
}
