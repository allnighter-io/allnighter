import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteMacAgentBootstrapTests: XCTestCase {
    private var root: URL!
    private var macSigningKey: Curve25519.Signing.PrivateKey!
    private var macSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private var deviceSigningKey: Curve25519.Signing.PrivateKey!
    private var deviceSealingKey: Curve25519.KeyAgreement.PrivateKey!
    private let now = Date(timeIntervalSince1970: 1_750_360_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-mac-agent-bootstrap-\(UUID().uuidString)", isDirectory: true)
        macSigningKey = Curve25519.Signing.PrivateKey()
        macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        deviceSigningKey = Curve25519.Signing.PrivateKey()
        deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBootstrapBuildsRegisteredAgentWithRouterEventsAndSnapshotSync() async throws {
        let runsRoot = root.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsRoot)
        let journal = RemoteRunEventJournal(rootDirectory: runsRoot)
        _ = try runStore.save(Self.run(id: "run_1", createdAt: now), models: [])
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        let command = try signedCommand(requestId: "req_stop_all")
        let relay = MockRemoteMacRelay(
            trustedDevices: [trustedDevice()],
            inbox: [inboxEntry(command)]
        )
        let executor = BootstrapRemoteExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 4))
        let cursorStore = RemoteMacAgentEventCursorStore(
            fileURL: root.appendingPathComponent("remote_event_cursor.json")
        )
        let bootstrap = makeBootstrap(
            relay: relay,
            runStore: runStore,
            journal: journal,
            executor: executor,
            eventCursorStore: cursorStore
        )

        let result = try await bootstrap.makeRuntime().agent.drainOnce()

        XCTAssertEqual(result.mac.macAgentId, "mac_1")
        XCTAssertEqual(result.processedCommandCount, 1)
        XCTAssertEqual(result.acknowledgements.first?.accepted, true)
        XCTAssertEqual(result.publishedEventCount, 1)
        XCTAssertEqual(result.lastPublishedEventSeq, 1)
        XCTAssertEqual(result.publishedSnapshotRunCount, 1)
        XCTAssertEqual(result.publishedSnapshotLastSeq, 1)
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 1)
        XCTAssertEqual(try cursorStore.load(), 1)

        let registrations = await relay.registrations
        XCTAssertEqual(registrations.map(\.macAgentId), ["mac_1"])
        XCTAssertEqual(registrations.first?.accountId, "acct_1")
        XCTAssertEqual(
            registrations.first?.agentSigningPubkey,
            RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        )
        XCTAssertEqual(
            registrations.first?.agentSealingPubkey,
            RemoteCrypto.sealingPublicKeyBase64(macSealingKey.publicKey)
        )

        let heartbeats = await relay.heartbeats
        XCTAssertEqual(heartbeats.first, RemoteMacAgentHeartbeat(
            accountId: "acct_1",
            macAgentId: "mac_1",
            at: now
        ))

        let acknowledgements = await relay.acknowledgements
        let acknowledgement = try XCTUnwrap(acknowledgements.first)
        XCTAssertTrue(try RemoteCrypto.verifyCommandAck(
            acknowledgement.ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        ))
        XCTAssertEqual(acknowledgement.auditEvent.targetSummary, "stopAll terminated=4")

        let publishedEvents = await relay.publishedEvents
        XCTAssertEqual(publishedEvents.map(\.event.id), ["evt_1"])
        XCTAssertTrue(try RemoteCrypto.verifyRemoteRunEventEnvelope(
            try XCTUnwrap(publishedEvents.first),
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        ))
        let snapshot = try await relay.snapshot(accountId: "acct_1", macAgentId: "mac_1", since: nil)
        XCTAssertEqual(snapshot?.runs.map(\.id), ["run_1"])
        XCTAssertEqual(snapshot?.lastSeq, 1)

        let eventLog = await relay.eventLog
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "trustedDevices")),
            try XCTUnwrap(eventLog.firstIndex(of: "pendingCommands"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(eventLog.firstIndex(of: "publishEvents")),
            try XCTUnwrap(eventLog.firstIndex(of: "publishSnapshot"))
        )
    }

    func testBootstrapUsesDocumentedRouterSkewWindowByDefault() async throws {
        let staleCommand = try signedCommand(
            requestId: "req_stale",
            timestamp: now.addingTimeInterval(-61)
        )
        let relay = MockRemoteMacRelay(
            trustedDevices: [trustedDevice()],
            inbox: [inboxEntry(staleCommand)]
        )
        let executor = BootstrapRemoteExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 4))
        let bootstrap = makeBootstrap(
            relay: relay,
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            journal: RemoteRunEventJournal(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            executor: executor
        )

        let result = try await bootstrap.makeRuntime().agent.drainOnce()

        XCTAssertEqual(result.processedCommandCount, 1)
        XCTAssertEqual(result.acknowledgements.first?.accepted, false)
        XCTAssertEqual(result.acknowledgements.first?.reason, .clockSkew)
        XCTAssertEqual(result.acknowledgements.first?.serverTime, now)
        let stopAllCallCount = await executor.stopAllCallCount()
        XCTAssertEqual(stopAllCallCount, 0)
    }

    func testBootstrapCoordinatorRunsAssembledAgentWithInjectedPolicy() async throws {
        let runStore = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let journal = RemoteRunEventJournal(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let relay = MockRemoteMacRelay()
        let executor = BootstrapRemoteExecutor(now: now)
        let sleeper = RecordingBootstrapSleeper()
        let events = BootstrapPollEventBox()
        let bootstrap = makeBootstrap(
            relay: relay,
            runStore: runStore,
            journal: journal,
            executor: executor,
            pollPolicy: RemoteMacAgentPollPolicy(pollInterval: 12, initialFailureBackoff: 1),
            sleeper: sleeper,
            observe: { events.append($0) }
        )

        await bootstrap.makeRuntime().coordinator.run { sleeper.sleepCallCount >= 1 }

        let registrations = await relay.registrations
        XCTAssertEqual(registrations.map(\.macAgentId), ["mac_1"])
        XCTAssertEqual(sleeper.intervals, [12])
        XCTAssertEqual(events.values, [
            RemoteMacAgentPollEvent(
                attempt: 1,
                outcome: .drained(processedCommandCount: 0, syncedTrustedDeviceCount: 0),
                nextDelay: 12,
                at: now
            ),
        ])
    }

    func testBootstrapScopesDefaultEventCursorStoreByAccountAndMac() {
        let first = defaultCursorBootstrap(accountId: "acct/one", macAgentId: "mac/one")
        let second = defaultCursorBootstrap(accountId: "acct/two", macAgentId: "mac/two")

        XCTAssertNotEqual(first.eventCursorStore.fileURL, second.eventCursorStore.fileURL)
        XCTAssertEqual(
            first.eventCursorStore.fileURL.lastPathComponent,
            "remote_event_publish_cursor_acct_one_mac_one.json"
        )
        XCTAssertEqual(
            second.eventCursorStore.fileURL.lastPathComponent,
            "remote_event_publish_cursor_acct_two_mac_two.json"
        )
    }

    private func makeBootstrap(
        relay: RemoteMacRelay,
        runStore: RunStore,
        journal: RemoteRunEventJournal,
        executor: RemoteTeamCommandExecuting,
        eventCursorStore: RemoteMacAgentEventCursorStore? = nil,
        pollPolicy: RemoteMacAgentPollPolicy = RemoteMacAgentPollPolicy(),
        sleeper: any RemoteMacAgentSleeping = DefaultRemoteMacAgentSleeper(),
        observe: (@Sendable (RemoteMacAgentPollEvent) -> Void)? = nil
    ) -> RemoteMacAgentBootstrap {
        let fixedNow = now
        return RemoteMacAgentBootstrap(
            account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            relay: relay,
            trustedStore: TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_remotes.json")),
            dedupeStore: RemoteRequestDedupeStore(fileURL: root.appendingPathComponent("seen_requests.json")),
            runStore: runStore,
            journal: journal,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            eventCursorStore: eventCursorStore ?? RemoteMacAgentEventCursorStore(
                fileURL: root.appendingPathComponent("remote_event_cursor.json")
            ),
            pollPolicy: pollPolicy,
            sleeper: sleeper,
            now: { fixedNow },
            observe: observe
        )
    }

    private func defaultCursorBootstrap(accountId: String, macAgentId: String) -> RemoteMacAgentBootstrap {
        let fixedNow = now
        return RemoteMacAgentBootstrap(
            account: RemoteAccountSession(accountId: accountId, provider: .apple),
            macAgentId: macAgentId,
            displayName: "Studio Mac",
            relay: MockRemoteMacRelay(),
            trustedStore: TrustedRemoteStore(fileURL: root.appendingPathComponent("trusted_\(macAgentId).json")),
            dedupeStore: RemoteRequestDedupeStore(fileURL: root.appendingPathComponent("dedupe_\(macAgentId).json")),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs_\(macAgentId)", isDirectory: true)),
            journal: RemoteRunEventJournal(rootDirectory: root.appendingPathComponent("journal_\(macAgentId)", isDirectory: true)),
            executor: BootstrapRemoteExecutor(now: now),
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: { fixedNow }
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
            capabilities: Set(RemoteCapability.allCases)
        )
    }

    private func signedCommand(requestId: String, timestamp: Date? = nil) throws -> RemoteCommand {
        let payload = RemoteCommandPayload.empty
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: requestId,
            timestamp: timestamp ?? now,
            kind: .stopAll,
            payload: payload,
            signingKey: deviceSigningKey
        )
        return RemoteCommand(requestId: requestId, kind: .stopAll, payload: payload, assertion: assertion)
    }

    private func inboxEntry(_ command: RemoteCommand) -> RemoteCommandInboxEntry {
        RemoteCommandInboxEntry(
            requestId: command.requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            fromDeviceId: "device_1",
            command: command,
            createdAt: now
        )
    }

    private static func run(id: String, createdAt: Date) -> TeamRun {
        TeamRun(
            id: id,
            prompt: "Remote bootstrap proof",
            status: .fanningOut,
            origin: .ios,
            createdAt: createdAt,
            teamDisplayName: "Remote Team"
        )
    }

    private static func event(id: String, runId: String, now: Date) -> RunEvent {
        RunEvent(
            id: id,
            seq: 0,
            ts: now,
            kind: RunEventKind.runStatusChanged,
            payload: [
                "runId": .string(runId),
                "to": .string(RunStatus.fanningOut.rawValue),
            ]
        )
    }
}

private actor BootstrapRemoteExecutor: RemoteTeamCommandExecuting {
    private let now: Date
    private var stopAllResult = StopAllResult(terminated: 0)
    private var storedStopAllCallCount = 0

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        .success(TeamStartResponse(
            runId: "run_remote",
            status: .accepted,
            lane: nil,
            teamPresetId: nil,
            teamDisplayName: nil,
            effort: nil,
            acceptedAt: now,
            nextPollAfterMs: 500,
            nextActions: []
        ))
    }

    func stopRun(runId: String) async -> TeamCancelResponse? {
        TeamCancelResponse(runId: runId, status: .cancelled, cancelledAt: now)
    }

    func stopAllRuns() async -> StopAllResult {
        storedStopAllCallCount += 1
        return stopAllResult
    }

    func setStopAllResult(_ result: StopAllResult) {
        stopAllResult = result
    }

    func stopAllCallCount() -> Int {
        storedStopAllCallCount
    }
}

private final class RecordingBootstrapSleeper: RemoteMacAgentSleeping, @unchecked Sendable {
    private let queue = DispatchQueue(label: "allnighter.tests.recording-bootstrap-sleeper")
    private var storedIntervals: [TimeInterval] = []

    var intervals: [TimeInterval] {
        queue.sync { storedIntervals }
    }

    var sleepCallCount: Int {
        queue.sync { storedIntervals.count }
    }

    func sleep(for interval: TimeInterval) async throws {
        queue.sync {
            storedIntervals.append(interval)
        }
    }
}

private final class BootstrapPollEventBox: @unchecked Sendable {
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
