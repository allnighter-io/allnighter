import AllnighterCore

public struct NoopPushNotifier: PushNotifier {
    public init() {}

    public func register(device: TrustedDevice, pushToken: String) async throws {}

    public func notify(device: TrustedDevice, doorbell: Doorbell) async throws {}
}
