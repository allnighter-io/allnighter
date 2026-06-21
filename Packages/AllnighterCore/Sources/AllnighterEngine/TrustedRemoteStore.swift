import Foundation
import AllnighterCore

public enum TrustedRemoteStoreError: Error, Equatable, Sendable {
    case pairRequestNotFound(String)
    case pairRequestExpired(String)
    case trustedDeviceNotFound(String)
}

public final class TrustedRemoteStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? AllnighterPaths.config
            .appendingPathComponent("Remote", isDirectory: true)
            .appendingPathComponent("trusted_remotes.json")
        self.fileManager = fileManager
    }

    public func load() -> TrustedRemoteRegistry {
        guard let data = try? Data(contentsOf: fileURL),
              let registry = try? CoreJSON.decode(TrustedRemoteRegistry.self, from: data) else {
            return TrustedRemoteRegistry()
        }
        return registry
    }

    @discardableResult
    public func save(_ registry: TrustedRemoteRegistry) throws -> URL {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CoreJSON.encode(registry).write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func list(now: Date = Date()) -> TrustedRemoteRegistry {
        var registry = load()
        expirePendingRequests(in: &registry, now: now)
        return registry
    }

    public func syncTrustedDevices(
        _ devices: [TrustedDevice],
        accountId: String,
        macAgentId: String,
        now: Date = Date()
    ) throws {
        var registry = load()
        expirePendingRequests(in: &registry, now: now)
        registry.trustedDevices.removeAll { $0.accountId == accountId && $0.macAgentId == macAgentId }
        registry.trustedDevices.append(contentsOf: devices.filter {
            $0.accountId == accountId && $0.macAgentId == macAgentId
        })
        registry.trustedDevices.sort { lhs, rhs in
            let displayOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if displayOrder == .orderedSame { return lhs.deviceId < rhs.deviceId }
            return displayOrder == .orderedAscending
        }
        try save(registry)
    }

    public func upsertPending(_ request: RemotePairRequest) throws {
        var registry = load()
        registry.pendingRequests.removeAll {
            $0.accountId == request.accountId
                && $0.macAgentId == request.macAgentId
                && $0.deviceId == request.deviceId
        }
        registry.pendingRequests.append(request)
        registry.pendingRequests.sort { lhs, rhs in
            if lhs.requestedAt == rhs.requestedAt { return lhs.deviceId < rhs.deviceId }
            return lhs.requestedAt < rhs.requestedAt
        }
        try save(registry)
    }

    @discardableResult
    public func approve(
        deviceId: String,
        now: Date = Date(),
        validFor: TimeInterval = 365 * 24 * 60 * 60,
        capabilities: Set<RemoteCapability> = Set(RemoteCapability.allCases)
    ) throws -> TrustedDevice {
        var registry = load()
        expirePendingRequests(in: &registry, now: now)
        guard let index = registry.pendingRequests.firstIndex(where: {
            $0.deviceId == deviceId && $0.status == .pending
        }) else {
            if registry.pendingRequests.contains(where: { $0.deviceId == deviceId && $0.status == .expired }) {
                try save(registry)
                throw TrustedRemoteStoreError.pairRequestExpired(deviceId)
            }
            try save(registry)
            throw TrustedRemoteStoreError.pairRequestNotFound(deviceId)
        }
        guard registry.pendingRequests[index].expiresAt >= now else {
            registry.pendingRequests[index].status = .expired
            try save(registry)
            throw TrustedRemoteStoreError.pairRequestExpired(deviceId)
        }

        registry.pendingRequests[index].status = .approved
        registry.pendingRequests[index].approvedAt = now
        let request = registry.pendingRequests[index]
        let device = TrustedDevice(
            deviceId: request.deviceId,
            displayName: request.displayName,
            deviceSigningPubkey: request.deviceSigningPubkey,
            deviceSealingPubkey: request.deviceSealingPubkey,
            accountId: request.accountId,
            macAgentId: request.macAgentId,
            pairedAt: now,
            validUntil: now.addingTimeInterval(validFor),
            revoked: false,
            revokedAt: nil,
            lastSeenAt: nil,
            capabilities: capabilities
        )
        registry.trustedDevices.removeAll {
            $0.deviceId == device.deviceId
                && $0.accountId == device.accountId
                && $0.macAgentId == device.macAgentId
        }
        registry.trustedDevices.append(device)
        registry.trustedDevices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        try save(registry)
        return device
    }

    @discardableResult
    public func revoke(
        deviceId: String,
        macAgentId: String? = nil,
        now: Date = Date()
    ) throws -> TrustedDevice {
        var registry = load()
        guard let index = registry.trustedDevices.firstIndex(where: {
            $0.deviceId == deviceId && (macAgentId == nil || $0.macAgentId == macAgentId)
        }) else {
            throw TrustedRemoteStoreError.trustedDeviceNotFound(deviceId)
        }
        registry.trustedDevices[index].revoked = true
        registry.trustedDevices[index].revokedAt = now
        try save(registry)
        return registry.trustedDevices[index]
    }

    private func expirePendingRequests(in registry: inout TrustedRemoteRegistry, now: Date) {
        for index in registry.pendingRequests.indices
            where registry.pendingRequests[index].status == .pending
                && registry.pendingRequests[index].expiresAt < now {
            registry.pendingRequests[index].status = .expired
        }
    }
}
