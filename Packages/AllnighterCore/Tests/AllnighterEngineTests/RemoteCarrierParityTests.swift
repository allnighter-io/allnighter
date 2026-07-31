import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RemoteCarrierParityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_320_000)

    override func setUp() {
        super.setUp()
        ServerAcceptLoopTestGate.enter()
    }

    override func tearDown() {
        ServerAcceptLoopTestGate.exit()
        super.tearDown()
    }

    func testCloudAndDirectCarriersExposeSameSnapshotEventsMediaAndStopAll() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-carrier-parity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let macSigningKey = Curve25519.Signing.PrivateKey()
        let macSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
        let deviceSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let mac = Self.mac(signingKey: macSigningKey, sealingKey: macSealingKey, now: now)
        let device = Self.trustedDevice(
            signingKey: deviceSigningKey,
            sealingKey: deviceSealingKey,
            now: now
        )
        let runsRoot = root.appendingPathComponent("runs", isDirectory: true)
        let runStore = RunStore(rootDirectory: runsRoot)
        let journal = RemoteRunEventJournal(rootDirectory: runsRoot)
        _ = try runStore.save(Self.run(id: "run_1", createdAt: now), models: [])
        _ = try journal.append(Self.event(id: "evt_1", runId: "run_1", now: now))
        let mediaRef = MediaRef(
            ref: "media_1",
            macAgentId: "mac_1",
            r2Key: "remote/media_1",
            contentType: "application/octet-stream",
            expiresAt: now.addingTimeInterval(3_600)
        )
        let mediaPlaintext = Data("private media bytes".utf8)
        let contentKey = Data((0..<RemoteMediaCrypto.contentKeyByteCount).map(UInt8.init))
        let mediaData = try RemoteMediaCrypto.encrypt(mediaPlaintext, contentKey: contentKey)
        let mediaKey = try XCTUnwrap(RemoteMediaCrypto.sealContentKey(
            contentKey,
            ref: mediaRef.ref,
            macAgentId: mediaRef.macAgentId,
            for: [device],
            now: now
        ).first)

        let cloud = try await makeCloudCarrier(
            root: root,
            mac: mac,
            device: device,
            runStore: runStore,
            journal: journal,
            mediaRef: mediaRef,
            mediaData: mediaData,
            mediaKey: mediaKey,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: now
        )
        let direct = try await makeDirectCarrier(
            root: root,
            mac: mac,
            device: device,
            runStore: runStore,
            journal: journal,
            mediaRef: mediaRef,
            mediaData: mediaData,
            mediaKey: mediaKey,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: now
        )
        defer { direct.server.stop() }

        let account = RemoteAccountSession(accountId: "acct_1", provider: .apple)
        try await cloud.client.connect(account: account, mode: .cloudRelay)
        try await direct.client.connect(account: account, mode: .loopback)

        let cloudSnapshot = try await cloud.client.snapshot(macId: "mac_1", since: nil)
        let directSnapshot = try await direct.client.snapshot(macId: "mac_1", since: nil)
        XCTAssertEqual(cloudSnapshot.runs.map(\.id), ["run_1"])
        XCTAssertEqual(directSnapshot.runs.map(\.id), cloudSnapshot.runs.map(\.id))
        XCTAssertEqual(directSnapshot.lastSeq, cloudSnapshot.lastSeq)

        let cloudEvents = await collect(await cloud.client.stream(macId: "mac_1", since: 0))
        let directEvents = await collect(await direct.client.stream(macId: "mac_1", since: 0))
        XCTAssertEqual(cloudEvents.map(\.event.id), ["evt_1"])
        XCTAssertEqual(directEvents.map(\.event.id), cloudEvents.map(\.event.id))

        let cloudMedia = try await cloud.client.fetchSealed(mediaRef)
        let directMedia = try await direct.client.fetchSealed(mediaRef)
        XCTAssertEqual(cloudMedia, mediaData)
        XCTAssertEqual(directMedia, cloudMedia)
        let cloudMediaKey = try await cloud.client.fetchMediaKey(mediaRef, deviceId: "device_1")
        let directMediaKey = try await direct.client.fetchMediaKey(mediaRef, deviceId: "device_1")
        XCTAssertEqual(cloudMediaKey, mediaKey)
        XCTAssertEqual(directMediaKey, cloudMediaKey)
        let cloudPlaintext = try await RemoteMediaFetcher.fetchAndDecrypt(
            client: cloud.client,
            ref: mediaRef,
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey
        )
        let directPlaintext = try await RemoteMediaFetcher.fetchAndDecrypt(
            client: direct.client,
            ref: mediaRef,
            deviceId: "device_1",
            deviceSealingKey: deviceSealingKey
        )
        XCTAssertEqual(cloudPlaintext, mediaPlaintext)
        XCTAssertEqual(directPlaintext, cloudPlaintext)

        let cloudAck = try await cloud.client.send(Self.signedCommand(
            requestId: "req_cloud_stop_all",
            signingKey: deviceSigningKey,
            now: now
        ))
        let directAck = try await direct.client.send(Self.signedCommand(
            requestId: "req_direct_stop_all",
            signingKey: deviceSigningKey,
            now: now
        ))

        XCTAssertEqual(cloudAck.accepted, true)
        XCTAssertEqual(directAck.accepted, true)
        XCTAssertEqual(cloudAck.outcome, .accepted)
        XCTAssertEqual(directAck.outcome, .accepted)
    }

    private func makeCloudCarrier(
        root: URL,
        mac: MacAgentRef,
        device: TrustedDevice,
        runStore: RunStore,
        journal: RemoteRunEventJournal,
        mediaRef: MediaRef,
        mediaData: Data,
        mediaKey: MediaKeyEnvelope,
        macSigningKey: Curve25519.Signing.PrivateKey,
        macSealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: Date
    ) async throws -> (client: CloudRemoteClient, agent: RemoteMacAgent) {
        let relay = MockRemoteMacRelay(
            macs: [mac],
            macAccountIds: ["mac_1": "acct_1"],
            trustedDevices: [device]
        )
        try await relay.publishMedia(ref: mediaRef, data: mediaData, keys: [mediaKey])
        let trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("cloud_trusted_remotes.json"))
        let dedupeStore = RemoteRequestDedupeStore(fileURL: root.appendingPathComponent("cloud_seen_requests.json"))
        let executor = CarrierParityExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 2))
        let router = RemoteCommandRouter(
            accountId: "acct_1",
            macAgentId: "mac_1",
            trustedStore: trustedStore,
            dedupeStore: dedupeStore,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: { now }
        )
        let eventSync = RemoteMacAgentEventSync(
            publisher: RemoteRunEventPublisher(
                accountId: "acct_1",
                macAgentId: "mac_1",
                journal: journal,
                relay: relay,
                signingKey: macSigningKey
            ),
            cursorStore: RemoteMacAgentEventCursorStore(
                fileURL: root.appendingPathComponent("cloud_event_cursor.json")
            )
        )
        let snapshotPublisher = RemoteSnapshotPublisher(
            accountId: "acct_1",
            macAgentId: "mac_1",
            service: RemoteSnapshotService(runStore: runStore, journal: journal, now: { now }),
            relay: relay
        )
        let agent = RemoteMacAgent(
            identity: RemoteMacAgentIdentity(
                account: RemoteAccountSession(accountId: "acct_1", provider: .apple),
                macAgentId: "mac_1",
                displayName: "Studio Mac",
                agentSigningPubkey: mac.agentSigningPubkey,
                agentSealingPubkey: mac.agentSealingPubkey
            ),
            relay: relay,
            trustedStore: trustedStore,
            router: router,
            eventSync: eventSync,
            snapshotPublisher: snapshotPublisher,
            now: { now }
        )
        _ = try await agent.drainOnce()
        let client = CloudRemoteClient(
            mac: mac,
            relay: relay,
            sleeper: DrainOnSleepSleeper(agent: agent),
            now: { now }
        )
        return (client, agent)
    }

    private func makeDirectCarrier(
        root: URL,
        mac: MacAgentRef,
        device: TrustedDevice,
        runStore: RunStore,
        journal: RemoteRunEventJournal,
        mediaRef: MediaRef,
        mediaData: Data,
        mediaKey: MediaKeyEnvelope,
        macSigningKey: Curve25519.Signing.PrivateKey,
        macSealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: Date
    ) async throws -> (client: DirectModeRemoteClient, server: DirectModeCommandServer) {
        let trustedStore = TrustedRemoteStore(fileURL: root.appendingPathComponent("direct_trusted_remotes.json"))
        try trustedStore.save(TrustedRemoteRegistry(trustedDevices: [device]))
        let dedupeStore = RemoteRequestDedupeStore(fileURL: root.appendingPathComponent("direct_seen_requests.json"))
        let executor = CarrierParityExecutor(now: now)
        await executor.setStopAllResult(StopAllResult(terminated: 2))
        let mediaRelay = MockRemoteMacRelay()
        try await mediaRelay.publishMedia(ref: mediaRef, data: mediaData, keys: [mediaKey])
        let router = RemoteCommandRouter(
            accountId: "acct_1",
            macAgentId: "mac_1",
            trustedStore: trustedStore,
            dedupeStore: dedupeStore,
            executor: executor,
            macSigningKey: macSigningKey,
            macSealingKey: macSealingKey,
            now: { now }
        )
        let server = DirectModeCommandServer(
            handler: DirectModeCommandHandler(
                accountId: "acct_1",
                macAgentId: "mac_1",
                router: router,
                now: { now }
            ),
            snapshotHandler: DirectModeSnapshotHandler(
                accountId: "acct_1",
                macAgentId: "mac_1",
                service: RemoteSnapshotService(runStore: runStore, journal: journal, now: { now })
            ),
            mediaHandler: DirectModeMediaHandler(
                accountId: "acct_1",
                macAgentId: "mac_1",
                provider: RelayDirectModeMediaProvider(relay: mediaRelay),
                now: { now }
            ),
            mediaKeyHandler: DirectModeMediaKeyHandler(
                accountId: "acct_1",
                macAgentId: "mac_1",
                provider: RelayDirectModeMediaProvider(relay: mediaRelay),
                now: { now }
            ),
            eventsHandler: DirectModeEventsHandler(
                accountId: "acct_1",
                macAgentId: "mac_1",
                journal: journal,
                signingKey: macSigningKey
            )
        )
        let port = try server.start()
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModeRemoteClient(mac: mac, endpoint: endpoint, now: { now })
        return (client, server)
    }

    private func collect(_ stream: AsyncStream<RemoteRunEventEnvelope>) async -> [RemoteRunEventEnvelope] {
        var events: [RemoteRunEventEnvelope] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    private static func mac(
        signingKey: Curve25519.Signing.PrivateKey,
        sealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: Date
    ) -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            lastSeenAt: now
        )
    }

    private static func trustedDevice(
        signingKey: Curve25519.Signing.PrivateKey,
        sealingKey: Curve25519.KeyAgreement.PrivateKey,
        now: Date
    ) -> TrustedDevice {
        TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            capabilities: Set(RemoteCapability.allCases)
        )
    }

    private static func signedCommand(
        requestId: String,
        signingKey: Curve25519.Signing.PrivateKey,
        now: Date
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

    private static func run(id: String, createdAt: Date) -> TeamRun {
        TeamRun(
            id: id,
            prompt: "Sensitive prompt stays local",
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

private struct DrainOnSleepSleeper: CloudRemoteClientSleeping {
    let agent: RemoteMacAgent

    func sleep(for interval: TimeInterval) async throws {
        _ = try await agent.drainOnce()
    }
}

private struct RelayDirectModeMediaProvider: DirectModeMediaDataProviding, DirectModeMediaKeyProviding {
    let relay: any RemoteMacRelay

    func mediaData(ref: String, macAgentId: String, at: Date) async throws -> Data? {
        try await relay.mediaData(ref: ref, macAgentId: macAgentId, at: at)
    }

    func mediaKey(ref: String, macAgentId: String, deviceId: String, at: Date) async throws -> MediaKeyEnvelope? {
        try await relay.mediaKey(ref: ref, macAgentId: macAgentId, deviceId: deviceId, at: at)
    }
}

private actor CarrierParityExecutor: RemoteTeamCommandExecuting {
    private let now: Date
    private var stopAllResult = StopAllResult(terminated: 0)

    init(now: Date) {
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        .success(TeamStartResponse(
            runId: "run_remote",
            status: .queued,
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
        stopAllResult
    }

    func setStopAllResult(_ result: StopAllResult) {
        stopAllResult = result
    }
}
