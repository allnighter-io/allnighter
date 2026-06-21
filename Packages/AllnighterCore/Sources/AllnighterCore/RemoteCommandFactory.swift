import CryptoKit
import Foundation

public enum RemoteCommandFactoryError: Error, Equatable, Sendable {
    case emptyDeviceId
    case emptyRequestId
    case emptyRunId
    case invalidStartRunPayload
}

public struct RemoteCommandFactory {
    private let deviceId: String
    private let signingKey: Curve25519.Signing.PrivateKey
    private let now: @Sendable () -> Date

    public init(
        deviceId: String,
        signingKey: Curve25519.Signing.PrivateKey,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.deviceId = deviceId
        self.signingKey = signingKey
        self.now = now
    }

    public func startRun(
        requestId: String,
        request: AsyncTeamStartRequest,
        mac: MacAgentRef,
        sealedForKeyId: String? = nil
    ) throws -> RemoteCommand {
        try startRun(
            requestId: requestId,
            payload: RemoteStartRunPayload(
                prompt: request.question,
                lane: request.lane?.rawValue,
                teamPresetId: request.teamPresetId,
                effort: request.effort?.rawValue,
                type: request.type,
                context: request.context,
                threadId: request.threadId,
                originConversationId: request.originConversationId,
                originMessageId: request.originMessageId
            ),
            mac: mac,
            sealedForKeyId: sealedForKeyId
        )
    }

    public func startRun(
        requestId: String,
        payload: RemoteStartRunPayload,
        mac: MacAgentRef,
        sealedForKeyId: String? = nil
    ) throws -> RemoteCommand {
        let requestId = try normalizedRequestId(requestId)
        let deviceId = try normalizedDeviceId()
        guard payload.asyncTeamStartRequest(
            originAgent: "ios:\(deviceId)",
            idempotencyKey: "remote:\(requestId)"
        ) != nil else {
            throw RemoteCommandFactoryError.invalidStartRunPayload
        }
        let blob = try RemoteCrypto.seal(
            CoreJSON.encode(payload),
            to: mac.agentSealingPubkey,
            sealedForKeyId: sealedForKeyId ?? mac.macAgentId,
            contentType: "application/json"
        )
        return try command(requestId: requestId, kind: .startRun, payload: .sealed(blob), deviceId: deviceId)
    }

    public func stopRun(
        requestId: String,
        runId: String
    ) throws -> RemoteCommand {
        let runId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runId.isEmpty else { throw RemoteCommandFactoryError.emptyRunId }
        return try command(
            requestId: normalizedRequestId(requestId),
            kind: .stopRun,
            payload: .light(["runId": .string(runId)]),
            deviceId: normalizedDeviceId()
        )
    }

    public func stopAll(requestId: String) throws -> RemoteCommand {
        try command(
            requestId: normalizedRequestId(requestId),
            kind: .stopAll,
            payload: .empty,
            deviceId: normalizedDeviceId()
        )
    }

    private func command(
        requestId: String,
        kind: RemoteCommandKind,
        payload: RemoteCommandPayload,
        deviceId: String
    ) throws -> RemoteCommand {
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: deviceId,
            requestId: requestId,
            timestamp: now(),
            kind: kind,
            payload: payload,
            signingKey: signingKey
        )
        return RemoteCommand(requestId: requestId, kind: kind, payload: payload, assertion: assertion)
    }

    private func normalizedDeviceId() throws -> String {
        let deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceId.isEmpty else { throw RemoteCommandFactoryError.emptyDeviceId }
        return deviceId
    }

    private func normalizedRequestId(_ requestId: String) throws -> String {
        let requestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestId.isEmpty else { throw RemoteCommandFactoryError.emptyRequestId }
        return requestId
    }
}
