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

        let ack = try await client.send(try commandFactory().stopAll(requestId: "req_stop_all"))

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

    func testClientSendsSealedStartRunThroughMacAgent() async throws {
        let relay = MockRemoteMacRelay(trustedDevices: [trustedDevice(capabilities: [.startRun])])
        let executor = CloudRemoteClientExecutor(now: now)
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
        let command = try commandFactory().startRun(
            requestId: "req_start",
            payload: RemoteStartRunPayload(
                prompt: "secret cloud prompt",
                lane: "code",
                teamPresetId: "code_core",
                effort: "med",
                context: "private context"
            ),
            mac: macRef()
        )

        let ack = try await client.send(command)

        XCTAssertTrue(ack.accepted)
        let started = await executor.startedRequests()
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.question, "secret cloud prompt")
        XCTAssertEqual(started.first?.lane, .code)
        XCTAssertEqual(started.first?.teamPresetId, "code_core")
        XCTAssertEqual(started.first?.effort, .med)
        XCTAssertEqual(started.first?.context, "private context")
        XCTAssertEqual(started.first?.originAgent, "ios:device_1")
        XCTAssertEqual(started.first?.idempotencyKey, "remote:req_start")

        let acknowledgements = await relay.acknowledgements
        XCTAssertFalse(try XCTUnwrap(acknowledgements.first).auditEvent.targetSummary.contains("secret cloud prompt"))
    }

    func testClientStreamsOnlyVerifiedCloudEventsAfterSeq() async throws {
        let relay = MockRemoteMacRelay()
        let newer = try eventEnvelope(id: "evt_2", seq: 2, kind: "run.completed")
        let older = try eventEnvelope(id: "evt_1", seq: 1, kind: "run.started")
        let forged = RemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(
                id: "evt_forged",
                seq: 3,
                ts: now,
                kind: "run.failed",
                payload: ["runId": .string("run_1")]
            ),
            signature: Data("not a real signature".utf8).base64EncodedString()
        )
        try await relay.publishEvents(
            accountId: "acct_1",
            macAgentId: "mac_1",
            events: [older, forged, newer]
        )
        let client = CloudRemoteClient(mac: macRef(), relay: relay)
        try await client.connect(account: account, mode: .cloudRelay)

        let stream = await client.stream(macId: "mac_1", since: 1)
        var ids: [String] = []
        for await envelope in stream {
            ids.append(envelope.event.id)
        }

        XCTAssertEqual(ids, ["evt_2"])
    }

    func testClientFiltersStaleEventsFromStreamingRelay() async throws {
        let relay = UnfilteredStreamingRelay(events: [
            try eventEnvelope(id: "evt_old", seq: 1, kind: "run.started"),
            try eventEnvelope(id: "evt_new", seq: 2, kind: "run.completed"),
        ])
        let client = CloudRemoteClient(mac: macRef(), relay: relay)
        try await client.connect(account: account, mode: .cloudRelay)

        let stream = await client.stream(macId: "mac_1", since: 1)
        var ids: [String] = []
        for await envelope in stream {
            ids.append(envelope.event.id)
        }

        XCTAssertEqual(ids, ["evt_new"])
    }

    func testClientFetchesPublishedCloudSnapshot() async throws {
        let relay = MockRemoteMacRelay()
        let snapshot = snapshotEnvelope()
        try await relay.publishSnapshot(accountId: "acct_1", macAgentId: "mac_1", snapshot: snapshot)
        let client = CloudRemoteClient(mac: macRef(), relay: relay)
        try await client.connect(account: account, mode: .cloudRelay)

        let fetched = try await client.snapshot(macId: "mac_1", since: nil)

        XCTAssertEqual(fetched, snapshot)

        let missingClient = CloudRemoteClient(mac: macRef(), relay: MockRemoteMacRelay())
        try await missingClient.connect(account: account, mode: .cloudRelay)
        do {
            _ = try await missingClient.snapshot(macId: "mac_1", since: nil)
            XCTFail("missing relay snapshot should be explicit")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .snapshotNotFound("mac_1"))
        }
    }

    func testClientFetchesCloudMediaData() async throws {
        let relay = MockRemoteMacRelay()
        let ref = mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60))
        try await relay.publishMedia(ref: ref, data: Data("ciphertext".utf8), keys: [])
        let fixedNow = now
        let client = CloudRemoteClient(mac: macRef(), relay: relay, now: { fixedNow })
        try await client.connect(account: account, mode: .cloudRelay)

        let data = try await client.fetchSealed(ref)

        XCTAssertEqual(data, Data("ciphertext".utf8))

        let expired = mediaRef(ref: "media_expired", expiresAt: now.addingTimeInterval(-1))
        try await relay.publishMedia(ref: expired, data: Data("old".utf8), keys: [])
        do {
            _ = try await client.fetchSealed(expired)
            XCTFail("expired media should be explicit")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .mediaNotFound("media_expired"))
        }
    }

    func testClientFetchesCloudMediaKey() async throws {
        let relay = MockRemoteMacRelay()
        let ref = mediaRef(ref: "media_1", expiresAt: now.addingTimeInterval(60))
        let key = mediaKey(ref: "media_1", deviceId: "device_1")
        try await relay.publishMedia(ref: ref, data: Data("ciphertext".utf8), keys: [key])
        let fixedNow = now
        let client = CloudRemoteClient(mac: macRef(), relay: relay, now: { fixedNow })
        try await client.connect(account: account, mode: .cloudRelay)

        let fetched = try await client.fetchMediaKey(ref, deviceId: "device_1")

        XCTAssertEqual(fetched, key)

        let mismatchedRelay = MalformedMediaKeyRelay(key: mediaKey(
            ref: "media_other",
            macAgentId: "mac_2",
            deviceId: "device_other"
        ))
        let mismatchedClient = CloudRemoteClient(mac: macRef(), relay: mismatchedRelay, now: { fixedNow })
        try await mismatchedClient.connect(account: account, mode: .cloudRelay)
        do {
            _ = try await mismatchedClient.fetchMediaKey(ref, deviceId: "device_1")
            XCTFail("mismatched media key envelope should be rejected")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .badMediaKeyEnvelope)
        }

        do {
            _ = try await client.fetchMediaKey(ref, deviceId: "device_missing")
            XCTFail("missing media key should be explicit")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .mediaKeyNotFound(ref: "media_1", deviceId: "device_missing"))
        }
    }

    func testClientRejectsCloudMediaRefsForOtherMac() async throws {
        let fixedNow = now
        let client = CloudRemoteClient(mac: macRef(), relay: MockRemoteMacRelay(), now: { fixedNow })
        try await client.connect(account: account, mode: .cloudRelay)
        let otherMacRef = mediaRef(
            ref: "media_other_mac",
            macAgentId: "mac_other",
            expiresAt: now.addingTimeInterval(60)
        )

        do {
            _ = try await client.fetchSealed(otherMacRef)
            XCTFail("other-Mac media data should be rejected")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .macNotFound("mac_other"))
        }

        do {
            _ = try await client.fetchMediaKey(otherMacRef, deviceId: "device_1")
            XCTFail("other-Mac media key should be rejected")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .macNotFound("mac_other"))
        }
    }

    func testRejectedAuthorizationAckKeepsApprovalDiagnosticFalse() async throws {
        let relay = MockRemoteMacRelay()
        try await relay.acknowledge(ackEnvelope(
            requestId: "req_revoked",
            signingKey: macSigningKey,
            accepted: false,
            reason: .revoked,
            outcome: .rejected
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

        let ack = try await client.send(try commandFactory().stopAll(requestId: "req_revoked"))

        XCTAssertEqual(ack.accepted, false)
        XCTAssertEqual(ack.reason, .revoked)
        let diagnosis = await client.diagnose()
        XCTAssertEqual(diagnosis.rungs.first(where: { $0.rung == .macReachable })?.ok, true)
        XCTAssertEqual(diagnosis.rungs.first(where: { $0.rung == .deviceApproved })?.ok, false)
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
            _ = try await client.send(try commandFactory().stopAll(requestId: "req_bad_sig"))
            XCTFail("bad Mac ack signature should be rejected")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .badAckSignature)
        }
    }

    func testClientRejectsAckEnvelopeWithWrongAuditDeviceId() async throws {
        let relay = MockRemoteMacRelay()
        try await relay.acknowledge(ackEnvelope(
            requestId: "req_bad_audit_device",
            signingKey: macSigningKey,
            auditDeviceId: "device_other"
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
            _ = try await client.send(try commandFactory().stopAll(requestId: "req_bad_audit_device"))
            XCTFail("mismatched audit device id should be rejected")
        } catch let error as CloudRemoteClientError {
            XCTAssertEqual(error, .badAckEnvelope)
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
            _ = try await client.send(try commandFactory().stopAll(requestId: "req_no_ack"))
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
            accountId: account.accountId,
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

    private func trustedDevice(capabilities: Set<RemoteCapability> = []) -> TrustedDevice {
        TrustedDevice(
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
    }

    private func commandFactory() -> RemoteCommandFactory {
        let fixedNow = now
        return RemoteCommandFactory(
            deviceId: "device_1",
            signingKey: deviceSigningKey,
            now: { fixedNow }
        )
    }

    private func ackEnvelope(
        requestId: String,
        signingKey: Curve25519.Signing.PrivateKey,
        accepted: Bool = true,
        reason: RemoteCommandRejectReason? = nil,
        outcome: RemoteCommandAckOutcome = .accepted,
        auditDeviceId: String = "device_1"
    ) throws -> RemoteCommandAckEnvelope {
        let ack = try RemoteCrypto.makeCommandAck(
            macAgentId: "mac_1",
            requestId: requestId,
            accepted: accepted,
            reason: reason,
            outcome: outcome,
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
                deviceId: auditDeviceId,
                commandKind: .stopAll,
                requestId: requestId,
                targetSummary: "stopAll terminated=1",
                outcome: outcome
            ),
            createdAt: now
        )
    }

    private func eventEnvelope(
        id: String,
        seq: Int64,
        kind: String
    ) throws -> RemoteRunEventEnvelope {
        try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(
                id: id,
                seq: seq,
                ts: now,
                kind: kind,
                payload: ["runId": .string("run_1")]
            ),
            signingKey: macSigningKey
        )
    }

    private func snapshotEnvelope() -> SnapshotEnvelope {
        SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .running,
                    origin: .ios,
                    promptExcerpt: "",
                    teamDisplayName: "Remote Team",
                    createdAt: now
                )
            ],
            lastSeq: 7,
            serverTime: now
        )
    }

    private func mediaRef(ref: String, macAgentId: String = "mac_1", expiresAt: Date) -> MediaRef {
        MediaRef(
            ref: ref,
            macAgentId: macAgentId,
            r2Key: "r2/\(ref)",
            contentType: "image/png",
            expiresAt: expiresAt
        )
    }

    private func mediaKey(ref: String, macAgentId: String = "mac_1", deviceId: String) -> MediaKeyEnvelope {
        MediaKeyEnvelope(
            ref: ref,
            macAgentId: macAgentId,
            deviceId: deviceId,
            sealedKey: SealedBlob(
                ciphertext: Data("ciphertext".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: deviceId,
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
    }
}

private actor MalformedMediaKeyRelay: RemoteMacRelay {
    private let key: MediaKeyEnvelope

    init(key: MediaKeyEnvelope) {
        self.key = key
    }

    func registerMacAgent(_: RemoteMacAgentRegistration) async throws -> MacAgentRef {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func heartbeat(_: RemoteMacAgentHeartbeat) async throws {}

    func macAgents(accountId _: String) async throws -> [MacAgentRef] {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func submitPairRequest(_: RemotePairRequestDraft) async throws -> RemotePairRequest {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func pendingPairRequests(accountId _: String, macAgentId _: String) async throws -> [RemotePairRequest] {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func pairRequestStatus(
        accountId _: String,
        macAgentId _: String,
        requestId _: String,
        deviceId _: String,
        checkedAt _: Date
    ) async throws -> RemotePairingStatusResponse {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func updatePairRequest(_: RemotePairRequest) async throws -> RemotePairRequest {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func trustedDevices(accountId _: String, macAgentId _: String) async throws -> [TrustedDevice] {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func upsertTrustedDevice(_: TrustedDevice) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func submitCommand(_: RemoteCommandInboxEntry) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func commandAck(
        accountId _: String,
        macAgentId _: String,
        requestId _: String
    ) async throws -> RemoteCommandAckEnvelope? {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func pendingCommands(accountId _: String, macAgentId _: String, limit _: Int) async throws -> [RemoteCommandInboxEntry] {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func acknowledge(_: RemoteCommandAckEnvelope) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func runEvents(
        accountId _: String,
        macAgentId _: String,
        after _: Int64,
        limit _: Int
    ) async throws -> [RemoteRunEventEnvelope] {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func publishEvents(accountId _: String, macAgentId _: String, events _: [RemoteRunEventEnvelope]) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func publishSnapshot(accountId _: String, macAgentId _: String, snapshot _: SnapshotEnvelope) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func snapshot(accountId _: String, macAgentId _: String, since _: Int64?) async throws -> SnapshotEnvelope? {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func publishMedia(ref _: MediaRef, data _: Data, keys _: [MediaKeyEnvelope]) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func upsertMediaKey(_: MediaKeyEnvelope, macAgentId _: String) async throws {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func mediaData(ref _: String, macAgentId _: String, at _: Date) async throws -> Data? {
        throw MalformedMediaKeyRelayError.unexpectedCall
    }

    func mediaKey(ref _: String, macAgentId _: String, deviceId _: String, at _: Date) async throws -> MediaKeyEnvelope? {
        key
    }
}

private enum MalformedMediaKeyRelayError: Error {
    case unexpectedCall
}

private struct UnfilteredStreamingRelay: RemoteRunEventStreamingRelay {
    var events: [RemoteRunEventEnvelope]

    func runEventStream(
        accountId _: String,
        macAgentId _: String,
        after _: Int64,
        limit _: Int
    ) async -> AsyncStream<RemoteRunEventEnvelope> {
        AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func registerMacAgent(_: RemoteMacAgentRegistration) async throws -> MacAgentRef {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func heartbeat(_: RemoteMacAgentHeartbeat) async throws {}

    func macAgents(accountId _: String) async throws -> [MacAgentRef] {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func submitPairRequest(_: RemotePairRequestDraft) async throws -> RemotePairRequest {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func pendingPairRequests(accountId _: String, macAgentId _: String) async throws -> [RemotePairRequest] {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func pairRequestStatus(
        accountId _: String,
        macAgentId _: String,
        requestId _: String,
        deviceId _: String,
        checkedAt _: Date
    ) async throws -> RemotePairingStatusResponse {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func updatePairRequest(_: RemotePairRequest) async throws -> RemotePairRequest {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func trustedDevices(accountId _: String, macAgentId _: String) async throws -> [TrustedDevice] {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func upsertTrustedDevice(_: TrustedDevice) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func submitCommand(_: RemoteCommandInboxEntry) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func commandAck(
        accountId _: String,
        macAgentId _: String,
        requestId _: String
    ) async throws -> RemoteCommandAckEnvelope? {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func pendingCommands(accountId _: String, macAgentId _: String, limit _: Int) async throws -> [RemoteCommandInboxEntry] {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func acknowledge(_: RemoteCommandAckEnvelope) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func runEvents(
        accountId _: String,
        macAgentId _: String,
        after _: Int64,
        limit _: Int
    ) async throws -> [RemoteRunEventEnvelope] {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func publishEvents(accountId _: String, macAgentId _: String, events _: [RemoteRunEventEnvelope]) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func publishSnapshot(accountId _: String, macAgentId _: String, snapshot _: SnapshotEnvelope) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func snapshot(accountId _: String, macAgentId _: String, since _: Int64?) async throws -> SnapshotEnvelope? {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func publishMedia(ref _: MediaRef, data _: Data, keys _: [MediaKeyEnvelope]) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func upsertMediaKey(_: MediaKeyEnvelope, macAgentId _: String) async throws {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func mediaData(ref _: String, macAgentId _: String, at _: Date) async throws -> Data? {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }

    func mediaKey(ref _: String, macAgentId _: String, deviceId _: String, at _: Date) async throws -> MediaKeyEnvelope? {
        throw UnfilteredStreamingRelayError.unexpectedCall
    }
}

private enum UnfilteredStreamingRelayError: Error {
    case unexpectedCall
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
    private var starts: [AsyncTeamStartRequest] = []
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

    func startedRequests() -> [AsyncTeamStartRequest] {
        starts
    }
}
