import Foundation
import AllnighterCore

public protocol DirectModePairingStatusHandling: Sendable {
    func status(_ request: DirectModePairingStatusRequest) throws -> DirectModePairingStatusResponse
}

public struct DirectModePairingStatusReader: DirectModePairingStatusHandling {
    private let accountId: String
    private let macAgentId: String
    private let trustedStore: TrustedRemoteStore
    private let now: @Sendable () -> Date

    public init(
        accountId: String,
        macAgentId: String,
        trustedStore: TrustedRemoteStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.trustedStore = trustedStore
        self.now = now
    }

    public func status(_ request: DirectModePairingStatusRequest) throws -> DirectModePairingStatusResponse {
        let checkedAt = now()
        let registry = trustedStore.list(now: checkedAt)
        let device = registry.trustedDevices.first {
            $0.accountId == accountId
                && $0.macAgentId == macAgentId
                && $0.deviceId == request.deviceId
        }
        let pairRequest = registry.pendingRequests.first {
            $0.accountId == accountId
                && $0.macAgentId == macAgentId
                && $0.deviceId == request.deviceId
                && $0.id == request.requestId
        }

        let status: DirectModePairingStatusKind
        if let device, device.revoked {
            status = .revoked
        } else if let device, device.validUntil < checkedAt {
            status = .expired
        } else if device != nil {
            status = .approved
        } else if let pairRequest {
            status = Self.statusKind(for: pairRequest, at: checkedAt)
        } else {
            status = .notFound
        }

        return DirectModePairingStatusResponse(
            requestId: request.requestId,
            deviceId: request.deviceId,
            status: status,
            pairRequest: pairRequest,
            trustedDevice: device,
            checkedAt: checkedAt
        )
    }

    private static func statusKind(
        for request: RemotePairRequest,
        at now: Date
    ) -> DirectModePairingStatusKind {
        switch request.status {
        case .pending:
            return request.isPending(at: now) ? .pending : .expired
        case .approved:
            return .approved
        case .rejected:
            return .rejected
        case .expired:
            return .expired
        }
    }
}
