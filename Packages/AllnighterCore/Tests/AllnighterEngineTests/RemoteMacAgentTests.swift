import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteMacAgentTests: XCTestCase {
    private var root: URL!
    private var trustedStore: TrustedRemoteStore!
    private var dedupeStore: RemoteRequestDedupeStore!
    private var macSigningKey: Curve25519.Signing.PrivateKey!
    private var macSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private var deviceSigningKey: Curve25519.Signing.PrivateKey!
    private var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-mac-agent-\(UUID().uuidString)", isDirectory: true)
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

    func testDrainRegistersAndPostsSignedAckForQueuedCommand() async throws {
        let device = trustedDevice(capabilities: [])
        let command = try signedCommand(requestId: "req_stop_all", kind: .stopAll, payload: .empty)
        let relay = MockRemoteMacRelay(
            trustedDevices: [device],
            inbox: [inboxEntry(command)]
        )
        let executor = CapturingRemoteExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 3))
        let agent = makeAgent(relay: relay, executor: executor)

        let result = try await agent.drainOnce()

        XCTAssertEqual(result.mac.macAgentId, "mac_1")
        XCTAssertEqual(result.syncedTrustedDeviceCount, 1)
        XCTAssertEqual(result.processedCommandCount, 1)
        XCTAssertEqual(result.acknowledgements.first?.accepted, true)
        XCTAssertEqual(result.acknowledgements.first?.requestId, "req_stop_all")
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)

        let registrations = await relay.registrations
        XCTAssertEqual(registrations.map(\.macAgentId), ["mac_1"])
        XCTAssertEqual(registrations.first?.agentSigningPubkey, RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey))

        let heartbeats = await relay.heartbeats
        XCTAssertEqual(heartbeats.first?.macAgentId, "mac_1")
        XCTAssertEqual(heartbeats.first?.at, now)

        let acknowledgements = await relay.acknowledgements
        XCTAssertEqual(acknowledgements.count, 1)
        XCTAssertTrue(try verifyAck(acknowledgements[0].ack))
        XCTAssertEqual(acknowledgements[0].auditEvent.targetSummary, "stopAll terminated=3")
    }

    func testDrainSyncsTrustedDevicesBeforeInboxSoRevokedQueuedCommandCannotExecute() async throws {
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [
            trustedDevice(revoked: false, capabilities: [])
        ]))
        let revoked = trustedDevice(revoked: true, capabilities: [])
        let command = try signedCommand(requestId: "req_revoked_stop_all", kind: .stopAll, payload: .empty)
        let relay = MockRemoteMacRelay(
            trustedDevices: [revoked],
            inbox: [inboxEntry(command)]
        )
        let executor = CapturingRemoteExecutor(now: now)
        let agent = makeAgent(relay: relay, executor: executor)

        let result = try await agent.drainOnce()

        XCTAssertEqual(result.processedCommandCount, 1)
        XCTAssertEqual(result.acknowledgements.first?.accepted, false)
        XCTAssertEqual(result.acknowledgements.first?.reason, .revoked)
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 0)
        XCTAssertEqual(trustedStore.load().trustedDevices.first?.revoked, true)

        let eventLog = await relay.eventLog
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "trustedDevices")),
            try XCTUnwrap(eventLog.firstIndex(of: "pendingCommands"))
        )
        let acknowledgements = await relay.acknowledgements
        let acknowledgement = try XCTUnwrap(acknowledgements.first)
        XCTAssertEqual(acknowledgement.ack.reason, .revoked)
        XCTAssertFalse(acknowledgement.auditEvent.targetSummary.contains("secret"))
    }

    func testDrainRejectsSpoofedFromDeviceIdWithoutExecuting() async throws {
        let device = trustedDevice(capabilities: [])
        let command = try signedCommand(requestId: "req_spoofed_from", kind: .stopAll, payload: .empty)
        let relay = MockRemoteMacRelay(
            trustedDevices: [device],
            inbox: [inboxEntry(command, fromDeviceId: "device_spoof")]
        )
        let executor = CapturingRemoteExecutor(now: now)
        let agent = makeAgent(relay: relay, executor: executor)

        let result = try await agent.drainOnce()

        XCTAssertEqual(result.acknowledgements.first?.accepted, false)
        XCTAssertEqual(result.acknowledgements.first?.reason, .badSignature)
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 0)
        let acknowledgements = await relay.acknowledgements
        let acknowledgement = try XCTUnwrap(acknowledgements.first)
        XCTAssertTrue(try verifyAck(acknowledgement.ack))
    }

    func testDrainRejectsMismatchedRegistrationResponse() async throws {
        let executor = CapturingRemoteExecutor(now: now)
        let agent = makeAgent(relay: MismatchedRegistrationRelay(), executor: executor)

        do {
            _ = try await agent.drainOnce()
            XCTFail("mismatched Mac agent id should fail before syncing trusted devices")
        } catch let error as RemoteMacAgentError {
            XCTAssertEqual(error, .macAgentMismatch(expected: "mac_1", actual: "mac_other"))
        }
    }

    private func makeAgent(
        relay: RemoteMacRelay,
        executor: CapturingRemoteExecutor
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

    private func trustedDevice(
        revoked: Bool = false,
        capabilities: Set<RemoteCapability>
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            revoked: revoked,
            revokedAt: revoked ? now.addingTimeInterval(-1) : nil,
            capabilities: capabilities
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

    private func inboxEntry(
        _ command: RemoteCommand,
        fromDeviceId: String? = nil
    ) -> RemoteCommandInboxEntry {
        RemoteCommandInboxEntry(
            requestId: command.requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            fromDeviceId: fromDeviceId ?? command.assertion.deviceId,
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

private actor CapturingRemoteExecutor: RemoteTeamCommandExecuting {
    private var stopAllResult = StopAllResult(terminated: 0)
    private var stopAllCalls = 0
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        .success(TeamStartResponse(
            runId: "run_\(request.idempotencyKey?.replacingOccurrences(of: "remote:", with: "") ?? "unknown")",
            status: .accepted,
            lane: request.lane?.rawValue,
            teamPresetId: request.teamPresetId,
            teamDisplayName: "Remote Team",
            effort: request.effort?.rawValue,
            acceptedAt: now,
            nextPollAfterMs: 500,
            nextActions: []
        ))
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

private actor MismatchedRegistrationRelay: RemoteMacRelay {
    func registerMacAgent(_ registration: RemoteMacAgentRegistration) async throws -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_other",
            displayName: registration.displayName,
            agentSigningPubkey: registration.agentSigningPubkey,
            agentSealingPubkey: registration.agentSealingPubkey
        )
    }

    func heartbeat(_ heartbeat: RemoteMacAgentHeartbeat) async throws {}

    func trustedDevices(accountId: String, macAgentId: String) async throws -> [TrustedDevice] {
        []
    }

    func pendingCommands(
        accountId: String,
        macAgentId: String,
        limit: Int
    ) async throws -> [RemoteCommandInboxEntry] {
        []
    }

    func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws {}
}
