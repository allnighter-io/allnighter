import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class CloudRemoteClientTests: XCTestCase {
    private var root: URL!
    private var trustedStore: TrustedRemoteStore!
    private var dedupeStore: RemoteRequestDedupeStore!
    private var macSigningKey: Curve25519.Signing.PrivateKey!
    private var macSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private var deviceSigningKey: Curve25519.Signing.PrivateKey!
    private var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private let now = Date(timeIntervalSince1970: 1_751_300_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-remote-client-\(UUID().uuidString)", isDirectory: true)
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

    func testClientSubmitsCommandAndWaitsForMacSignedAck() async throws {
        let device = trustedDevice()
        let relay = MockRemoteMacRelay(trustedDevices: [device])
        let executor = CloudRemoteClientExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 2))
        let agent = makeAgent(relay: relay, executor: executor)
        let sleeper = DrainingCloudRemoteClientSleeper(agent: agent)
        let fixedNow = now
        let client = CloudRemoteClient(
            mac: macRef(),
            relay: relay,
            sleeper: sleeper,
            now: { fixedNow },
            ackPollInterval: 0,
            maxAckPollAttempts: 3
        )
        try await client.connect(account: account, mode: .cloudRelay)

        let ack = try await client.send(try signedCommand(requestId: "req_stop_all"))

        XCTAssertEqual(ack.requestId, "req_stop_all")
        XCTAssertTrue(ack.accepted)
        XCTAssertEqual(ack.outcome, .accepted)
        XCTAssertTrue(try RemoteCrypto.verifyCommandAck(
            ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        ))
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)

        let acknowledgements = await relay.acknowledgements
        XCTAssertEqual(acknowledgements.map(\.requestId), ["req_stop_all"])
        XCTAssertEqual(acknowledgements.first?.auditEvent.targetSummary, "stopAll terminated=2")

        let diagnosis = await client.diagnose()
        XCTAssertEqual(diagnosis.rungs.first(where: { $0.rung == .macReachable })?.ok, true)
        XCTAssertEqual(diagnosis.rungs.first(where: { $0.rung == .deviceApproved })?.ok, true)
    }

    func testClientRejectsBadAckSignature() async throws {
        let relay = MockRemoteMacRelay()
        let badSigningKey = Curve25519.Signing.PrivateKey()
        try await relay.acknowledge(ackEnvelope(
            requestId: "req_bad_sig",
            signingKey: badSigningKey
        ))
        let fixedNow = now
        let client = CloudRemoteClient(
            mac: macRef(),
            relay: relay,
            now: { fixedNow },
            ackPollInterval: 0,
            maxAckPollAttempts: 1
        )
        try await client.connect(account: account, mode: .cloudRelay)

        do {
            _ = try await client.send(try signedCommand(requestId: "req_bad_sig"))
            XCTFail("bad Mac ack signature should be rejected")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .badAckSignature)
        }
    }

    func testClientRejectsWrongModeAndTimesOutWithoutAck() async throws {
        let relay = MockRemoteMacRelay()
        let fixedNow = now
        let client = CloudRemoteClient(
            mac: macRef(),
            relay: relay,
            now: { fixedNow },
            ackPollInterval: 0,
            maxAckPollAttempts: 1
        )

        do {
            try await client.connect(account: account, mode: .tailscaleDirect)
            XCTFail("cloud remote client should require cloud relay mode")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .unsupportedMode(.tailscaleDirect))
        }

        try await client.connect(account: account, mode: .cloudRelay)
        do {
            _ = try await client.send(try signedCommand(requestId: "req_no_ack"))
            XCTFail("missing Mac ack should time out")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .ackTimedOut("req_no_ack"))
        }
    }

    private var account: RemoteAccountSession {
        RemoteAccountSession(accountId: "acct_1", provider: .apple)
    }

    private func makeAgent(
        relay: RemoteMacRelay,
        executor: CloudRemoteClientExecutor
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
                account: account,
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

    private func macRef() -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey),
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
        )
    }

    private func trustedDevice() -> TrustedDevice {
        TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            capabilities: []
        )
    }

    private func signedCommand(requestId: String) throws -> RemoteCommand {
        let payload = RemoteCommandPayload.empty
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: requestId,
            timestamp: now,
            kind: .stopAll,
            payload: payload,
            signingKey: deviceSigningKey
        )
        return RemoteCommand(requestId: requestId, kind: .stopAll, payload: payload, assertion: assertion)
    }

    private func ackEnvelope(
        requestId: String,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> RemoteCommandAckEnvelope {
        let ack = try RemoteCrypto.makeCommandAck(
            macAgentId: "mac_1",
            requestId: requestId,
            accepted: true,
            outcome: .accepted,
            serverTime: now,
            signingKey: signingKey
        )
        return RemoteCommandAckEnvelope(
            requestId: requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            ack: ack,
            auditEvent: RemoteAuditEvent(
                ts: now,
                deviceId: "device_1",
                commandKind: .stopAll,
                requestId: requestId,
                targetSummary: "stopAll terminated=1",
                outcome: .accepted
            ),
            createdAt: now
        )
    }
}

private actor DrainingCloudRemoteClientSleeper: CloudRemoteClientSleeping {
    private let agent: RemoteMacAgent
    private var hasDrained = false

    init(agent: RemoteMacAgent) {
        self.agent = agent
    }

    func sleep(for interval: TimeInterval) async throws {
        guard !hasDrained else { return }
        hasDrained = true
        _ = try await agent.drainOnce()
    }
}

private actor CloudRemoteClientExecutor: RemoteTeamCommandExecuting {
    private var stopAllResult = StopAllResult(terminated: 0)
    private var stopAllCalls = 0
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        fatalError("startRun is not part of the cloud remote client stopAll proof")
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
