import Foundation
import AllnighterCore

public struct RemoteDeviceRevocationScope: Equatable, Sendable {
    public var accountId: String
    public var macAgentId: String
    public var deviceId: String
    public var revokedAt: Date

    public init(
        accountId: String,
        macAgentId: String,
        deviceId: String,
        revokedAt: Date
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.deviceId = deviceId
        self.revokedAt = revokedAt
    }
}

public struct RemoteDeviceRevocationResult: Equatable, Sendable {
    public var revokedDevice: TrustedDevice
    public var teardownScope: RemoteDeviceRevocationScope

    public init(
        revokedDevice: TrustedDevice,
        teardownScope: RemoteDeviceRevocationScope
    ) {
        self.revokedDevice = revokedDevice
        self.teardownScope = teardownScope
    }
}

public protocol RemoteDeviceRevocationTearingDown: Sendable {
    func tearDown(_ scope: RemoteDeviceRevocationScope) async throws
}

public struct NoopRemoteDeviceRevocationTeardown: RemoteDeviceRevocationTearingDown {
    public init() {}

    public func tearDown(_ scope: RemoteDeviceRevocationScope) async throws {}
}

public final class RemoteDeviceRevocationCoordinator: @unchecked Sendable {
    private let store: TrustedRemoteStore
    private let teardown: any RemoteDeviceRevocationTearingDown
    private let now: @Sendable () -> Date

    public init(
        store: TrustedRemoteStore,
        teardown: any RemoteDeviceRevocationTearingDown = NoopRemoteDeviceRevocationTeardown(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.teardown = teardown
        self.now = now
    }

    public func revoke(
        deviceId: String,
        macAgentId: String
    ) async throws -> RemoteDeviceRevocationResult {
        let revokedAt = now()
        let revokedDevice = try store.revoke(
            deviceId: deviceId,
            macAgentId: macAgentId,
            now: revokedAt
        )
        let scope = RemoteDeviceRevocationScope(
            accountId: revokedDevice.accountId,
            macAgentId: revokedDevice.macAgentId,
            deviceId: revokedDevice.deviceId,
            revokedAt: revokedDevice.revokedAt ?? revokedAt
        )
        try await teardown.tearDown(scope)
        return RemoteDeviceRevocationResult(
            revokedDevice: revokedDevice,
            teardownScope: scope
        )
    }
}
