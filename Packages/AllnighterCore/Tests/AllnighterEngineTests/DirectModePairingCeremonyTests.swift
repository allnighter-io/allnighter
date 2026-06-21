import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModePairingCeremonyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_700_000)

    func testDirectModePairingApprovesDeviceBeforeCommandDispatch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("direct-mode-pairing-ceremony-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionStore = DirectModePairingSessionStore(
            fileURL: root.appendingPathComponent("pairing_sessions.json"),
            idFactory: { "pair_session_1" }
        )
        let trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        let dedupeStore = RemoteRequestDedupeStore(fileURL: root.appendingPathComponent("seen_requests.json"))
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let fixedNow = now

        let executor = CeremonyRemoteExecutor()
        await executor.setStopAllResult(StopAllResult(terminated: 2))
        let router = RemoteCommandRouter(
            accountId: "acct_1",
            macAgentId: "mac_1",
            trustedStore: trustedStore,
            dedupeStore: dedupeStore,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: { fixedNow }
        )
        let commandHandler = DirectModeCommandHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            router: router,
            now: { fixedNow }
        )
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
            handler: commandHandler,
            pairingHandler: pairingHandler,
            pairingStatusHandler: statusReader
        )
        let port = try server.start()
        defer { server.stop() }

        let exposurePlan = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
        let beginService = DirectModePairingBeginService(
            sessionStore: sessionStore,
            now: { fixedNow },
            tokenFactory: { "pairing-token-secret" },
            manualCodeFactory: { "123456" }
        )
        let begin = try beginService.begin(DirectModePairingBeginRequest(
            exposurePlan: exposurePlan,
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey),
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey),
            ttlSeconds: 300
        ))
        XCTAssertEqual(begin.payload.endpoints.first?.url, exposurePlan.endpoint.baseURL)
        XCTAssertEqual(sessionStore.load().sessions.first?.status, DirectModePairingSessionStatus.armed)

        let pairingClient = DirectModePairingClient(endpoint: exposurePlan.endpoint)
        let submit = try await pairingClient.submit(DirectModePairingSubmitRequest(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            pairingToken: begin.payload.pairingToken
        ))
        XCTAssertEqual(submit.request.status, RemotePairRequestStatus.pending)
        XCTAssertEqual(sessionStore.load().sessions.first?.status, DirectModePairingSessionStatus.consumed)

        let pending = try await pairingClient.status(DirectModePairingStatusRequest(
            requestId: submit.request.id,
            deviceId: "device_1"
        ))
        XCTAssertEqual(pending.status, DirectModePairingStatusKind.pending)
        XCTAssertNil(pending.trustedDevice)

        let remoteClient = DirectModeRemoteClient(
            mac: MacAgentRef(
                macAgentId: "mac_1",
                displayName: "Studio Mac",
                agentSigningPubkey: begin.payload.agentSigningPubkey,
                agentSealingPubkey: begin.payload.agentSealingPubkey
            ),
            endpoint: exposurePlan.endpoint,
            now: { fixedNow }
        )
        try await remoteClient.connect(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            mode: ConnectionMode.loopback
        )

        let beforeApproval = try await remoteClient.send(Self.command(
            requestId: "req_before_approval",
            now: now,
            signingKey: deviceSigningKey
        ))
        XCTAssertFalse(beforeApproval.accepted)
        XCTAssertEqual(beforeApproval.reason, RemoteCommandRejectReason.unauthorizedKind)
        let beforeApprovalStopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(beforeApprovalStopAllCallCount, 0)

        let trusted = try trustedStore.approve(deviceId: "device_1", now: now, validFor: 3_600)
        XCTAssertEqual(trusted.deviceSigningPubkey, submit.request.deviceSigningPubkey)
        XCTAssertEqual(trusted.deviceSealingPubkey, submit.request.deviceSealingPubkey)

        let approved = try await pairingClient.status(DirectModePairingStatusRequest(
            requestId: submit.request.id,
            deviceId: "device_1"
        ))
        XCTAssertEqual(approved.status, DirectModePairingStatusKind.approved)
        XCTAssertEqual(approved.trustedDevice?.deviceId, "device_1")

        let afterApproval = try await remoteClient.send(Self.command(
            requestId: "req_after_approval",
            now: now,
            signingKey: deviceSigningKey
        ))
        XCTAssertTrue(afterApproval.accepted)
        XCTAssertEqual(afterApproval.outcome, RemoteCommandAckOutcome.accepted)
        XCTAssertNil(afterApproval.reason)
        let afterApprovalStopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(afterApprovalStopAllCallCount, 1)
    }

    private static func command(
        requestId: String,
        now: Date,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> RemoteCommand {
        let payload = RemoteCommandPayload.empty
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: requestId,
            timestamp: now,
            kind: .stopAll,
            payload: payload,
            signingKey: signingKey
        )
        return RemoteCommand(requestId: requestId, kind: .stopAll, payload: payload, assertion: assertion)
    }
}

private actor CeremonyRemoteExecutor: RemoteTeamCommandExecuting {
    private var stopAllResult = StopAllResult(terminated: 0)
    private var stopAllCalls = 0

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        fatalError("startRun is not part of the direct-mode pairing ceremony proof")
    }

    func stopRun(runId: String) async -> TeamCancelResponse? {
        nil
    }

    func stopAllRuns() async -> StopAllResult {
        stopAllCalls += 1
        return stopAllResult
    }

    func setStopAllResult(_ result: StopAllResult) {
        stopAllResult = result
    }

    func stopAllCallCount() -> Int {
        stopAllCalls
    }
}
