import CryptoKit
import Foundation
import AllnighterCore

public enum DirectModePairingBeginError: Error, Equatable, Sendable {
    case invalidTTL(TimeInterval)
    case emptyAgentSigningKey
    case emptyAgentSealingKey
    case invalidUniversalLinkBase(String)
}

public struct DirectModePairingBeginRequest: Equatable, Sendable {
    public var exposurePlan: DirectModeExposurePlan
    public var agentSigningPubkey: String
    public var agentSealingPubkey: String
    public var tailnetName: String?
    public var ttlSeconds: TimeInterval
    public var maxFailedAttempts: Int
    public var universalLinkBase: URL?

    public init(
        exposurePlan: DirectModeExposurePlan,
        agentSigningPubkey: String,
        agentSealingPubkey: String,
        tailnetName: String? = nil,
        ttlSeconds: TimeInterval = 5 * 60,
        maxFailedAttempts: Int = 5,
        universalLinkBase: URL? = nil
    ) {
        self.exposurePlan = exposurePlan
        self.agentSigningPubkey = agentSigningPubkey
        self.agentSealingPubkey = agentSealingPubkey
        self.tailnetName = tailnetName
        self.ttlSeconds = ttlSeconds
        self.maxFailedAttempts = maxFailedAttempts
        self.universalLinkBase = universalLinkBase
    }
}

public struct DirectModePairingBeginResult: Equatable, Sendable {
    public var session: DirectModePairingSession
    public var payload: RemotePairingPayload
    public var manualCode: String
    public var pairingLink: String?
    public var serveCommand: [String]
    public var certificateProbeCommand: [String]?

    public init(
        session: DirectModePairingSession,
        payload: RemotePairingPayload,
        manualCode: String,
        pairingLink: String? = nil,
        serveCommand: [String],
        certificateProbeCommand: [String]? = nil
    ) {
        self.session = session
        self.payload = payload
        self.manualCode = manualCode
        self.pairingLink = pairingLink
        self.serveCommand = serveCommand
        self.certificateProbeCommand = certificateProbeCommand
    }

    public func json(contractVersion: String) -> DirectModePairingBeginJSON {
        DirectModePairingBeginJSON(
            contractVersion: contractVersion,
            sessionId: session.id,
            pairingLink: pairingLink,
            manualCode: manualCode,
            payload: payload,
            expiresAt: payload.expiresAt,
            serveCommand: serveCommand,
            certificateProbeCommand: certificateProbeCommand
        )
    }
}

public struct DirectModePairingBeginService: Sendable {
    private let sessionStore: DirectModePairingSessionStore
    private let now: @Sendable () -> Date
    private let tokenFactory: @Sendable () -> String
    private let manualCodeFactory: @Sendable () -> String

    public init(
        sessionStore: DirectModePairingSessionStore,
        now: @escaping @Sendable () -> Date = Date.init,
        tokenFactory: @escaping @Sendable () -> String = DirectModePairingBeginService.randomPairingToken,
        manualCodeFactory: @escaping @Sendable () -> String = DirectModePairingBeginService.randomManualCode
    ) {
        self.sessionStore = sessionStore
        self.now = now
        self.tokenFactory = tokenFactory
        self.manualCodeFactory = manualCodeFactory
    }

    public func begin(_ request: DirectModePairingBeginRequest) throws -> DirectModePairingBeginResult {
        guard request.ttlSeconds.isFinite, request.ttlSeconds > 0 else {
            throw DirectModePairingBeginError.invalidTTL(request.ttlSeconds)
        }
        let signingKey = request.agentSigningPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signingKey.isEmpty else {
            throw DirectModePairingBeginError.emptyAgentSigningKey
        }
        let sealingKey = request.agentSealingPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sealingKey.isEmpty else {
            throw DirectModePairingBeginError.emptyAgentSealingKey
        }

        let currentDate = now()
        let payload = RemotePairingPayload(
            endpoints: [request.exposurePlan.endpoint.pairingEndpoint],
            agentSigningPubkey: signingKey,
            agentSealingPubkey: sealingKey,
            tailnetName: request.tailnetName,
            pairingToken: tokenFactory(),
            expiresAt: currentDate.addingTimeInterval(request.ttlSeconds)
        )
        let manualCode = manualCodeFactory()
        let session = try sessionStore.arm(
            payload: payload,
            manualCode: manualCode,
            now: currentDate,
            maxFailedAttempts: request.maxFailedAttempts
        )
        let link = try request.universalLinkBase.map { try pairingLink(baseURL: $0, payload: payload) }
        return DirectModePairingBeginResult(
            session: session,
            payload: payload,
            manualCode: manualCode,
            pairingLink: link,
            serveCommand: request.exposurePlan.serveCommand,
            certificateProbeCommand: request.exposurePlan.certificateProbeCommand
        )
    }

    public static func randomPairingToken() -> String {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        return base64URL(data)
    }

    public static func randomManualCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private func pairingLink(baseURL: URL, payload: RemotePairingPayload) throws -> String {
        guard baseURL.scheme?.lowercased() == "https" else {
            throw DirectModePairingBeginError.invalidUniversalLinkBase(baseURL.absoluteString)
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DirectModePairingBeginError.invalidUniversalLinkBase(baseURL.absoluteString)
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(
            name: "payload",
            value: Self.base64URL(try CoreJSON.encode(payload))
        ))
        components.queryItems = queryItems
        guard let link = components.string else {
            throw DirectModePairingBeginError.invalidUniversalLinkBase(baseURL.absoluteString)
        }
        return link
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
