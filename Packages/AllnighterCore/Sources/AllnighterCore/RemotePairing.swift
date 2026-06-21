import Foundation

public enum RemotePairRequestStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case approved
    case rejected
    case expired
}

public struct RemotePairRequest: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var accountId: String
    public var macAgentId: String
    public var deviceId: String
    public var displayName: String
    public var deviceSigningPubkey: String
    public var deviceSealingPubkey: String
    public var status: RemotePairRequestStatus
    public var requestedAt: Date
    public var expiresAt: Date
    public var approvedAt: Date?
    public var rejectedAt: Date?

    public init(
        id: String,
        accountId: String,
        macAgentId: String,
        deviceId: String,
        displayName: String,
        deviceSigningPubkey: String,
        deviceSealingPubkey: String,
        status: RemotePairRequestStatus = .pending,
        requestedAt: Date,
        expiresAt: Date,
        approvedAt: Date? = nil,
        rejectedAt: Date? = nil
    ) {
        self.id = id
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.deviceId = deviceId
        self.displayName = displayName
        self.deviceSigningPubkey = deviceSigningPubkey
        self.deviceSealingPubkey = deviceSealingPubkey
        self.status = status
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
        self.approvedAt = approvedAt
        self.rejectedAt = rejectedAt
    }

    public func isPending(at now: Date) -> Bool {
        status == .pending && expiresAt >= now
    }
}

public struct RemotePairingEndpoint: Codable, Equatable, Sendable {
    public var url: String
    public var transportMode: ConnectionMode

    public init(url: String, transportMode: ConnectionMode) {
        self.url = url
        self.transportMode = transportMode
    }
}

public struct RemotePairingPayload: Codable, Equatable, Sendable {
    public var endpoints: [RemotePairingEndpoint]
    public var agentSigningPubkey: String
    public var agentSealingPubkey: String
    public var tailnetName: String?
    public var protocolVersion: Int
    public var pairingToken: String
    public var expiresAt: Date

    public init(
        endpoints: [RemotePairingEndpoint],
        agentSigningPubkey: String,
        agentSealingPubkey: String,
        tailnetName: String? = nil,
        protocolVersion: Int = RemoteProtocol.currentMajor,
        pairingToken: String,
        expiresAt: Date
    ) {
        self.endpoints = endpoints
        self.agentSigningPubkey = agentSigningPubkey
        self.agentSealingPubkey = agentSealingPubkey
        self.tailnetName = tailnetName
        self.protocolVersion = protocolVersion
        self.pairingToken = pairingToken
        self.expiresAt = expiresAt
    }

    public func isExpired(at now: Date) -> Bool {
        expiresAt < now
    }
}

public enum DirectModePairingSessionStatus: String, Codable, Sendable, CaseIterable {
    case armed
    case consumed
    case expired
    case lockedOut
}

public struct DirectModePairingSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var endpoints: [RemotePairingEndpoint]
    public var agentSigningPubkey: String
    public var agentSealingPubkey: String
    public var tailnetName: String?
    public var protocolVersion: Int
    public var pairingTokenSHA256: String
    public var manualCodeSHA256: String?
    public var createdAt: Date
    public var expiresAt: Date
    public var status: DirectModePairingSessionStatus
    public var failedAttempts: Int
    public var maxFailedAttempts: Int
    public var consumedAt: Date?
    public var lockedOutAt: Date?

    public init(
        id: String,
        endpoints: [RemotePairingEndpoint],
        agentSigningPubkey: String,
        agentSealingPubkey: String,
        tailnetName: String? = nil,
        protocolVersion: Int = RemoteProtocol.currentMajor,
        pairingTokenSHA256: String,
        manualCodeSHA256: String? = nil,
        createdAt: Date,
        expiresAt: Date,
        status: DirectModePairingSessionStatus = .armed,
        failedAttempts: Int = 0,
        maxFailedAttempts: Int,
        consumedAt: Date? = nil,
        lockedOutAt: Date? = nil
    ) {
        self.id = id
        self.endpoints = endpoints
        self.agentSigningPubkey = agentSigningPubkey
        self.agentSealingPubkey = agentSealingPubkey
        self.tailnetName = tailnetName
        self.protocolVersion = protocolVersion
        self.pairingTokenSHA256 = pairingTokenSHA256
        self.manualCodeSHA256 = manualCodeSHA256
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.failedAttempts = failedAttempts
        self.maxFailedAttempts = maxFailedAttempts
        self.consumedAt = consumedAt
        self.lockedOutAt = lockedOutAt
    }

    public func isExpired(at now: Date) -> Bool {
        expiresAt < now
    }

    public func isArmed(at now: Date) -> Bool {
        status == .armed && !isExpired(at: now)
    }

    public func pairingPayload(pairingToken: String) -> RemotePairingPayload {
        RemotePairingPayload(
            endpoints: endpoints,
            agentSigningPubkey: agentSigningPubkey,
            agentSealingPubkey: agentSealingPubkey,
            tailnetName: tailnetName,
            protocolVersion: protocolVersion,
            pairingToken: pairingToken,
            expiresAt: expiresAt
        )
    }
}

public struct DirectModePairingRegistry: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var sessions: [DirectModePairingSession]

    public init(
        schemaVersion: Int = 1,
        sessions: [DirectModePairingSession] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }
}

public struct DirectModePairingBeginJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var sessionId: String
    public var pairingLink: String?
    public var manualCode: String
    public var payload: RemotePairingPayload
    public var expiresAt: Date
    public var serveCommand: [String]
    public var certificateProbeCommand: [String]?

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        sessionId: String,
        pairingLink: String? = nil,
        manualCode: String,
        payload: RemotePairingPayload,
        expiresAt: Date,
        serveCommand: [String],
        certificateProbeCommand: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.sessionId = sessionId
        self.pairingLink = pairingLink
        self.manualCode = manualCode
        self.payload = payload
        self.expiresAt = expiresAt
        self.serveCommand = serveCommand
        self.certificateProbeCommand = certificateProbeCommand
    }
}

public struct TrustedRemoteRegistry: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var pendingRequests: [RemotePairRequest]
    public var trustedDevices: [TrustedDevice]

    public init(
        schemaVersion: Int = 1,
        pendingRequests: [RemotePairRequest] = [],
        trustedDevices: [TrustedDevice] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pendingRequests = pendingRequests
        self.trustedDevices = trustedDevices
    }
}

public struct TrustedRemoteListJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var pendingRequests: [RemotePairRequest]
    public var trustedDevices: [TrustedDevice]

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        pendingRequests: [RemotePairRequest],
        trustedDevices: [TrustedDevice]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.pendingRequests = pendingRequests
        self.trustedDevices = trustedDevices
    }
}

public struct TrustedRemoteMutationJSON: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var device: TrustedDevice

    public init(schemaVersion: Int = 1, contractVersion: String, device: TrustedDevice) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.device = device
    }
}
