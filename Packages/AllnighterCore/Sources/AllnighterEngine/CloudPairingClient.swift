import Foundation
import AllnighterCore

public enum CloudPairingClientError: Error, Equatable, Sendable {
    case notConnected
    case unsupportedMode(ConnectionMode)
    case invalidTTL(TimeInterval)
    case emptyRequestId
    case emptyMacAgentId
    case emptyDeviceId
    case emptyDisplayName
    case emptyDeviceSigningKey
    case emptyDeviceSealingKey
}

public actor CloudPairingClient {
    private let relay: RemoteMacRelay
    private let now: @Sendable () -> Date
    private let defaultTTL: TimeInterval
    private var connectedAccount: RemoteAccountSession?

    public init(
        relay: RemoteMacRelay,
        now: @escaping @Sendable () -> Date = Date.init,
        defaultTTL: TimeInterval = 5 * 60
    ) {
        self.relay = relay
        self.now = now
        self.defaultTTL = defaultTTL
    }

    public func connect(account: RemoteAccountSession, mode: ConnectionMode) throws {
        guard mode == .cloudRelay else {
            throw CloudPairingClientError.unsupportedMode(mode)
        }
        connectedAccount = account
    }

    public func macs() async throws -> [MacAgentRef] {
        let account = try requireConnected()
        return try await relay.macAgents(accountId: account.accountId)
    }

    public func requestPairing(
        mac: MacAgentRef,
        device: RemotePairingDeviceIdentity,
        ttl: TimeInterval? = nil
    ) async throws -> RemotePairRequest {
        let account = try requireConnected()
        let ttl = ttl ?? defaultTTL
        guard ttl.isFinite, ttl > 0 else {
            throw CloudPairingClientError.invalidTTL(ttl)
        }
        let macAgentId = mac.macAgentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !macAgentId.isEmpty else { throw CloudPairingClientError.emptyMacAgentId }
        let deviceId = device.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceId.isEmpty else { throw CloudPairingClientError.emptyDeviceId }
        let displayName = device.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { throw CloudPairingClientError.emptyDisplayName }
        let signingKey = device.deviceSigningPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signingKey.isEmpty else { throw CloudPairingClientError.emptyDeviceSigningKey }
        let sealingKey = device.deviceSealingPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sealingKey.isEmpty else { throw CloudPairingClientError.emptyDeviceSealingKey }

        let requestedAt = now()
        return try await relay.submitPairRequest(RemotePairRequestDraft(
            accountId: account.accountId,
            macAgentId: macAgentId,
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: signingKey,
            deviceSealingPubkey: sealingKey,
            requestedAt: requestedAt,
            expiresAt: requestedAt.addingTimeInterval(ttl)
        ))
    }

    public func status(
        requestId: String,
        deviceId: String
    ) async throws -> RemotePairingStatusResponse {
        let account = try requireConnected()
        let requestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else { throw CloudPairingClientError.emptyRequestId }
        let deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceId.isEmpty else { throw CloudPairingClientError.emptyDeviceId }
        return try await relay.pairRequestStatus(
            accountId: account.accountId,
            requestId: requestId,
            deviceId: deviceId,
            checkedAt: now()
        )
    }

    private func requireConnected() throws -> RemoteAccountSession {
        guard let connectedAccount else {
            throw CloudPairingClientError.notConnected
        }
        return connectedAccount
    }
}
