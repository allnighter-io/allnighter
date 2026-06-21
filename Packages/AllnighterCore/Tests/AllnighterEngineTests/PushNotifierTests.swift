import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PushNotifierTests: XCTestCase {
    func testNoopNotifierAcceptsRegistrationAndDoorbell() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let notifier = NoopPushNotifier()
        let device = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "signing",
            deviceSealingPubkey: "sealing",
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now,
            validUntil: now.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
        let doorbell = Doorbell(
            title: "Run complete",
            body: "Your Mac has an update.",
            runId: "run_1",
            kind: .runCompleted
        )

        try await notifier.register(device: device, pushToken: "push-token")
        try await notifier.notify(device: device, doorbell: doorbell)
    }
}
