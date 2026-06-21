import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class CloudPairingCeremonyTests: XCTestCase {
    private var root: URL!
    private var trustedStore: TrustedRemoteStore!
    private var dedupeStore: RemoteRequestDedupeStore!
    private var macSigningKey: Curve25519.Signing.PrivateKey!
    private var macSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private var deviceSigningKey: Curve25519.Signing.PrivateKey!
    private var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private let now = Date(timeIntervalSince1970: 1_750_900_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-pairing-ceremony-\(UUID().uuidString)", isDirectory: true)
        trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json"))
        dedupeStore = RemoteRequestDedupeStore(fileURL: root.appendingPathComponent("seen_requests.json"))
        macSigningKey = Curve25519.Signing.PrivateKey()
        macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        deviceSigningKey = Curve25519.Signing.PrivateKey()
        deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCloudPairingApprovalEnablesQueuedCommand() async throws {
        let relay = MockRemoteMacRelay(pairRequestIdFactory: { "pair_request_1" })
        let executor = CloudPairingRemoteExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 4))
        let agent = makeAgent(relay: relay, executor: executor)

        let submitted = try await relay.submitPairRequest(pairDraft())
        let firstDrain = try await agent.drainOnce()

        XCTAssertEqual(firstDrain.syncedPendingPairRequestCount, 1)
        XCTAssertEqual(firstDrain.syncedTrustedDeviceCount, 0)
        XCTAssertEqual(firstDrain.processedCommandCount, 0)
        XCTAssertEqual(trustedStore.load().pendingRequests, [submitted])

        let approvedDevice = try trustedStore.approve(deviceId: "device_1", now: now, validFor: 3_600)
        let secondDrain = try await agent.drainOnce()

        XCTAssertEqual(secondDrain.publishedTrustedDeviceCount, 1)
        XCTAssertEqual(secondDrain.syncedTrustedDeviceCount, 1)
        let relayTrusted = try await relay.trustedDevices(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(relayTrusted, [approvedDevice])
        let pendingAfterApproval = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertTrue(pendingAfterApproval.isEmpty)

        let command = try signedCommand(requestId: "req_cloud_stop_all", kind: .stopAll, payload: .empty)
        await relay.enqueue(inboxEntry(command))
        let thirdDrain = try await agent.drainOnce()

        XCTAssertEqual(thirdDrain.processedCommandCount, 1)
        XCTAssertEqual(thirdDrain.acknowledgements.first?.accepted, true)
        XCTAssertEqual(thirdDrain.acknowledgements.first?.requestId, "req_cloud_stop_all")
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)

        let acknowledgements = await relay.acknowledgements
        let envelope = try XCTUnwrap(acknowledgements.first)
        XCTAssertTrue(try verifyAck(envelope.ack))
        XCTAssertEqual(envelope.auditEvent.targetSummary, "stopAll terminated=4")
    }

    private func makeAgent(
        relay: RemoteMacRelay,
        executor: CloudPairingRemoteExecutor
    ) -> RemoteMacAgent {
        let fixedNow = now
        let router = RemoteCommandRouter(
            macAgentId: "mac_1",
            trustedStore: trustedStore,
            dedupeStore: dedupeStore,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: { fixedNow }
        )
        return RemoteMacAgent(
            identity: RemoteMacAgentIdentity(
                account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
                macAgentId: "mac_1",
                displayName: "Studio Mac",
                agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey),
                agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
            ),
            relay: relay,
            trustedStore: trustedStore,
            router: router,
            now: { fixedNow }
        )
    }

    private func pairDraft() -> RemotePairRequestDraft {
        RemotePairRequestDraft(
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            requestedAt: now,
            expiresAt: now.addingTimeInterval(300)
        )
    }

    private func signedCommand(
        requestId: String,
        kind: RemoteCommandKind,
        payload: RemoteCommandPayload
    ) throws -> RemoteCommand {
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: requestId,
            timestamp: now,
            kind: kind,
            payload: payload,
            signingKey: deviceSigningKey
        )
        return RemoteCommand(requestId: requestId, kind: kind, payload: payload, assertion: assertion)
    }

    private func inboxEntry(_ command: RemoteCommand) -> RemoteCommandInboxEntry {
        RemoteCommandInboxEntry(
            requestId: command.requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            fromDeviceId: command.assertion.deviceId,
            command: command,
            createdAt: now
        )
    }

    private func verifyAck(_ ack: CommandAck) throws -> Bool {
        try RemoteCrypto.verifyCommandAck(
            ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        )
    }
}

private actor CloudPairingRemoteExecutor: RemoteTeamCommandExecuting {
    private var stopAllResult = StopAllResult(terminated: 0)
    private var stopAllCalls = 0
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        fatalError("startRun is not part of the cloud pairing ceremony proof")
    }

    func stopRun(runId: String) async -> TeamCancelResponse? {
        TeamCancelResponse(runId: runId, status: .cancelled, cancelledAt: now)
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
