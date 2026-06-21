import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModePairingClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_600_000)

    func testClientSubmitsPairingRequestToLoopbackServer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-mode-pairing-client-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionStore = DirectModePairingSessionStore(
            fileURL: root.appendingPathComponent("direct_pairing_sessions.json"),
            idFactory: { "session_1" }
        )
        let trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        try sessionStore.arm(
            payload: RemotePairingPayload(
                endpoints: [
                    RemotePairingEndpoint(url: "http://127.0.0.1:42123", transportMode: .loopback),
                ],
                agentSigningPubkey: "agent_sign",
                agentSealingPubkey: "agent_seal",
                pairingToken: "pair_token_1",
                expiresAt: now.addingTimeInterval(120)
            ),
            manualCode: "123456",
            now: now
        )
        let fixedNow = now
        let pairingHandler = DirectModePairingRequestHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            sessionStore: sessionStore,
            trustedStore: trustedStore,
            now: { fixedNow },
            requestIdFactory: { "pair_request_1" }
        )
        let statusReader = DirectModePairingStatusReader(
            accountId: "acct_1",
            macAgentId: "mac_1",
            trustedStore: trustedStore,
            now: { fixedNow }
        )
        let server = DirectModeCommandServer(
            handler: RecordingPairingClientCommandHandler(),
            pairingHandler: pairingHandler,
            pairingStatusHandler: statusReader
        )
        let port = try server.start()
        defer { server.stop() }
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModePairingClient(endpoint: endpoint)

        let response = try await client.submit(DirectModePairingSubmitRequest(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            pairingToken: "pair_token_1"
        ))

        XCTAssertEqual(response.sessionId, "session_1")
        XCTAssertEqual(response.request.id, "pair_request_1")
        XCTAssertEqual(response.request.deviceId, "device_1")
        XCTAssertEqual(response.request.status, .pending)
        XCTAssertEqual(sessionStore.load().sessions.first?.status, .consumed)
        XCTAssertEqual(trustedStore.load().pendingRequests, [response.request])

        let pending = try await client.status(DirectModePairingStatusRequest(
            requestId: "pair_request_1",
            deviceId: "device_1"
        ))
        XCTAssertEqual(pending.status, .pending)
        XCTAssertNil(pending.trustedDevice)

        _ = try trustedStore.approve(deviceId: "device_1", now: now, validFor: 120)
        let approved = try await client.status(DirectModePairingStatusRequest(
            requestId: "pair_request_1",
            deviceId: "device_1"
        ))
        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(approved.trustedDevice?.deviceId, "device_1")
    }

    func testClientReportsHTTPStatusWhenPairingRouteIsUnavailable() async throws {
        let server = DirectModeCommandServer(handler: RecordingPairingClientCommandHandler())
        let port = try server.start()
        defer { server.stop() }
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModePairingClient(endpoint: endpoint)

        do {
            _ = try await client.submit(DirectModePairingSubmitRequest(
                deviceId: "device_1",
                displayName: "Mike's iPhone",
                deviceSigningPubkey: "device_sign",
                deviceSealingPubkey: "device_seal",
                pairingToken: "pair_token_1"
            ))
            XCTFail("missing pairing handler should surface an HTTP error")
        } catch let error as DirectModePairingClientError {
            XCTAssertEqual(error, .httpStatus(404))
        }

        do {
            _ = try await client.status(DirectModePairingStatusRequest(
                requestId: "pair_request_1",
                deviceId: "device_1"
            ))
            XCTFail("missing pairing status handler should surface an HTTP error")
        } catch let error as DirectModePairingClientError {
            XCTAssertEqual(error, .httpStatus(404))
        }
    }
}

private final class RecordingPairingClientCommandHandler: DirectModeCommandHandling, @unchecked Sendable {
    func handle(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandAckEnvelope {
        throw DirectModeRemoteClientError.unsupportedOperation("command")
    }
}
