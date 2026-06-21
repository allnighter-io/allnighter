import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModePairingRequestHandlerTests: XCTestCase {
    private var root: URL!
    private var sessionStore: DirectModePairingSessionStore!
    private var trustedStore: TrustedRemoteStore!
    private let now = Date(timeIntervalSince1970: 1_750_500_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-mode-pair-request-\(UUID().uuidString)", isDirectory: true)
        sessionStore = DirectModePairingSessionStore(
            fileURL: root.appendingPathComponent("direct_pairing_sessions.json"),
            idFactory: { "session_1" }
        )
        trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testHandlerConsumesTokenAndCreatesPendingPairRequest() throws {
        try arm(pairingToken: "token_ok", manualCode: "123456")
        let handler = makeHandler()

        let response = try handler.handle(submitRequest(pairingToken: "token_ok"))

        XCTAssertEqual(response.sessionId, "session_1")
        XCTAssertEqual(response.acceptedAt, now)
        XCTAssertEqual(response.request.id, "pair_request_1")
        XCTAssertEqual(response.request.accountId, "acct_1")
        XCTAssertEqual(response.request.macAgentId, "mac_1")
        XCTAssertEqual(response.request.deviceId, "device_1")
        XCTAssertEqual(response.request.displayName, "Mike's iPhone")
        XCTAssertEqual(response.request.deviceSigningPubkey, "device_signing_pub")
        XCTAssertEqual(response.request.deviceSealingPubkey, "device_sealing_pub")
        XCTAssertEqual(response.request.status, .pending)
        XCTAssertEqual(response.request.expiresAt, now.addingTimeInterval(120))

        XCTAssertEqual(try sessionStore.load().sessions.first?.status, .consumed)
        XCTAssertEqual(try trustedStore.load().pendingRequests, [response.request])
    }

    func testManualCodeCreatesPendingPairRequest() throws {
        try arm(pairingToken: "token_ok", manualCode: "123456")
        let handler = makeHandler()

        let response = try handler.handle(submitRequest(pairingToken: nil, manualCode: "123 456"))

        XCTAssertEqual(response.sessionId, "session_1")
        XCTAssertEqual(try trustedStore.load().pendingRequests.map(\.deviceId), ["device_1"])
        XCTAssertEqual(try sessionStore.load().sessions.first?.status, .consumed)
    }

    func testWrongTokenLocksOutBeforePendingRequest() throws {
        try arm(pairingToken: "token_ok", manualCode: "123456", maxFailedAttempts: 1)
        let handler = makeHandler()

        XCTAssertThrowsError(try handler.handle(submitRequest(pairingToken: "wrong"))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .invalidPairingToken)
        }
        XCTAssertEqual(try sessionStore.load().sessions.first?.status, .lockedOut)
        XCTAssertTrue(try trustedStore.load().pendingRequests.isEmpty)

        XCTAssertThrowsError(try handler.handle(submitRequest(pairingToken: "token_ok"))) { error in
            XCTAssertEqual(error as? DirectModePairingSessionStoreError, .sessionLockedOut("session_1"))
        }
        XCTAssertTrue(try trustedStore.load().pendingRequests.isEmpty)
    }

    func testSubmitRequiresExactlyOneCredential() throws {
        let handler = makeHandler()

        XCTAssertThrowsError(try handler.handle(submitRequest(pairingToken: nil, manualCode: nil))) { error in
            XCTAssertEqual(error as? DirectModePairingRequestError, .missingCredential)
        }
        XCTAssertThrowsError(try handler.handle(submitRequest(pairingToken: "token_ok", manualCode: "123456"))) { error in
            XCTAssertEqual(error as? DirectModePairingRequestError, .multipleCredentials)
        }
        XCTAssertTrue(try trustedStore.load().pendingRequests.isEmpty)
    }

    func testSubmitRequiresDeviceIdentityFields() throws {
        let handler = makeHandler()

        XCTAssertThrowsError(try handler.handle(submitRequest(deviceId: " ", pairingToken: "token_ok"))) { error in
            XCTAssertEqual(error as? DirectModePairingRequestError, .emptyDeviceId)
        }
        XCTAssertThrowsError(try handler.handle(submitRequest(displayName: " ", pairingToken: "token_ok"))) { error in
            XCTAssertEqual(error as? DirectModePairingRequestError, .emptyDisplayName)
        }
        XCTAssertThrowsError(try handler.handle(submitRequest(deviceSigningPubkey: " ", pairingToken: "token_ok"))) { error in
            XCTAssertEqual(error as? DirectModePairingRequestError, .emptyDeviceSigningKey)
        }
        XCTAssertThrowsError(try handler.handle(submitRequest(deviceSealingPubkey: " ", pairingToken: "token_ok"))) { error in
            XCTAssertEqual(error as? DirectModePairingRequestError, .emptyDeviceSealingKey)
        }
        XCTAssertTrue(try trustedStore.load().pendingRequests.isEmpty)
    }

    private func arm(
        pairingToken: String,
        manualCode: String,
        maxFailedAttempts: Int = 5
    ) throws {
        let payload = RemotePairingPayload(
            endpoints: [
                RemotePairingEndpoint(url: "https://studio.tail123.ts.net", transportMode: .tailscaleDirect),
            ],
            agentSigningPubkey: "agent_signing_pub",
            agentSealingPubkey: "agent_sealing_pub",
            pairingToken: pairingToken,
            expiresAt: now.addingTimeInterval(120)
        )
        try sessionStore.arm(
            payload: payload,
            manualCode: manualCode,
            now: now,
            maxFailedAttempts: maxFailedAttempts
        )
    }

    private func makeHandler() -> DirectModePairingRequestHandler {
        let fixedNow = now
        return DirectModePairingRequestHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            sessionStore: sessionStore,
            trustedStore: trustedStore,
            now: { fixedNow },
            requestIdFactory: { "pair_request_1" }
        )
    }

    private func submitRequest(
        deviceId: String = "device_1",
        displayName: String = "Mike's iPhone",
        deviceSigningPubkey: String = "device_signing_pub",
        deviceSealingPubkey: String = "device_sealing_pub",
        pairingToken: String? = nil,
        manualCode: String? = nil
    ) -> DirectModePairingSubmitRequest {
        DirectModePairingSubmitRequest(
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: deviceSigningPubkey,
            deviceSealingPubkey: deviceSealingPubkey,
            pairingToken: pairingToken,
            manualCode: manualCode
        )
    }
}
