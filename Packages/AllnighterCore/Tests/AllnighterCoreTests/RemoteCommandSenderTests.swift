import CryptoKit
import XCTest
@testable import AllnighterCore

final class RemoteCommandSenderTests: XCTestCase {
    private let serverNow = Date(timeIntervalSince1970: 1_750_380_000)

    func testSenderRetriesClockSkewWithReturnedServerTime() async throws {
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
        let dateBox = RemoteCommandSenderDateBox()
        let client = MockiOSClient(
            macs: [],
            trustedDevices: [trustedDevice(signingKey: deviceSigningKey)],
            serverNow: serverNow
        )
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)
        let skewedNow = serverNow.addingTimeInterval(300)

        let result = try await RemoteCommandSender.sendWithClockSkewRetry(
            client: client,
            initialNow: skewedNow
        ) { signingTime in
            dateBox.append(signingTime)
            return try RemoteCommandFactory(
                deviceId: "device_1",
                signingKey: deviceSigningKey,
                now: { signingTime }
            ).stopAll(requestId: "req_stop_all")
        }

        XCTAssertTrue(result.ack.accepted)
        XCTAssertEqual(result.attemptCount, 2)
        XCTAssertEqual(result.correctedClockAt, serverNow)
        XCTAssertEqual(dateBox.values, [skewedNow, serverNow])
    }

    func testSenderDoesNotRetryNonClockSkewRejection() async throws {
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
        let dateBox = RemoteCommandSenderDateBox()
        let client = MockiOSClient(macs: [], trustedDevices: [], serverNow: serverNow)
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let result = try await RemoteCommandSender.sendWithClockSkewRetry(
            client: client,
            initialNow: serverNow
        ) { signingTime in
            dateBox.append(signingTime)
            return try RemoteCommandFactory(
                deviceId: "device_1",
                signingKey: deviceSigningKey,
                now: { signingTime }
            ).stopAll(requestId: "req_stop_all")
        }

        XCTAssertFalse(result.ack.accepted)
        XCTAssertEqual(result.ack.reason, .unauthorizedKind)
        XCTAssertEqual(result.attemptCount, 1)
        XCTAssertNil(result.correctedClockAt)
        XCTAssertEqual(dateBox.values, [serverNow])
    }

    private func trustedDevice(signingKey: Curve25519.Signing.PrivateKey) -> TrustedDevice {
        TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            deviceSealingPubkey: "seal",
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: serverNow.addingTimeInterval(-60),
            validUntil: serverNow.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
    }
}

private final class RemoteCommandSenderDateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Date] = []

    var values: [Date] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: Date) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}
