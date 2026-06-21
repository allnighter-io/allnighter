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

    func testDrainRecordsLocalAuditJournalForQueuedCommand() async throws {
        let device = trustedDevice(capabilities: [])
        let command = try signedCommand(requestId: "req_stop_all", kind: .stopAll, payload: .empty)
        let relay = MockRemoteMacRelay(
            trustedDevices: [device],
            inbox: [inboxEntry(command)]
        )
        let executor = CapturingRemoteExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 3))
        let journal = RemoteAuditJournal(fileURL: root.appendingPathComponent("remote_audit.jsonl"))
        let agent = makeAgent(relay: relay, executor: executor, auditRecorder: journal)

        _ = try await agent.drainOnce()

        let entries = try journal.entries()
        XCTAssertEqual(entries.map(\.requestId), ["req_stop_all"])
        XCTAssertEqual(entries.first?.accountId, "acct_1")
        XCTAssertEqual(entries.first?.macAgentId, "mac_1")
        XCTAssertEqual(entries.first?.auditEvent.deviceId, "device_1")
        XCTAssertEqual(entries.first?.auditEvent.targetSummary, "stopAll terminated=3")
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

    func testDrainSyncsPendingPairRequestsBeforeTrustedDevicesAndInbox() async throws {
        let request = pairRequest(deviceId: "device_cloud")
        let relay = MockRemoteMacRelay(pairRequests: [request])
        let executor = CapturingRemoteExecutor(now: now)
        let agent = makeAgent(relay: relay, executor: executor)

        let result = try await agent.drainOnce()

        XCTAssertEqual(result.syncedPendingPairRequestCount, 1)
        XCTAssertEqual(result.syncedTrustedDeviceCount, 0)
        XCTAssertEqual(result.processedCommandCount, 0)
        XCTAssertEqual(trustedStore.load().pendingRequests, [request])

        let eventLog = await relay.eventLog
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "pendingPairRequests")),
            try XCTUnwrap(eventLog.firstIndex(of: "trustedDevices"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "trustedDevices")),
            try XCTUnwrap(eventLog.firstIndex(of: "pendingCommands"))
        )
    }

    func testDrainPublishesLocalApprovalBeforeCloudTrustedSync() async throws {
        let request = pairRequest(deviceId: "device_cloud")
        try trustedStore.upsertPending(request)
        let approvedDevice = try trustedStore.approve(deviceId: "device_cloud", now: now, validFor: 3_600)
        let relay = MockRemoteMacRelay(pairRequests: [request])
        let executor = CapturingRemoteExecutor(now: now)
        let agent = makeAgent(relay: relay, executor: executor)

        let result = try await agent.drainOnce()

        XCTAssertEqual(result.publishedTrustedDeviceCount, 1)
        XCTAssertEqual(result.syncedTrustedDeviceCount, 1)
        XCTAssertEqual(trustedStore.load().trustedDevices, [approvedDevice])

        let eventLog = await relay.eventLog
        let relayTrusted = try await relay.trustedDevices(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertEqual(relayTrusted, [approvedDevice])
        let relayPending = try await relay.pendingPairRequests(accountId: "acct_1", macAgentId: "mac_1")
        XCTAssertTrue(relayPending.isEmpty)

        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "trustedDevices")),
            try XCTUnwrap(eventLog.firstIndex(of: "upsertTrustedDevice"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "upsertTrustedDevice")),
            try XCTUnwrap(eventLog.lastIndex(of: "trustedDevices"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.lastIndex(of: "trustedDevices")),
            try XCTUnwrap(eventLog.firstIndex(of: "pendingCommands"))
        )
        XCTAssertTrue(eventLog.contains("updatePairRequest"))
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

    func testCoordinatorPollsAfterSuccessfulDrain() async throws {
        let fixedNow = now
        let agent = ScriptedRemoteMacAgent(outcomes: [
            .success(processedCommandCount: 2, syncedTrustedDeviceCount: 3)
        ])
        let sleeper = RecordingRemoteMacAgentSleeper()
        let events = RemoteMacAgentPollEventBox()
        let coordinator = RemoteMacAgentCoordinator(
            agent: agent,
            policy: RemoteMacAgentPollPolicy(pollInterval: 10, initialFailureBackoff: 1),
            sleeper: sleeper,
            now: { fixedNow },
            observe: { events.append($0) }
        )

        await coordinator.run { sleeper.sleepCallCount >= 1 }

        let drainCallCount = await agent.drainCallCount()
        XCTAssertEqual(drainCallCount, 1)
        XCTAssertEqual(sleeper.intervals, [10])
        XCTAssertEqual(events.values, [
            RemoteMacAgentPollEvent(
                attempt: 1,
                outcome: .drained(processedCommandCount: 2, syncedTrustedDeviceCount: 3),
                nextDelay: 10,
                at: now
            )
        ])
    }

    func testCoordinatorBacksOffOnFailureAndResetsAfterSuccess() async throws {
        let fixedNow = now
        let agent = ScriptedRemoteMacAgent(outcomes: [
            .failure("offline"),
            .failure("still-offline"),
            .success(processedCommandCount: 0, syncedTrustedDeviceCount: 1),
            .failure("offline-again")
        ])
        let sleeper = RecordingRemoteMacAgentSleeper()
        let events = RemoteMacAgentPollEventBox()
        let coordinator = RemoteMacAgentCoordinator(
            agent: agent,
            policy: RemoteMacAgentPollPolicy(
                pollInterval: 30,
                initialFailureBackoff: 1,
                maximumFailureBackoff: 4,
                backoffMultiplier: 2
            ),
            sleeper: sleeper,
            now: { fixedNow },
            observe: { events.append($0) }
        )

        await coordinator.run { sleeper.sleepCallCount >= 4 }

        let drainCallCount = await agent.drainCallCount()
        XCTAssertEqual(drainCallCount, 4)
        XCTAssertEqual(sleeper.intervals, [1, 2, 30, 1])
        XCTAssertEqual(events.values.map(\.outcome), [
            .failed(errorType: "ScriptedDrainError"),
            .failed(errorType: "ScriptedDrainError"),
            .drained(processedCommandCount: 0, syncedTrustedDeviceCount: 1),
            .failed(errorType: "ScriptedDrainError")
        ])
    }

    func testCoordinatorStopsWhenSleeperThrows() async throws {
        let fixedNow = now
        let agent = ScriptedRemoteMacAgent(outcomes: [
            .success(processedCommandCount: 1, syncedTrustedDeviceCount: 1),
            .success(processedCommandCount: 1, syncedTrustedDeviceCount: 1)
        ])
        let sleeper = RecordingRemoteMacAgentSleeper(throwOnSleepCall: 1)
        let coordinator = RemoteMacAgentCoordinator(
            agent: agent,
            policy: RemoteMacAgentPollPolicy(pollInterval: 5),
            sleeper: sleeper,
            now: { fixedNow }
        )

        await coordinator.run { false }

        let drainCallCount = await agent.drainCallCount()
        XCTAssertEqual(drainCallCount, 1)
        XCTAssertEqual(sleeper.intervals, [5])
    }

    func testCoordinatorDoesNotDrainWhenAlreadyCancelled() async throws {
        let agent = ScriptedRemoteMacAgent(outcomes: [
            .success(processedCommandCount: 1, syncedTrustedDeviceCount: 1)
        ])
        let sleeper = RecordingRemoteMacAgentSleeper()
        let coordinator = RemoteMacAgentCoordinator(agent: agent, sleeper: sleeper)

        await coordinator.run { true }

        let drainCallCount = await agent.drainCallCount()
        XCTAssertEqual(drainCallCount, 0)
        XCTAssertTrue(sleeper.intervals.isEmpty)
    }

    func testPollPolicyEnforcesPositiveFiniteDelays() {
        let clamped = RemoteMacAgentPollPolicy(
            pollInterval: 0,
            initialFailureBackoff: -1,
            maximumFailureBackoff: 0,
            backoffMultiplier: 0
        )
        XCTAssertEqual(clamped.pollInterval, RemoteMacAgentPollPolicy.minimumDelay)
        XCTAssertEqual(clamped.initialFailureBackoff, RemoteMacAgentPollPolicy.minimumDelay)
        XCTAssertEqual(clamped.maximumFailureBackoff, RemoteMacAgentPollPolicy.minimumDelay)
        XCTAssertEqual(clamped.backoffMultiplier, 1)

        let fallback = RemoteMacAgentPollPolicy(
            pollInterval: .infinity,
            initialFailureBackoff: .nan,
            maximumFailureBackoff: .infinity,
            backoffMultiplier: .nan
        )
        XCTAssertEqual(fallback.pollInterval, 5)
        XCTAssertEqual(fallback.initialFailureBackoff, 1)
        XCTAssertEqual(fallback.maximumFailureBackoff, 60)
        XCTAssertEqual(fallback.backoffMultiplier, 2)
    }

    private func makeAgent(
        relay: RemoteMacRelay,
        executor: CapturingRemoteExecutor,
        auditRecorder: any RemoteAuditRecording = NoopRemoteAuditRecorder()
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
            auditRecorder: auditRecorder,
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

    private func pairRequest(deviceId: String) -> RemotePairRequest {
        RemotePairRequest(
            id: "pair_request_\(deviceId)",
            accountId: "acct_1",
            macAgentId: "mac_1",
            deviceId: deviceId,
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(deviceSigningKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(deviceSealingKey.publicKey),
            requestedAt: now.addingTimeInterval(-30),
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

private enum ScriptedDrainOutcome: Sendable {
    case success(processedCommandCount: Int, syncedTrustedDeviceCount: Int)
    case failure(String)
}

private struct ScriptedDrainError: Error, CustomStringConvertible, Sendable {
    var description: String
}

private actor ScriptedRemoteMacAgent: RemoteMacAgentDraining {
    private var outcomes: [ScriptedDrainOutcome]
    private var calls = 0

    init(outcomes: [ScriptedDrainOutcome]) {
        self.outcomes = outcomes
    }

    func drainOnce() async throws -> RemoteMacAgentDrainResult {
        calls += 1
        let outcome = outcomes.isEmpty ? .success(processedCommandCount: 0, syncedTrustedDeviceCount: 0) : outcomes.removeFirst()
        switch outcome {
        case let .success(processedCommandCount, syncedTrustedDeviceCount):
            return RemoteMacAgentDrainResult(
                mac: MacAgentRef(
                    macAgentId: "mac_1",
                    displayName: "Studio Mac",
                    agentSigningPubkey: "agent_signing_pubkey",
                    agentSealingPubkey: "agent_sealing_pubkey"
                ),
                syncedTrustedDeviceCount: syncedTrustedDeviceCount,
                processedCommandCount: processedCommandCount,
                acknowledgements: []
            )
        case let .failure(message):
            throw ScriptedDrainError(description: message)
        }
    }

    func drainCallCount() -> Int {
        calls
    }
}

private final class RecordingRemoteMacAgentSleeper: RemoteMacAgentSleeping, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedIntervals: [TimeInterval] = []
    private let throwOnSleepCall: Int?

    init(throwOnSleepCall: Int? = nil) {
        self.throwOnSleepCall = throwOnSleepCall
    }

    var intervals: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedIntervals
    }

    var sleepCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedIntervals.count
    }

    func sleep(for interval: TimeInterval) async throws {
        let shouldThrow: Bool = lock.withLock {
            recordedIntervals.append(interval)
            return recordedIntervals.count == throwOnSleepCall
        }
        if shouldThrow {
            throw ScriptedDrainError(description: "sleep-cancelled")
        }
    }
}

private final class RemoteMacAgentPollEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RemoteMacAgentPollEvent] = []

    var values: [RemoteMacAgentPollEvent] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ event: RemoteMacAgentPollEvent) {
        lock.lock()
        stored.append(event)
        lock.unlock()
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

    func macAgents(accountId: String) async throws -> [MacAgentRef] {
        []
    }

    func submitPairRequest(_ request: RemotePairRequestDraft) async throws -> RemotePairRequest {
        request.pairRequest(id: "pair_request_mismatch")
    }

    func pendingPairRequests(accountId: String, macAgentId: String) async throws -> [RemotePairRequest] {
        []
    }

    func pairRequestStatus(
        accountId: String,
        requestId: String,
        deviceId: String,
        checkedAt: Date
    ) async throws -> RemotePairingStatusResponse {
        RemotePairingStatusResponse(
            requestId: requestId,
            deviceId: deviceId,
            status: .notFound,
            checkedAt: checkedAt
        )
    }

    func updatePairRequest(_ request: RemotePairRequest) async throws -> RemotePairRequest {
        request
    }

    func trustedDevices(accountId: String, macAgentId: String) async throws -> [TrustedDevice] {
        []
    }

    func upsertTrustedDevice(_ device: TrustedDevice) async throws {}

    func pendingCommands(
        accountId: String,
        macAgentId: String,
        limit: Int
    ) async throws -> [RemoteCommandInboxEntry] {
        []
    }

    func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws {}

    func publishEvents(
        accountId: String,
        macAgentId: String,
        events: [RemoteRunEventEnvelope]
    ) async throws {}
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
