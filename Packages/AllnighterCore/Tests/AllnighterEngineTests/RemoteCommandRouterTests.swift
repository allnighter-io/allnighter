import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteCommandRouterTests: XCTestCase {
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
            .appendingPathComponent("remote-router-\(UUID().uuidString)", isDirectory: true)
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

    func testStartRunUnsealsPayloadAndStartsIOSRun() async throws {
        try trustDevice(capabilities: [.startRun])
        let executor = CapturingRemoteExecutor(now: now)
        let router = makeRouter(executor: executor)
        let startPayload = RemoteStartRunPayload(
            prompt: "secret launch prompt",
            lane: "code",
            teamPresetId: "code_core",
            effort: "med",
            context: "private context"
        )
        let sealed = try RemoteCrypto.seal(
            CoreJSON.encode(startPayload),
            to: RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey),
            sealedForKeyId: "mac_1",
            contentType: "application/json"
        )
        let command = try signedCommand(requestId: "req_start", kind: .startRun, payload: .sealed(sealed))

        let result = try await router.route(command)

        XCTAssertTrue(result.ack.accepted)
        XCTAssertEqual(result.startResponse?.runId, "run_req_start")
        XCTAssertTrue(try verifyAck(result.ack))
        let requests = await executor.startedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.question, "secret launch prompt")
        XCTAssertEqual(requests.first?.lane, .code)
        XCTAssertEqual(requests.first?.teamPresetId, "code_core")
        XCTAssertEqual(requests.first?.effort, .med)
        XCTAssertEqual(requests.first?.originAgent, "ios:device_1")
        XCTAssertEqual(requests.first?.idempotencyKey, "remote:req_start")
        XCTAssertFalse(result.auditEvent.targetSummary.contains("secret launch prompt"))
    }

    func testStartRunRequiresSealedPayload() async throws {
        try trustDevice(capabilities: [.startRun])
        let executor = CapturingRemoteExecutor(now: now)
        let router = makeRouter(executor: executor)
        let command = try signedCommand(
            requestId: "req_plaintext",
            kind: .startRun,
            payload: .light(["prompt": .string("do not relay plaintext")])
        )

        let result = try await router.route(command)

        XCTAssertFalse(result.ack.accepted)
        XCTAssertEqual(result.ack.reason, .invalidPayload)
        XCTAssertTrue(try verifyAck(result.ack))
        let startedRequests = await executor.startedRequests()
        XCTAssertEqual(startedRequests.count, 0)
    }

    func testStopRunRoutesToExecutor() async throws {
        try trustDevice(capabilities: [.stopRun])
        let executor = CapturingRemoteExecutor(now: now)
        await executor.setKnownRunIds(["run_1"])
        let router = makeRouter(executor: executor)
        let command = try signedCommand(
            requestId: "req_stop",
            kind: .stopRun,
            payload: .light(["runId": .string("run_1")])
        )

        let result = try await router.route(command)

        XCTAssertTrue(result.ack.accepted)
        XCTAssertEqual(result.stopRunResponse?.runId, "run_1")
        let stoppedRunIds = await executor.stoppedRunIds()
        XCTAssertEqual(stoppedRunIds, ["run_1"])
        XCTAssertEqual(result.auditEvent.targetSummary, "stopRun runId=run_1")
    }

    func testOversizedLightPayloadIsRejectedBeforeExecutor() async throws {
        try trustDevice(capabilities: [.stopRun])
        let executor = CapturingRemoteExecutor(now: now)
        await executor.setKnownRunIds(["run_1"])
        let router = makeRouter(
            executor: executor,
            policy: RemoteCommandRouterPolicy(maxLightPayloadBytes: 8)
        )
        let command = try signedCommand(
            requestId: "req_large_stop",
            kind: .stopRun,
            payload: .light(["runId": .string("run_1")])
        )

        let result = try await router.route(command)

        XCTAssertFalse(result.ack.accepted)
        XCTAssertEqual(result.ack.reason, .payloadTooLarge)
        XCTAssertTrue(try verifyAck(result.ack))
        let stoppedRunIds = await executor.stoppedRunIds()
        XCTAssertEqual(stoppedRunIds, [])
    }

    func testStopAllIsNotCapabilityGatedAndReturnsTerminatedCount() async throws {
        try trustDevice(capabilities: [])
        let executor = CapturingRemoteExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 2))
        let router = makeRouter(executor: executor)
        let command = try signedCommand(requestId: "req_stop_all", kind: .stopAll, payload: .empty)

        let result = try await router.route(command)

        XCTAssertTrue(result.ack.accepted)
        XCTAssertEqual(result.stopAllResult, StopAllResult(terminated: 2))
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)
        XCTAssertTrue(try verifyAck(result.ack))
    }

    func testReplayIsRejectedBeforeSecondExecution() async throws {
        try trustDevice(capabilities: [])
        let executor = CapturingRemoteExecutor(now: now)
        let router = makeRouter(executor: executor)
        let command = try signedCommand(requestId: "req_replay", kind: .stopAll, payload: .empty)

        let first = try await router.route(command)
        let replay = try await router.route(command)

        XCTAssertTrue(first.ack.accepted)
        XCTAssertFalse(replay.ack.accepted)
        XCTAssertEqual(replay.ack.outcome, .duplicate)
        XCTAssertEqual(replay.ack.reason, .replayedRequestId)
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)
    }

    func testPerDeviceRateLimitRejectsSecondDistinctCommand() async throws {
        try trustDevice(capabilities: [])
        let executor = CapturingRemoteExecutor(now: now)
        let router = makeRouter(
            executor: executor,
            policy: RemoteCommandRouterPolicy(maxCommandsPerDevicePerWindow: 1, rateLimitWindow: 60)
        )
        let firstCommand = try signedCommand(requestId: "req_rate_1", kind: .stopAll, payload: .empty)
        let secondCommand = try signedCommand(requestId: "req_rate_2", kind: .stopAll, payload: .empty)

        let first = try await router.route(firstCommand)
        let second = try await router.route(secondCommand)

        XCTAssertTrue(first.ack.accepted)
        XCTAssertFalse(second.ack.accepted)
        XCTAssertEqual(second.ack.reason, .rateLimited)
        XCTAssertTrue(try verifyAck(second.ack))
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)
    }

    private func makeRouter(
        executor: CapturingRemoteExecutor,
        policy: RemoteCommandRouterPolicy = .default
    ) -> RemoteCommandRouter {
        let fixedNow = now
        return RemoteCommandRouter(
            macAgentId: "mac_1",
            trustedStore: trustedStore,
            dedupeStore: dedupeStore,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: { fixedNow },
            policy: policy
        )
    }

    private func trustDevice(capabilities: Set<RemoteCapability>) throws {
        let device = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            capabilities: capabilities
        )
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [device]))
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

    private func verifyAck(_ ack: CommandAck) throws -> Bool {
        try RemoteCrypto.verifyCommandAck(
            ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        )
    }
}

private actor CapturingRemoteExecutor: RemoteTeamCommandExecuting {
    private var starts: [AsyncTeamStartRequest] = []
    private var stopped: [String] = []
    private var knownRunIds: Set<String> = []
    private var stopAllResult = StopAllResult(terminated: 0)
    private var stopAllCalls = 0
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        starts.append(request)
        return .success(TeamStartResponse(
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
        guard knownRunIds.contains(runId) else { return nil }
        stopped.append(runId)
        return TeamCancelResponse(runId: runId, status: .cancelled, cancelledAt: now)
    }

    func stopAllRuns() async -> StopAllResult {
        stopAllCalls += 1
        return stopAllResult
    }

    func setKnownRunIds(_ ids: Set<String>) {
        knownRunIds = ids
    }

    func setStopAllResult(_ result: StopAllResult) {
        stopAllResult = result
    }

    func startedRequests() -> [AsyncTeamStartRequest] {
        starts
    }

    func stoppedRunIds() -> [String] {
        stopped
    }

    func stopAllCallCount() -> Int {
        stopAllCalls
    }
}
