import Foundation
import AllnighterCore

public enum DirectModePairingRequestError: Error, Equatable, Sendable {
    case missingCredential
    case multipleCredentials
    case emptyDeviceId
    case emptyDisplayName
    case emptyDeviceSigningKey
    case emptyDeviceSealingKey
}

public protocol DirectModePairingHandling: Sendable {
    func handle(_ request: DirectModePairingSubmitRequest) throws -> DirectModePairingSubmitResponse
}

public struct DirectModePairingRequestHandler: DirectModePairingHandling {
    private let accountId: String
    private let macAgentId: String
    private let sessionStore: DirectModePairingSessionStore
    private let trustedStore: TrustedRemoteStore
    private let now: @Sendable () -> Date
    private let requestIdFactory: @Sendable () -> String

    public init(
        accountId: String,
        macAgentId: String,
        sessionStore: DirectModePairingSessionStore,
        trustedStore: TrustedRemoteStore,
        now: @escaping @Sendable () -> Date = Date.init,
        requestIdFactory: @escaping @Sendable () -> String = {
            "pair_\(UUID().uuidString.lowercased())"
        }
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.sessionStore = sessionStore
        self.trustedStore = trustedStore
        self.now = now
        self.requestIdFactory = requestIdFactory
    }

    public func handle(_ request: DirectModePairingSubmitRequest) throws -> DirectModePairingSubmitResponse {
        let deviceId = request.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceId.isEmpty else { throw DirectModePairingRequestError.emptyDeviceId }
        let displayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { throw DirectModePairingRequestError.emptyDisplayName }
        let signingKey = request.deviceSigningPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signingKey.isEmpty else { throw DirectModePairingRequestError.emptyDeviceSigningKey }
        let sealingKey = request.deviceSealingPubkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sealingKey.isEmpty else { throw DirectModePairingRequestError.emptyDeviceSealingKey }

        let credential = try credential(from: request)
        let acceptedAt = now()
        let session: DirectModePairingSession
        switch credential {
        case .pairingToken(let token):
            session = try sessionStore.consume(pairingToken: token, now: acceptedAt)
        case .manualCode(let code):
            session = try sessionStore.consume(manualCode: code, now: acceptedAt)
        }

        let pairRequest = RemotePairRequest(
            id: requestIdFactory(),
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: signingKey,
            deviceSealingPubkey: sealingKey,
            requestedAt: acceptedAt,
            expiresAt: session.expiresAt
        )
        try trustedStore.upsertPending(pairRequest)
        return DirectModePairingSubmitResponse(
            request: pairRequest,
            sessionId: session.id,
            acceptedAt: acceptedAt
        )
    }

    private enum Credential {
        case pairingToken(String)
        case manualCode(String)
    }

    private func credential(from request: DirectModePairingSubmitRequest) throws -> Credential {
        let token = request.pairingToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = request.manualCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasToken = token?.isEmpty == false
        let hasCode = code?.isEmpty == false

        switch (hasToken, hasCode) {
        case (false, false):
            throw DirectModePairingRequestError.missingCredential
        case (true, true):
            throw DirectModePairingRequestError.multipleCredentials
        case (true, false):
            guard let token else { throw DirectModePairingRequestError.missingCredential }
            return .pairingToken(token)
        case (false, true):
            guard let code else { throw DirectModePairingRequestError.missingCredential }
            return .manualCode(code)
        }
    }
}
