import CryptoKit
import Foundation
import AllnighterCore

public protocol RemoteTeamCommandExecuting: Sendable {
    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal>
    func stopRun(runId: String) async -> TeamCancelResponse?
    func stopAllRuns() async -> StopAllResult
}

public struct AsyncTeamRemoteCommandExecutor: RemoteTeamCommandExecuting {
    private let service: AsyncTeamService
    private let readyModels: @Sendable () -> [Model]

    public init(
        service: AsyncTeamService,
        readyModels: @escaping @Sendable () -> [Model]
    ) {
        self.service = service
        self.readyModels = readyModels
    }

    public func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        await service.start(request, origin: .ios, readyModels: readyModels())
    }

    public func stopRun(runId: String) async -> TeamCancelResponse? {
        await service.cancel(runId: runId)
    }

    public func stopAllRuns() async -> StopAllResult {
        await service.cancelAll()
    }
}

public struct RemoteCommandRoutingResult: Equatable, Sendable {
    public var ack: CommandAck
    public var auditEvent: RemoteAuditEvent
    public var startResponse: TeamStartResponse?
    public var stopRunResponse: TeamCancelResponse?
    public var stopAllResult: StopAllResult?

    public init(
        ack: CommandAck,
        auditEvent: RemoteAuditEvent,
        startResponse: TeamStartResponse? = nil,
        stopRunResponse: TeamCancelResponse? = nil,
        stopAllResult: StopAllResult? = nil
    ) {
        self.ack = ack
        self.auditEvent = auditEvent
        self.startResponse = startResponse
        self.stopRunResponse = stopRunResponse
        self.stopAllResult = stopAllResult
    }
}

public struct RemoteCommandRouterPolicy: Equatable, Sendable {
    public static let `default` = RemoteCommandRouterPolicy()

    public var maxLightPayloadBytes: Int
    public var maxSealedPayloadBytes: Int
    public var maxCommandsPerDevicePerWindow: Int
    public var rateLimitWindow: TimeInterval

    public init(
        maxLightPayloadBytes: Int = 16 * 1024,
        maxSealedPayloadBytes: Int = 256 * 1024,
        maxCommandsPerDevicePerWindow: Int = 120,
        rateLimitWindow: TimeInterval = 60
    ) {
        self.maxLightPayloadBytes = max(0, maxLightPayloadBytes)
        self.maxSealedPayloadBytes = max(0, maxSealedPayloadBytes)
        self.maxCommandsPerDevicePerWindow = max(1, maxCommandsPerDevicePerWindow)
        if rateLimitWindow.isFinite, rateLimitWindow > 0 {
            self.rateLimitWindow = rateLimitWindow
        } else {
            self.rateLimitWindow = 60
        }
    }
}

public struct RemoteSeenRequest: Codable, Equatable, Sendable {
    public var requestId: String
    public var seenAt: Date
    public var accountId: String
    public var macAgentId: String
    public var deviceId: String

    public init(
        requestId: String,
        seenAt: Date,
        accountId: String,
        macAgentId: String,
        deviceId: String
    ) {
        self.requestId = requestId
        self.seenAt = seenAt
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.deviceId = deviceId
    }
}

public struct RemoteRequestDedupeRegistry: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var requests: [RemoteSeenRequest]

    public init(schemaVersion: Int = currentSchemaVersion, requests: [RemoteSeenRequest] = []) {
        self.schemaVersion = schemaVersion
        self.requests = requests
    }
}

public final class RemoteRequestDedupeStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? AllnighterPaths.config
            .appendingPathComponent("Remote", isDirectory: true)
            .appendingPathComponent("seen_remote_requests.json")
        self.fileManager = fileManager
    }

    public func load() throws -> RemoteRequestDedupeRegistry {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return RemoteRequestDedupeRegistry()
        }
        let data = try Data(contentsOf: fileURL)
        return try CoreJSON.decode(RemoteRequestDedupeRegistry.self, from: data)
    }

    @discardableResult
    public func save(_ registry: RemoteRequestDedupeRegistry) throws -> URL {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CoreJSON.encode(registry).write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func containsOrRecord(
        requestId: String,
        accountId: String,
        macAgentId: String,
        deviceId: String,
        now: Date,
        window: TimeInterval,
        maxEntries: Int = 10_000
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let cutoff = now.addingTimeInterval(-window)
        var registry = try load()
        registry.schemaVersion = RemoteRequestDedupeRegistry.currentSchemaVersion
        registry.requests.removeAll { $0.seenAt < cutoff }
        if registry.requests.contains(where: {
            requestMatches($0, requestId: requestId, accountId: accountId, macAgentId: macAgentId, deviceId: deviceId)
        }) {
            try save(registry)
            return true
        }

        registry.requests.append(RemoteSeenRequest(
            requestId: requestId,
            seenAt: now,
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: deviceId
        ))
        if registry.requests.count > maxEntries {
            registry.requests = Array(registry.requests
                .sorted { $0.seenAt < $1.seenAt }
                .suffix(maxEntries))
        }
        try save(registry)
        return false
    }

    private func requestMatches(
        _ seen: RemoteSeenRequest,
        requestId: String,
        accountId: String,
        macAgentId: String,
        deviceId: String
    ) -> Bool {
        guard seen.requestId == requestId else { return false }
        return seen.accountId == accountId
            && seen.macAgentId == macAgentId
            && seen.deviceId == deviceId
    }
}

private enum RemoteCommandRouterError: Error {
    case invalidLightPayload
}

public final class RemoteCommandRouter: @unchecked Sendable {
    private let accountId: String
    private let macAgentId: String
    private let trustedStore: TrustedRemoteStore
    private let dedupeStore: RemoteRequestDedupeStore
    private let executor: RemoteTeamCommandExecuting
    private let macSigningKey: Curve25519.Signing.PrivateKey
    private let macSealingKey: Curve25519.KeyAgreement.PrivateKey
    private let now: @Sendable () -> Date
    private let skewWindow: TimeInterval
    private let policy: RemoteCommandRouterPolicy
    private let rateLimitLock = NSLock()
    private var rateLimitHitsByDevice: [String: [Date]] = [:]

    public init(
        accountId: String,
        macAgentId: String,
        trustedStore: TrustedRemoteStore,
        dedupeStore: RemoteRequestDedupeStore,
        executor: RemoteTeamCommandExecuting,
        macSigningKey: Curve25519.Signing.PrivateKey,
        macSealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: @escaping @Sendable () -> Date = Date.init,
        skewWindow: TimeInterval = 60,
        policy: RemoteCommandRouterPolicy = .default
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.trustedStore = trustedStore
        self.dedupeStore = dedupeStore
        self.executor = executor
        self.macSigningKey = macSigningKey
        self.macSealingKey = macSealingKey
        self.now = now
        self.skewWindow = skewWindow
        self.policy = policy
    }

    public func route(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandRoutingResult {
        let serverTime = now()
        guard entry.requestId == entry.command.requestId else {
            return try rejected(entry.command, reason: .badSignature, serverTime: serverTime, requestId: entry.requestId)
        }
        guard entry.accountId == accountId,
              entry.macAgentId == macAgentId,
              entry.fromDeviceId == entry.command.assertion.deviceId else {
            return try rejected(entry.command, reason: .badSignature, serverTime: serverTime)
        }
        return try await route(entry.command)
    }

    public func route(_ command: RemoteCommand) async throws -> RemoteCommandRoutingResult {
        let serverTime = now()

        guard command.requestId == command.assertion.requestId,
              command.kind == command.assertion.kind,
              command.assertion.method == RemoteProtocol.commandMethod else {
            return try rejected(command, reason: .badSignature, serverTime: serverTime)
        }
        guard command.assertion.protocolMajor == RemoteProtocol.currentMajor else {
            return try rejected(command, reason: .upgradeRequired, serverTime: serverTime)
        }
        guard command.carriesRequiredSealedPayload else {
            return try rejected(command, reason: .invalidPayload, serverTime: serverTime)
        }
        guard abs(command.assertion.timestamp.timeIntervalSince(serverTime)) <= skewWindow else {
            return try rejected(command, reason: .clockSkew, serverTime: serverTime, includeServerTime: true)
        }
        guard try payloadFitsPolicy(command.payload) else {
            return try rejected(command, reason: .payloadTooLarge, serverTime: serverTime)
        }
        guard try RemoteCrypto.payloadDigest(command.payload) == command.assertion.payloadSHA256 else {
            return try rejected(command, reason: .badSignature, serverTime: serverTime)
        }

        let registry = try trustedStore.list(now: serverTime)
        guard let trustedDevice = registry.trustedDevices.first(where: {
            $0.accountId == accountId
                && $0.deviceId == command.assertion.deviceId
                && $0.macAgentId == macAgentId
        }) else {
            return try rejected(command, reason: .unauthorizedKind, serverTime: serverTime)
        }
        guard !trustedDevice.revoked else {
            return try rejected(command, reason: .revoked, serverTime: serverTime)
        }
        guard trustedDevice.validUntil >= serverTime else {
            return try rejected(command, reason: .expired, serverTime: serverTime)
        }
        guard trustedDevice.authorizes(command.kind, at: serverTime) else {
            return try rejected(command, reason: .unauthorizedKind, serverTime: serverTime)
        }
        guard try RemoteCrypto.verifyDeviceAssertion(
            command.assertion,
            signingPublicKeyBase64: trustedDevice.deviceSigningPubkey
        ) else {
            return try rejected(command, reason: .badSignature, serverTime: serverTime)
        }
        if try dedupeStore.containsOrRecord(
            requestId: command.requestId,
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: trustedDevice.deviceId,
            now: serverTime,
            window: skewWindow
        ) {
            return try rejected(command, reason: .replayedRequestId, outcome: .duplicate, serverTime: serverTime)
        }
        guard recordRateLimitHit(deviceId: trustedDevice.deviceId, at: serverTime) else {
            return try rejected(command, reason: .rateLimited, serverTime: serverTime)
        }

        switch command.kind {
        case .startRun:
            return try await routeStartRun(command, trustedDevice: trustedDevice, serverTime: serverTime)
        case .stopRun:
            return try await routeStopRun(command, serverTime: serverTime)
        case .stopAll:
            return try await routeStopAll(command, serverTime: serverTime)
        }
    }

    private func payloadFitsPolicy(_ payload: RemoteCommandPayload) throws -> Bool {
        switch payload.kind {
        case .empty:
            return true
        case .lightJSON:
            return try CoreJSON.encode(payload).count <= policy.maxLightPayloadBytes
        case .sealedBlob:
            return try CoreJSON.encode(payload).count <= policy.maxSealedPayloadBytes
        }
    }

    private func recordRateLimitHit(deviceId: String, at serverTime: Date) -> Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }

        let cutoff = serverTime.addingTimeInterval(-policy.rateLimitWindow)
        var hits = rateLimitHitsByDevice[deviceId, default: []].filter { $0 >= cutoff }
        guard hits.count < policy.maxCommandsPerDevicePerWindow else {
            rateLimitHitsByDevice[deviceId] = hits
            return false
        }
        hits.append(serverTime)
        rateLimitHitsByDevice[deviceId] = hits
        return true
    }

    private func routeStartRun(
        _ command: RemoteCommand,
        trustedDevice: TrustedDevice,
        serverTime: Date
    ) async throws -> RemoteCommandRoutingResult {
        guard let blob = command.payload.sealedBlob,
              let data = try? RemoteCrypto.open(blob, with: macSealingKey),
              let payload = try? CoreJSON.decode(RemoteStartRunPayload.self, from: data),
              let request = payload.asyncTeamStartRequest(
                originAgent: "ios:\(trustedDevice.deviceId)",
                idempotencyKey: "remote:\(command.requestId)"
              ) else {
            return try rejected(command, reason: .invalidPayload, serverTime: serverTime, targetSummary: "startRun sealed payload")
        }

        switch await executor.startRun(request) {
        case .success(let response):
            return try accepted(
                command,
                serverTime: serverTime,
                targetSummary: "startRun team=\(request.teamPresetId ?? "default")",
                startResponse: response
            )
        case .failure:
            return try rejected(command, reason: .invalidPayload, serverTime: serverTime, targetSummary: "startRun team request")
        }
    }

    private func routeStopRun(
        _ command: RemoteCommand,
        serverTime: Date
    ) async throws -> RemoteCommandRoutingResult {
        guard let payload = try? decodeLightPayload(RemoteStopRunPayload.self, from: command.payload),
              !payload.runId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let response = await executor.stopRun(runId: payload.runId) else {
            return try rejected(command, reason: .invalidPayload, serverTime: serverTime, targetSummary: "stopRun")
        }

        return try accepted(
            command,
            serverTime: serverTime,
            targetSummary: "stopRun runId=\(payload.runId)",
            stopRunResponse: response
        )
    }

    private func routeStopAll(
        _ command: RemoteCommand,
        serverTime: Date
    ) async throws -> RemoteCommandRoutingResult {
        let result = await executor.stopAllRuns()
        return try accepted(
            command,
            serverTime: serverTime,
            targetSummary: "stopAll terminated=\(result.terminated)",
            stopAllResult: result
        )
    }

    private func decodeLightPayload<T: Decodable>(
        _ type: T.Type,
        from payload: RemoteCommandPayload
    ) throws -> T {
        guard payload.kind == .lightJSON, let lightPayload = payload.lightPayload else {
            throw RemoteCommandRouterError.invalidLightPayload
        }
        return try CoreJSON.decode(type, from: CoreJSON.encode(lightPayload))
    }

    private func accepted(
        _ command: RemoteCommand,
        serverTime: Date,
        targetSummary: String,
        startResponse: TeamStartResponse? = nil,
        stopRunResponse: TeamCancelResponse? = nil,
        stopAllResult: StopAllResult? = nil
    ) throws -> RemoteCommandRoutingResult {
        let ack = try signedAck(
            requestId: command.requestId,
            accepted: true,
            outcome: .accepted,
            serverTime: serverTime
        )
        return RemoteCommandRoutingResult(
            ack: ack,
            auditEvent: audit(command, outcome: .accepted, targetSummary: targetSummary, serverTime: serverTime),
            startResponse: startResponse,
            stopRunResponse: stopRunResponse,
            stopAllResult: stopAllResult
        )
    }

    private func rejected(
        _ command: RemoteCommand,
        reason: RemoteCommandRejectReason,
        outcome: RemoteCommandAckOutcome = .rejected,
        serverTime: Date,
        includeServerTime: Bool = false,
        requestId: String? = nil,
        targetSummary: String? = nil
    ) throws -> RemoteCommandRoutingResult {
        let ackRequestId = requestId ?? command.requestId
        let ack = try signedAck(
            requestId: ackRequestId,
            accepted: false,
            reason: reason,
            outcome: outcome,
            serverTime: includeServerTime ? serverTime : nil
        )
        return RemoteCommandRoutingResult(
            ack: ack,
            auditEvent: audit(
                command,
                outcome: outcome,
                requestId: ackRequestId,
                targetSummary: targetSummary ?? "\(command.kind.rawValue) rejected",
                serverTime: serverTime
            )
        )
    }

    private func signedAck(
        requestId: String,
        accepted: Bool,
        reason: RemoteCommandRejectReason? = nil,
        outcome: RemoteCommandAckOutcome,
        serverTime: Date?
    ) throws -> CommandAck {
        try RemoteCrypto.makeCommandAck(
            macAgentId: macAgentId,
            requestId: requestId,
            accepted: accepted,
            reason: reason,
            outcome: outcome,
            serverTime: serverTime,
            signingKey: macSigningKey
        )
    }

    private func audit(
        _ command: RemoteCommand,
        outcome: RemoteCommandAckOutcome,
        requestId: String? = nil,
        targetSummary: String,
        serverTime: Date
    ) -> RemoteAuditEvent {
        RemoteAuditEvent(
            ts: serverTime,
            deviceId: command.assertion.deviceId,
            commandKind: command.kind,
            requestId: requestId ?? command.requestId,
            targetSummary: targetSummary,
            outcome: outcome
        )
    }
}
