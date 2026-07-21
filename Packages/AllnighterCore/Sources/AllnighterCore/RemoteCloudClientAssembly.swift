#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

public enum RemoteCloudClientAssemblyError: Error, Equatable, Sendable {
    case missingDeviceAccessToken
    case missingAccountId
    case macNotSelected
    case pairingTimedOut
    case pairingRejected
}

public enum RemoteCloudPairingPhase: Equatable, Sendable {
    case checkingTrust
    case requestingPairing
    case awaitingApproval(macDisplayName: String)
    case approved
}

public struct RemoteCloudPairingOptions: Sendable {
    public var pollInterval: TimeInterval
    public var maxPollAttempts: Int
    public var requestTTL: TimeInterval

    public init(
        pollInterval: TimeInterval = 2,
        maxPollAttempts: Int = 150,
        requestTTL: TimeInterval = 5 * 60
    ) {
        self.pollInterval = pollInterval
        self.maxPollAttempts = maxPollAttempts
        self.requestTTL = requestTTL
    }
}

/// Builds a live cloud `RemoteClient` for the iOS companion from relay settings.
public enum RemoteCloudClientAssembly {
    public struct ConnectedClient: Sendable {
        public var client: CloudRemoteClient
        public var mac: MacAgentRef
        public var account: RemoteAccountSession
        public var deviceCredentials: RemoteDeviceCredentials
        public var deviceSigningKey: Curve25519.Signing.PrivateKey
        public var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey

        public init(
            client: CloudRemoteClient,
            mac: MacAgentRef,
            account: RemoteAccountSession,
            deviceCredentials: RemoteDeviceCredentials,
            deviceSigningKey: Curve25519.Signing.PrivateKey,
            deviceSealingKey: Curve25519.KeyAgreement.PrivateKey
        ) {
            self.client = client
            self.mac = mac
            self.account = account
            self.deviceCredentials = deviceCredentials
            self.deviceSigningKey = deviceSigningKey
            self.deviceSealingKey = deviceSealingKey
        }
    }

    public static func makeConnectedClient(
        environment: RemoteSupabaseEnvironment,
        deviceDisplayName: String,
        macAgentId: String? = nil,
        credentialStore: RemoteDeviceCredentialStore = RemoteDeviceCredentialStore(),
        pairing: RemoteCloudPairingOptions = RemoteCloudPairingOptions(),
        relay injectedRelay: RemoteMacRelay? = nil,
        onPairingPhase: (@Sendable (RemoteCloudPairingPhase) -> Void)? = nil
    ) async throws -> ConnectedClient {
        guard environment.hasDeviceCredentials else {
            throw RemoteCloudClientAssemblyError.missingDeviceAccessToken
        }
        guard let account = environment.deviceAccountSession() else {
            throw RemoteCloudClientAssemblyError.missingAccountId
        }
        guard let accessToken = environment.deviceAccessTokenValue() else {
            throw RemoteCloudClientAssemblyError.missingDeviceAccessToken
        }

        let relay: RemoteMacRelay
        if let injectedRelay {
            relay = injectedRelay
        } else {
            relay = try SupabaseRemoteMacRelay(
                supabaseURL: environment.supabaseURL,
                publishableKey: environment.publishableKey,
                tokenProvider: StaticSupabaseAccessTokenProvider(token: accessToken)
            )
        }

        let deviceMaterial = try credentialStore.loadOrCreate(displayName: deviceDisplayName)
        let macs = try await relay.macAgents(accountId: account.accountId)
        let selectedMacId = macAgentId ?? environment.macAgentId
        guard let mac = selectMac(from: macs, preferredId: selectedMacId) else {
            throw RemoteCloudClientAssemblyError.macNotSelected
        }

        onPairingPhase?(.checkingTrust)
        try await ensureDeviceTrusted(
            relay: relay,
            account: account,
            mac: mac,
            device: deviceMaterial.credentials,
            pairing: pairing,
            onPairingPhase: onPairingPhase
        )

        let client = CloudRemoteClient(mac: mac, relay: relay)
        try await client.connect(account: account, mode: .cloudRelay)

        return ConnectedClient(
            client: client,
            mac: mac,
            account: account,
            deviceCredentials: deviceMaterial.credentials,
            deviceSigningKey: deviceMaterial.signingKey,
            deviceSealingKey: deviceMaterial.sealingKey
        )
    }

    private static func ensureDeviceTrusted(
        relay: RemoteMacRelay,
        account: RemoteAccountSession,
        mac: MacAgentRef,
        device: RemoteDeviceCredentials,
        pairing: RemoteCloudPairingOptions,
        onPairingPhase: (@Sendable (RemoteCloudPairingPhase) -> Void)?
    ) async throws {
        let checkedAt = Date()
        let trustedDevices = try await relay.trustedDevices(
            accountId: account.accountId,
            macAgentId: mac.macAgentId
        )
        if isActiveTrustedDevice(trustedDevices, deviceId: device.deviceId, at: checkedAt) {
            onPairingPhase?(.approved)
            return
        }

        onPairingPhase?(.requestingPairing)
        let pairingClient = CloudPairingClient(
            relay: relay,
            defaultTTL: pairing.requestTTL
        )
        try await pairingClient.connect(account: account, mode: .cloudRelay)

        let identity = try device.pairingIdentity
        let request = try await pairingClient.requestPairing(mac: mac, device: identity)
        onPairingPhase?(.awaitingApproval(macDisplayName: mac.displayName))

        for attempt in 0..<max(1, pairing.maxPollAttempts) {
            let status = try await pairingClient.status(
                mac: mac,
                requestId: request.id,
                deviceId: device.deviceId
            )
            switch status.status {
            case .approved:
                onPairingPhase?(.approved)
                return
            case .rejected, .revoked:
                throw RemoteCloudClientAssemblyError.pairingRejected
            case .expired, .notFound:
                throw RemoteCloudClientAssemblyError.pairingTimedOut
            case .pending:
                break
            }
            if attempt < pairing.maxPollAttempts - 1 {
                let nanoseconds = UInt64((max(pairing.pollInterval, 0.25) * 1_000_000_000).rounded())
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        throw RemoteCloudClientAssemblyError.pairingTimedOut
    }

    private static func isActiveTrustedDevice(
        _ devices: [TrustedDevice],
        deviceId: String,
        at now: Date
    ) -> Bool {
        devices.contains { device in
            device.deviceId == deviceId && !device.revoked && device.validUntil >= now
        }
    }

    private static func selectMac(from macs: [MacAgentRef], preferredId: String?) -> MacAgentRef? {
        if let preferredId,
           let match = macs.first(where: { $0.macAgentId == preferredId }) {
            return match
        }
        return macs.first
    }
}
