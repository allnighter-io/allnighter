import Foundation
import AllnighterCore

public protocol CloudRemoteClientSleeping: Sendable {
    func sleep(for interval: TimeInterval) async throws
}

public struct TaskCloudRemoteClientSleeper: CloudRemoteClientSleeping {
    public init() {}

    public func sleep(for interval: TimeInterval) async throws {
        guard interval.isFinite, interval > 0 else { return }
        let nanoseconds = UInt64((min(interval, 60) * 1_000_000_000).rounded())
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

public enum CloudRemoteClientError: Error, Equatable, Sendable {
    case notConnected
    case unsupportedMode(ConnectionMode)
    case macNotFound(String)
    case snapshotNotFound(String)
    case mediaNotFound(String)
    case ackTimedOut(String)
    case badAckEnvelope
    case badAckSignature
    case unsupportedOperation(String)
}

public actor CloudRemoteClient: RemoteClient {
    private let mac: MacAgentRef
    private let relay: RemoteMacRelay
    private let sleeper: any CloudRemoteClientSleeping
    private let now: @Sendable () -> Date
    private let ackPollInterval: TimeInterval
    private let maxAckPollAttempts: Int
    private let streamEventLimit: Int
    private var connectedAccount: RemoteAccountSession?
    private var lastVerifiedAck = false

    public init(
        mac: MacAgentRef,
        relay: RemoteMacRelay,
        sleeper: any CloudRemoteClientSleeping = TaskCloudRemoteClientSleeper(),
        now: @escaping @Sendable () -> Date = Date.init,
        ackPollInterval: TimeInterval = 0.25,
        maxAckPollAttempts: Int = 40,
        streamEventLimit: Int = 500
    ) {
        self.mac = mac
        self.relay = relay
        self.sleeper = sleeper
        self.now = now
        self.ackPollInterval = ackPollInterval
        self.maxAckPollAttempts = maxAckPollAttempts
        self.streamEventLimit = max(0, streamEventLimit)
    }

    public func connect(account: RemoteAccountSession, mode: ConnectionMode) async throws {
        guard mode == .cloudRelay else {
            throw CloudRemoteClientError.unsupportedMode(mode)
        }
        connectedAccount = account
    }

    public func macs() async throws -> [MacAgentRef] {
        let account = try requireConnected()
        return try await relay.macAgents(accountId: account.accountId)
    }

    public func snapshot(macId: String, since: Int64?) async throws -> SnapshotEnvelope {
        let account = try requireConnected()
        try requireMac(macId)
        guard let snapshot = try await relay.snapshot(
            accountId: account.accountId,
            macAgentId: macId,
            since: since
        ) else {
            throw CloudRemoteClientError.snapshotNotFound(macId)
        }
        return snapshot
    }

    public func stream(macId: String, since: Int64) async -> AsyncStream<RemoteRunEventEnvelope> {
        guard let connectedAccount, macId == mac.macAgentId else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let accountId = connectedAccount.accountId
        let relay = relay
        let mac = mac
        let limit = streamEventLimit
        return AsyncStream { continuation in
            Task {
                defer { continuation.finish() }
                guard limit > 0 else { return }
                let events = (try? await relay.runEvents(
                    accountId: accountId,
                    macAgentId: mac.macAgentId,
                    after: since,
                    limit: limit
                )) ?? []
                for envelope in events where Self.verifies(envelope, mac: mac) {
                    continuation.yield(envelope)
                }
            }
        }
    }

    public func send(_ command: RemoteCommand) async throws -> CommandAck {
        let account = try requireConnected()
        let entry = RemoteCommandInboxEntry(
            requestId: command.requestId,
            accountId: account.accountId,
            macAgentId: mac.macAgentId,
            fromDeviceId: command.assertion.deviceId,
            command: command,
            createdAt: now()
        )
        try await relay.submitCommand(entry)

        for attempt in 0..<max(1, maxAckPollAttempts) {
            if let envelope = try await relay.commandAck(
                accountId: account.accountId,
                macAgentId: mac.macAgentId,
                requestId: command.requestId
            ) {
                return try verifiedAck(from: envelope, account: account, command: command)
            }
            if attempt < maxAckPollAttempts - 1 {
                try await sleeper.sleep(for: ackPollInterval)
            }
        }
        throw CloudRemoteClientError.ackTimedOut(command.requestId)
    }

    public func fetchSealed(_ ref: MediaRef) async throws -> Data {
        _ = try requireConnected()
        guard let data = try await relay.mediaData(
            ref: ref.ref,
            macAgentId: ref.macAgentId,
            at: now()
        ) else {
            throw CloudRemoteClientError.mediaNotFound(ref.ref)
        }
        return data
    }

    public func diagnose() async -> ConnectionDiagnosis {
        guard let connectedAccount else {
            return ConnectionDiagnosis(rungs: [
                ConnectionDiagnosis.Rung(rung: .signedIn, ok: false, nextAction: "Sign in with Apple or Google."),
                ConnectionDiagnosis.Rung(rung: .providerAccountMatch, ok: false, nextAction: "Use the same account on your phone and Mac."),
                ConnectionDiagnosis.Rung(rung: .macVisible, ok: false, nextAction: "Open Allnighter on your Mac with the same account."),
                ConnectionDiagnosis.Rung(rung: .macReachable, ok: false, nextAction: "Wake your Mac or start the Allnighter agent."),
                ConnectionDiagnosis.Rung(rung: .clockInSync, ok: false, nextAction: "Connect once to compare your phone clock with the Mac."),
                ConnectionDiagnosis.Rung(rung: .deviceApproved, ok: false, nextAction: "Approve this device on your Mac."),
            ])
        }

        let visibleMacs = (try? await relay.macAgents(accountId: connectedAccount.accountId)) ?? []
        let visibleMac = visibleMacs.first { $0.macAgentId == mac.macAgentId }
        let macVisible = visibleMac != nil
        let macReachable: Bool
        if let lastSeenAt = visibleMac?.lastSeenAt {
            macReachable = now().timeIntervalSince(lastSeenAt) <= 120
        } else {
            macReachable = lastVerifiedAck
        }

        return ConnectionDiagnosis(rungs: [
            ConnectionDiagnosis.Rung(rung: .signedIn, ok: true, nextAction: nil),
            ConnectionDiagnosis.Rung(rung: .providerAccountMatch, ok: true, nextAction: nil),
            ConnectionDiagnosis.Rung(
                rung: .macVisible,
                ok: macVisible,
                nextAction: macVisible ? nil : "Open Allnighter on your Mac with the same account."
            ),
            ConnectionDiagnosis.Rung(
                rung: .macReachable,
                ok: macReachable,
                nextAction: macReachable ? nil : "Wake your Mac or start the Allnighter agent."
            ),
            ConnectionDiagnosis.Rung(rung: .clockInSync, ok: true, nextAction: nil),
            ConnectionDiagnosis.Rung(
                rung: .deviceApproved,
                ok: lastVerifiedAck,
                nextAction: lastVerifiedAck ? nil : "Approve this device on your Mac."
            ),
        ])
    }

    private func verifiedAck(
        from envelope: RemoteCommandAckEnvelope,
        account: RemoteAccountSession,
        command: RemoteCommand
    ) throws -> CommandAck {
        guard envelope.requestId == command.requestId,
              envelope.accountId == account.accountId,
              envelope.macAgentId == mac.macAgentId,
              envelope.ack.requestId == command.requestId,
              envelope.auditEvent.requestId == command.requestId,
              envelope.auditEvent.commandKind == command.kind else {
            throw CloudRemoteClientError.badAckEnvelope
        }
        guard try RemoteCrypto.verifyCommandAck(
            envelope.ack,
            macAgentId: mac.macAgentId,
            signingPublicKeyBase64: mac.agentSigningPubkey
        ) else {
            throw CloudRemoteClientError.badAckSignature
        }
        lastVerifiedAck = true
        return envelope.ack
    }

    private static func verifies(_ envelope: RemoteRunEventEnvelope, mac: MacAgentRef) -> Bool {
        guard envelope.macAgentId == mac.macAgentId else { return false }
        return ((try? RemoteCrypto.verifyRemoteRunEventEnvelope(
            envelope,
            signingPublicKeyBase64: mac.agentSigningPubkey
        )) == true)
    }

    private func requireConnected() throws -> RemoteAccountSession {
        guard let connectedAccount else {
            throw CloudRemoteClientError.notConnected
        }
        return connectedAccount
    }

    private func requireMac(_ macId: String) throws {
        _ = try requireConnected()
        guard macId == mac.macAgentId else {
            throw CloudRemoteClientError.macNotFound(macId)
        }
    }
}
