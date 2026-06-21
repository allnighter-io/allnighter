import Foundation

public struct RemoteAccountSession: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, Sendable, CaseIterable {
        case apple
        case google
        case local
    }

    public var accountId: String
    public var provider: Provider
    public var displayName: String?

    public init(accountId: String, provider: Provider, displayName: String? = nil) {
        self.accountId = accountId
        self.provider = provider
        self.displayName = displayName
    }
}

public protocol RemoteClient: Sendable {
    func connect(account: RemoteAccountSession, mode: ConnectionMode) async throws
    func macs() async throws -> [MacAgentRef]
    func snapshot(macId: String, since: Int64?) async throws -> SnapshotEnvelope
    func stream(macId: String, since: Int64) async -> AsyncStream<RemoteRunEventEnvelope>
    func send(_ command: RemoteCommand) async throws -> CommandAck
    func fetchSealed(_ ref: MediaRef) async throws -> Data
    func fetchMediaKey(_ ref: MediaRef, deviceId: String) async throws -> MediaKeyEnvelope
    func diagnose() async -> ConnectionDiagnosis
}

public struct RemoteRunViewState: Codable, Equatable, Sendable {
    public var runs: [TeamRunLight]
    public var lastSeq: Int64
    public var appliedEventIds: Set<String>
    public var recentEvents: [RemoteRunEventEnvelope]
    public var protocolVersion: Int
    public var serverTime: Date

    public init(
        runs: [TeamRunLight],
        lastSeq: Int64,
        appliedEventIds: Set<String> = [],
        recentEvents: [RemoteRunEventEnvelope] = [],
        protocolVersion: Int = RemoteProtocol.currentMajor,
        serverTime: Date
    ) {
        self.runs = runs
        self.lastSeq = lastSeq
        self.appliedEventIds = appliedEventIds
        self.recentEvents = recentEvents
        self.protocolVersion = protocolVersion
        self.serverTime = serverTime
    }

    public init(snapshot: SnapshotEnvelope) {
        self.init(
            runs: snapshot.runs,
            lastSeq: snapshot.lastSeq,
            protocolVersion: snapshot.protocolVersion,
            serverTime: snapshot.serverTime
        )
    }

    public func run(id: String) -> TeamRunLight? {
        runs.first { $0.id == id }
    }
}

public enum RemoteRunReducer {
    public static func apply(
        snapshot: SnapshotEnvelope,
        events: [RemoteRunEventEnvelope] = []
    ) -> RemoteRunViewState {
        var state = RemoteRunViewState(snapshot: snapshot)
        apply(events, to: &state)
        return state
    }

    public static func apply(_ events: [RemoteRunEventEnvelope], to state: inout RemoteRunViewState) {
        for envelope in events.sorted(by: { $0.event.seq < $1.event.seq }) {
            apply(envelope, to: &state)
        }
    }

    public static func apply(_ envelope: RemoteRunEventEnvelope, to state: inout RemoteRunViewState) {
        guard envelope.event.seq > state.lastSeq else { return }
        guard !state.appliedEventIds.contains(envelope.event.id) else { return }
        state.appliedEventIds.insert(envelope.event.id)
        state.recentEvents.append(envelope)
        state.lastSeq = max(state.lastSeq, envelope.event.seq)

        guard let runId = envelope.event.payload["runId"]?.stringValue else { return }

        switch envelope.event.kind {
        case RunEventKind.runStatusChanged:
            if let status = statusValue(from: envelope.event.payload["to"])
                ?? statusValue(from: envelope.event.payload["status"]) {
                upsertRun(id: runId, status: status, event: envelope.event, state: &state)
            }
        case "run.started":
            upsertRun(id: runId, status: .running, event: envelope.event, state: &state)
        case "run.completed":
            upsertRun(id: runId, status: .done, event: envelope.event, state: &state)
        case "run.failed":
            upsertRun(id: runId, status: .failed, event: envelope.event, state: &state)
        case "run.cancelled":
            upsertRun(id: runId, status: .cancelled, event: envelope.event, state: &state)
        default:
            return
        }
    }

    private static func upsertRun(
        id: String,
        status: TeamRunJSON.Status,
        event: RunEvent,
        state: inout RemoteRunViewState
    ) {
        if let index = state.runs.firstIndex(where: { $0.id == id }) {
            state.runs[index].status = status
            if status == .done || status == .failed || status == .cancelled || status == .interrupted {
                state.runs[index].completedAt = state.runs[index].completedAt ?? event.ts
            }
            return
        }

        state.runs.append(TeamRunLight(
            id: id,
            status: status,
            origin: originValue(from: event.payload["origin"]) ?? .ios,
            promptExcerpt: event.payload["promptExcerpt"]?.stringValue ?? "",
            teamDisplayName: event.payload["teamDisplayName"]?.stringValue,
            createdAt: event.ts,
            completedAt: status == .done || status == .failed || status == .cancelled || status == .interrupted
                ? event.ts
                : nil
        ))
    }

    private static func statusValue(from value: JSONValue?) -> TeamRunJSON.Status? {
        guard let raw = value?.stringValue else { return nil }
        return TeamRunJSON.Status(rawValue: raw)
    }

    private static func originValue(from value: JSONValue?) -> TeamRunJSON.Origin? {
        guard let raw = value?.stringValue else { return nil }
        return TeamRunJSON.Origin(rawValue: raw)
    }
}

public enum MockRemoteClientError: Error, Equatable {
    case notConnected
    case macNotFound(String)
    case mediaNotFound(String)
    case mediaKeyNotFound(ref: String, deviceId: String)
}

public actor MockiOSClient: RemoteClient {
    private var connectedAccount: RemoteAccountSession?
    private var connectionMode: ConnectionMode?
    private var macRefs: [MacAgentRef]
    private var snapshots: [String: SnapshotEnvelope]
    private var events: [String: [RemoteRunEventEnvelope]]
    private var media: [String: Data]
    private var mediaKeys: [String: [String: MediaKeyEnvelope]]
    private var trustedDevices: [String: TrustedDevice]
    private var seenRequestIds: Set<String>
    private var serverNow: Date
    private var deviceNow: Date

    public init(
        macs: [MacAgentRef],
        snapshots: [String: SnapshotEnvelope] = [:],
        events: [String: [RemoteRunEventEnvelope]] = [:],
        media: [String: Data] = [:],
        mediaKeys: [String: [String: MediaKeyEnvelope]] = [:],
        trustedDevices: [TrustedDevice] = [],
        serverNow: Date = Date(),
        deviceNow: Date? = nil
    ) {
        self.macRefs = macs
        self.snapshots = snapshots
        self.events = events
        self.media = media
        self.mediaKeys = mediaKeys
        self.trustedDevices = Dictionary(uniqueKeysWithValues: trustedDevices.map { ($0.deviceId, $0) })
        self.seenRequestIds = []
        self.serverNow = serverNow
        self.deviceNow = deviceNow ?? serverNow
    }

    public func connect(account: RemoteAccountSession, mode: ConnectionMode) async throws {
        connectedAccount = account
        connectionMode = mode
    }

    public func macs() async throws -> [MacAgentRef] {
        try requireConnected()
        return macRefs
    }

    public func snapshot(macId: String, since: Int64?) async throws -> SnapshotEnvelope {
        try requireConnected()
        guard macRefs.contains(where: { $0.macAgentId == macId }) else {
            throw MockRemoteClientError.macNotFound(macId)
        }
        if let snapshot = snapshots[macId] {
            return snapshot
        }
        return SnapshotEnvelope(runs: [], lastSeq: since ?? 0, serverTime: serverNow)
    }

    public func stream(macId: String, since: Int64) async -> AsyncStream<RemoteRunEventEnvelope> {
        guard let mac = macRefs.first(where: { $0.macAgentId == macId }) else {
            return AsyncStream { $0.finish() }
        }
        let pending = (events[macId] ?? [])
            .filter { $0.event.seq > since }
            .filter {
                (try? RemoteCrypto.verifyRemoteRunEventEnvelope(
                    $0,
                    signingPublicKeyBase64: mac.agentSigningPubkey
                )) == true
            }
            .sorted { $0.event.seq < $1.event.seq }
        return AsyncStream { continuation in
            for event in pending {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    public func send(_ command: RemoteCommand) async throws -> CommandAck {
        try requireConnected()
        guard command.assertion.protocolMajor == RemoteProtocol.currentMajor else {
            return reject(command, reason: .upgradeRequired)
        }
        guard command.requestId == command.assertion.requestId,
              command.kind == command.assertion.kind else {
            return reject(command, reason: .badSignature)
        }
        guard command.carriesRequiredSealedPayload else {
            return reject(command, reason: .invalidPayload)
        }
        guard abs(command.assertion.timestamp.timeIntervalSince(serverNow)) <= 60 else {
            return reject(command, reason: .clockSkew, includeServerTime: true)
        }
        guard !seenRequestIds.contains(command.requestId) else {
            return reject(command, reason: .replayedRequestId, outcome: .duplicate)
        }
        guard try RemoteCrypto.payloadDigest(command.payload) == command.assertion.payloadSHA256 else {
            return reject(command, reason: .badSignature)
        }
        guard let trustedDevice = trustedDevices[command.assertion.deviceId],
              trustedDevice.authorizes(command.kind, at: serverNow) else {
            return reject(command, reason: .unauthorizedKind)
        }
        guard try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: trustedDevice.deviceSigningPubkey
        ) else {
            return reject(command, reason: .badSignature)
        }

        seenRequestIds.insert(command.requestId)
        return CommandAck(
            requestId: command.requestId,
            accepted: true,
            outcome: .accepted,
            serverTime: serverNow,
            signature: "mock-mac-signature"
        )
    }

    public func fetchSealed(_ ref: MediaRef) async throws -> Data {
        try requireConnected()
        guard ref.expiresAt >= serverNow else {
            throw MockRemoteClientError.mediaNotFound(ref.ref)
        }
        guard let data = media[ref.ref] else {
            throw MockRemoteClientError.mediaNotFound(ref.ref)
        }
        return data
    }

    public func fetchMediaKey(_ ref: MediaRef, deviceId: String) async throws -> MediaKeyEnvelope {
        try requireConnected()
        guard ref.expiresAt >= serverNow else {
            throw MockRemoteClientError.mediaKeyNotFound(ref: ref.ref, deviceId: deviceId)
        }
        guard let key = mediaKeys[ref.ref]?[deviceId] else {
            throw MockRemoteClientError.mediaKeyNotFound(ref: ref.ref, deviceId: deviceId)
        }
        return key
    }

    public func diagnose() async -> ConnectionDiagnosis {
        let account = connectedAccount
        let signedIn = account != nil
        let visibleMacs = signedIn ? macRefs : []
        let visibleMacIds = Set(visibleMacs.map(\.macAgentId))
        let reachableMacIds = Set(visibleMacs.compactMap { mac -> String? in
            guard let lastSeenAt = mac.lastSeenAt,
                  serverNow.timeIntervalSince(lastSeenAt) <= 120 else {
                return nil
            }
            return mac.macAgentId
        })
        let clockInSync = signedIn && abs(deviceNow.timeIntervalSince(serverNow)) <= 60
        let clockNextAction: String?
        if clockInSync {
            clockNextAction = nil
        } else if signedIn {
            clockNextAction = "Check your phone clock; it differs from the Mac by more than 60 seconds."
        } else {
            clockNextAction = "Connect once to compare your phone clock with the Mac."
        }
        let approved = trustedDevices.values.contains { device in
            guard let account else { return false }
            return device.accountId == account.accountId
                && visibleMacIds.contains(device.macAgentId)
                && !device.revoked
                && device.validUntil >= serverNow
        }

        return ConnectionDiagnosis(rungs: [
            ConnectionDiagnosis.Rung(
                rung: .signedIn,
                ok: signedIn,
                nextAction: signedIn ? nil : "Sign in with Apple or Google."
            ),
            ConnectionDiagnosis.Rung(
                rung: .providerAccountMatch,
                ok: signedIn,
                nextAction: signedIn ? nil : "Use the same account on your phone and Mac."
            ),
            ConnectionDiagnosis.Rung(
                rung: .macVisible,
                ok: !visibleMacs.isEmpty,
                nextAction: visibleMacs.isEmpty ? "Open Allnighter on your Mac with the same account." : nil
            ),
            ConnectionDiagnosis.Rung(
                rung: .macReachable,
                ok: !reachableMacIds.isEmpty,
                nextAction: reachableMacIds.isEmpty ? "Wake your Mac or start the Allnighter agent." : nil
            ),
            ConnectionDiagnosis.Rung(
                rung: .clockInSync,
                ok: clockInSync,
                nextAction: clockNextAction
            ),
            ConnectionDiagnosis.Rung(
                rung: .deviceApproved,
                ok: approved,
                nextAction: approved ? nil : "Approve this device on your Mac."
            ),
        ])
    }

    public func setSnapshot(_ snapshot: SnapshotEnvelope, macId: String) {
        snapshots[macId] = snapshot
    }

    public func appendEvent(_ envelope: RemoteRunEventEnvelope, macId: String) {
        events[macId, default: []].append(envelope)
    }

    public func setDeviceNow(_ now: Date) {
        deviceNow = now
    }

    public func trustDevice(_ device: TrustedDevice) {
        trustedDevices[device.deviceId] = device
    }

    public func setServerNow(_ date: Date) {
        serverNow = date
    }

    private func requireConnected() throws {
        guard connectedAccount != nil, connectionMode != nil else {
            throw MockRemoteClientError.notConnected
        }
    }

    private func reject(
        _ command: RemoteCommand,
        reason: RemoteCommandRejectReason,
        outcome: RemoteCommandAckOutcome = .rejected,
        includeServerTime: Bool = false
    ) -> CommandAck {
        CommandAck(
            requestId: command.requestId,
            accepted: false,
            reason: reason,
            outcome: outcome,
            serverTime: includeServerTime ? serverNow : nil,
            signature: "mock-mac-signature"
        )
    }
}
