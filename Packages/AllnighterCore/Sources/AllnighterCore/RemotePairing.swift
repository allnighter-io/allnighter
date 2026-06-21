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
