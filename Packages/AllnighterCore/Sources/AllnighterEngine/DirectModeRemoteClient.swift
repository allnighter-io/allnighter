import Foundation
import AllnighterCore

public struct DirectModeHTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol DirectModeHTTPPosting: Sendable {
    func postJSON(_ body: Data, to url: URL) async throws -> DirectModeHTTPResponse
}

public struct URLSessionDirectModeHTTPPoster: DirectModeHTTPPosting {
    public init() {}

    public func postJSON(_ body: Data, to url: URL) async throws -> DirectModeHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return DirectModeHTTPResponse(statusCode: statusCode, body: data)
    }
}

public enum DirectModeRemoteClientError: Error, Equatable, Sendable {
    case notConnected
    case unsupportedMode(ConnectionMode)
    case invalidEndpoint(String)
    case macNotFound(String)
    case httpStatus(Int)
    case badAckEnvelope
    case badAckSignature
    case badSnapshotResponse
    case badMediaResponse
    case badMediaKeyResponse
}

public actor DirectModeRemoteClient: RemoteClient {
    private let mac: MacAgentRef
    private let endpoint: DirectModeEndpoint
    private let poster: any DirectModeHTTPPosting
    private let now: @Sendable () -> Date
    private let streamEventLimit: Int
    private var connectedAccount: RemoteAccountSession?
    private var lastVerifiedAck = false
    private var lastDeviceApprovedAck = false

    public init(
        mac: MacAgentRef,
        endpoint: DirectModeEndpoint,
        poster: any DirectModeHTTPPosting = URLSessionDirectModeHTTPPoster(),
        now: @escaping @Sendable () -> Date = Date.init,
        streamEventLimit: Int = 500
    ) {
        self.mac = mac
        self.endpoint = endpoint
        self.poster = poster
        self.now = now
        self.streamEventLimit = max(0, streamEventLimit)
    }

    public func connect(account: RemoteAccountSession, mode: ConnectionMode) async throws {
        guard mode == expectedMode else {
            throw DirectModeRemoteClientError.unsupportedMode(mode)
        }
        connectedAccount = account
    }

    public func macs() async throws -> [MacAgentRef] {
        _ = try requireConnected()
        return [mac]
    }

    public func snapshot(macId: String, since: Int64?) async throws -> SnapshotEnvelope {
        let account = try requireConnected()
        try requireMac(macId)
        let snapshotURL = endpoint.snapshotURL
        guard let url = URL(string: snapshotURL) else {
            throw DirectModeRemoteClientError.invalidEndpoint(snapshotURL)
        }
        let request = DirectModeSnapshotRequest(
            accountId: account.accountId,
            macAgentId: macId,
            since: since
        )
        let response = try await poster.postJSON(CoreJSON.encode(request), to: url)
        guard (200..<300).contains(response.statusCode) else {
            throw DirectModeRemoteClientError.httpStatus(response.statusCode)
        }
        guard let snapshot = try? CoreJSON.decode(SnapshotEnvelope.self, from: response.body) else {
            throw DirectModeRemoteClientError.badSnapshotResponse
        }
        return snapshot
    }

    public func stream(macId: String, since: Int64) async -> AsyncStream<RemoteRunEventEnvelope> {
        guard let connectedAccount, macId == mac.macAgentId, streamEventLimit > 0 else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let endpoint = endpoint
        let poster = poster
        let mac = mac
        let accountId = connectedAccount.accountId
        let limit = streamEventLimit
        return AsyncStream { continuation in
            Task {
                defer { continuation.finish() }
                let eventsURL = endpoint.eventsURL
                guard let url = URL(string: eventsURL) else { return }
                let request = DirectModeEventsRequest(
                    accountId: accountId,
                    macAgentId: macId,
                    afterSeq: since,
                    limit: limit
                )
                guard let body = try? CoreJSON.encode(request),
                      let response = try? await poster.postJSON(body, to: url),
                      (200..<300).contains(response.statusCode),
                      let decoded = try? CoreJSON.decode(DirectModeEventsResponse.self, from: response.body) else {
                    return
                }
                for envelope in decoded.events where envelope.event.seq > since && envelope.isVerified(for: mac) {
                    continuation.yield(envelope)
                }
            }
        }
    }

    public func send(_ command: RemoteCommand) async throws -> CommandAck {
        let account = try requireConnected()
        guard let url = URL(string: endpoint.commandURL) else {
            throw DirectModeRemoteClientError.invalidEndpoint(endpoint.commandURL)
        }

        let entry = RemoteCommandInboxEntry(
            requestId: command.requestId,
            accountId: account.accountId,
            macAgentId: mac.macAgentId,
            fromDeviceId: command.assertion.deviceId,
            command: command,
            createdAt: now()
        )
        let response = try await poster.postJSON(CoreJSON.encode(entry), to: url)
        guard (200..<300).contains(response.statusCode) else {
            throw DirectModeRemoteClientError.httpStatus(response.statusCode)
        }
        let envelope = try CoreJSON.decode(RemoteCommandAckEnvelope.self, from: response.body)
        guard envelope.requestId == command.requestId,
              envelope.accountId == account.accountId,
              envelope.macAgentId == mac.macAgentId,
              envelope.ack.requestId == command.requestId,
              envelope.auditEvent.requestId == command.requestId,
              envelope.auditEvent.deviceId == command.assertion.deviceId,
              envelope.auditEvent.commandKind == command.kind else {
            throw DirectModeRemoteClientError.badAckEnvelope
        }
        guard try RemoteCrypto.verifyCommandAck(
            envelope.ack,
            macAgentId: mac.macAgentId,
            signingPublicKeyBase64: mac.agentSigningPubkey
        ) else {
            throw DirectModeRemoteClientError.badAckSignature
        }
        lastVerifiedAck = true
        lastDeviceApprovedAck = Self.ackProvesDeviceApproved(envelope.ack)
        return envelope.ack
    }

    public func fetchSealed(_ ref: MediaRef) async throws -> Data {
        let account = try requireConnected()
        try requireMac(ref.macAgentId)
        let mediaURL = endpoint.mediaURL
        guard let url = URL(string: mediaURL) else {
            throw DirectModeRemoteClientError.invalidEndpoint(mediaURL)
        }
        let request = DirectModeMediaRequest(
            accountId: account.accountId,
            macAgentId: ref.macAgentId,
            ref: ref.ref,
            checkedAt: now()
        )
        let response = try await poster.postJSON(CoreJSON.encode(request), to: url)
        guard (200..<300).contains(response.statusCode) else {
            throw DirectModeRemoteClientError.httpStatus(response.statusCode)
        }
        guard let decoded = try? CoreJSON.decode(DirectModeMediaResponse.self, from: response.body),
              decoded.ref == ref.ref,
              decoded.macAgentId == ref.macAgentId else {
            throw DirectModeRemoteClientError.badMediaResponse
        }
        return decoded.data
    }

    public func fetchMediaKey(_ ref: MediaRef, deviceId: String) async throws -> MediaKeyEnvelope {
        let account = try requireConnected()
        try requireMac(ref.macAgentId)
        let mediaKeyURL = endpoint.mediaKeyURL
        guard let url = URL(string: mediaKeyURL) else {
            throw DirectModeRemoteClientError.invalidEndpoint(mediaKeyURL)
        }
        let request = DirectModeMediaKeyRequest(
            accountId: account.accountId,
            macAgentId: ref.macAgentId,
            ref: ref.ref,
            deviceId: deviceId,
            checkedAt: now()
        )
        let response = try await poster.postJSON(CoreJSON.encode(request), to: url)
        guard (200..<300).contains(response.statusCode) else {
            throw DirectModeRemoteClientError.httpStatus(response.statusCode)
        }
        guard let decoded = try? CoreJSON.decode(DirectModeMediaKeyResponse.self, from: response.body),
              decoded.key.ref == ref.ref,
              decoded.key.macAgentId == ref.macAgentId,
              decoded.key.deviceId == deviceId else {
            throw DirectModeRemoteClientError.badMediaKeyResponse
        }
        return decoded.key
    }

    public func diagnose() async -> ConnectionDiagnosis {
        let signedIn = connectedAccount != nil
        return ConnectionDiagnosis(rungs: [
            ConnectionDiagnosis.Rung(
                rung: .signedIn,
                ok: signedIn,
                nextAction: signedIn ? nil : "Connect with the same account used to pair this Mac."
            ),
            ConnectionDiagnosis.Rung(
                rung: .providerAccountMatch,
                ok: signedIn,
                nextAction: signedIn ? nil : "Use the same account on your phone and Mac."
            ),
            ConnectionDiagnosis.Rung(
                rung: .macVisible,
                ok: signedIn,
                nextAction: signedIn ? nil : "Open the Direct Mode pairing link again."
            ),
            ConnectionDiagnosis.Rung(
                rung: .macReachable,
                ok: lastVerifiedAck,
                nextAction: lastVerifiedAck ? nil : "Run the Direct Mode readiness check, then send a command."
            ),
            ConnectionDiagnosis.Rung(
                rung: .clockInSync,
                ok: signedIn,
                nextAction: signedIn ? nil : "Connect once to compare your phone clock with the Mac."
            ),
            ConnectionDiagnosis.Rung(
                rung: .deviceApproved,
                ok: lastDeviceApprovedAck,
                nextAction: lastDeviceApprovedAck ? nil : "Approve this device on your Mac."
            ),
        ])
    }

    private var expectedMode: ConnectionMode {
        endpoint.transport == .loopback ? .loopback : .tailscaleDirect
    }

    private static func ackProvesDeviceApproved(_ ack: CommandAck) -> Bool {
        if ack.accepted { return true }
        switch ack.reason {
        case .rateLimited, .replayedRequestId:
            return true
        case .badSignature, .clockSkew, .expired, .invalidPayload, .payloadTooLarge, .revoked, .unauthorizedKind,
             .upgradeRequired, nil:
            return false
        }
    }

    private func requireConnected() throws -> RemoteAccountSession {
        guard let connectedAccount else {
            throw DirectModeRemoteClientError.notConnected
        }
        return connectedAccount
    }

    private func requireMac(_ macId: String) throws {
        _ = try requireConnected()
        guard macId == mac.macAgentId else {
            throw DirectModeRemoteClientError.macNotFound(macId)
        }
    }
}
