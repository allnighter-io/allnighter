import CryptoKit
import Foundation
import XCTest
@testable import AllnighterCore

final class RemoteFoundationTests: XCTestCase {
    func testCommandSetIsClosedAndHasNoShellEscape() {
        let cases = RemoteCommandKind.allCases.map(\.rawValue)
        XCTAssertEqual(cases, [
            "startRun",
            "stopRun",
            "stopAll",
            "approveRequest",
            "rejectRequest",
            "openOnMac",
            "landPlane",
        ])
        XCTAssertFalse(cases.contains { $0.localizedCaseInsensitiveContains("shell") })
        XCTAssertFalse(cases.contains { $0.localizedCaseInsensitiveContains("mcp") })
    }

    func testStartRunRequiresSealedPayloadAndStopAllIsCapabilityUngated() {
        XCTAssertTrue(RemoteCommandKind.startRun.requiresSealedPayload)
        XCTAssertEqual(RemoteCommandKind.startRun.requiredCapability, .startRun)
        XCTAssertFalse(RemoteCommandKind.stopAll.requiresSealedPayload)
        XCTAssertNil(RemoteCommandKind.stopAll.requiredCapability)

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let trusted = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "signing",
            deviceSealingPubkey: "sealing",
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now,
            validUntil: now.addingTimeInterval(60),
            capabilities: []
        )

        XCTAssertTrue(trusted.authorizes(.stopAll, at: now))
        XCTAssertFalse(trusted.authorizes(.startRun, at: now))
    }

    func testStartRunCommandRejectsPlainLightPayloadByContract() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let payload = RemoteCommandPayload.light(["prompt": .string("do the secret thing")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            kind: .startRun,
            payload: payload,
            signingKey: signingKey
        )
        let command = RemoteCommand(requestId: "req_1", kind: .startRun, payload: payload, assertion: assertion)
        XCTAssertFalse(command.carriesRequiredSealedPayload)
    }

    func testCommandSigningStringIsDeterministicAndDeviceBound() {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let signingString = RemoteCrypto.commandSigningString(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: timestamp,
            kind: .startRun,
            payloadSHA256: "abc123"
        )

        XCTAssertEqual(
            signingString,
            "device_1|remote.command.v1|req_1|2025-06-15T15:06:40Z|1|startRun|abc123"
        )
    }

    func testPayloadDigestIsCanonicalForLightJSON() throws {
        let one = RemoteCommandPayload.light(["b": .int(2), "a": .string("one")])
        let two = RemoteCommandPayload.light(["a": .string("one"), "b": .int(2)])
        XCTAssertEqual(try RemoteCrypto.payloadDigest(one), try RemoteCrypto.payloadDigest(two))
    }

    func testMacRelayContractsRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let registration = RemoteMacAgentRegistration(
            accountId: "acct_1",
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: "signing",
            agentSealingPubkey: "sealing"
        )
        XCTAssertEqual(
            try CoreJSON.decode(RemoteMacAgentRegistration.self, from: CoreJSON.encode(registration)),
            registration
        )

        let heartbeat = RemoteMacAgentHeartbeat(accountId: "acct_1", macAgentId: "mac_1", at: now)
        XCTAssertEqual(
            try CoreJSON.decode(RemoteMacAgentHeartbeat.self, from: CoreJSON.encode(heartbeat)),
            heartbeat
        )

        let assertion = DeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: now,
            kind: .stopAll,
            payloadSHA256: "digest",
            signature: "signature"
        )
        let command = RemoteCommand(requestId: "req_1", kind: .stopAll, payload: .empty, assertion: assertion)
        let inbox = RemoteCommandInboxEntry(
            requestId: "req_1",
            accountId: "acct_1",
            macAgentId: "mac_1",
            fromDeviceId: "device_1",
            command: command,
            createdAt: now
        )
        XCTAssertEqual(
            try CoreJSON.decode(RemoteCommandInboxEntry.self, from: CoreJSON.encode(inbox)),
            inbox
        )

        let ack = CommandAck(requestId: "req_1", accepted: true, outcome: .accepted, signature: "sig")
        let audit = RemoteAuditEvent(
            ts: now,
            deviceId: "device_1",
            commandKind: .stopAll,
            requestId: "req_1",
            targetSummary: "stopAll terminated=1",
            outcome: .accepted
        )
        let envelope = RemoteCommandAckEnvelope(
            requestId: "req_1",
            accountId: "acct_1",
            macAgentId: "mac_1",
            ack: ack,
            auditEvent: audit,
            createdAt: now
        )
        XCTAssertEqual(
            try CoreJSON.decode(RemoteCommandAckEnvelope.self, from: CoreJSON.encode(envelope)),
            envelope
        )
    }

    func testDeviceAssertionSignsAndRejectsTampering() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let publicKey = RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        let payload = RemoteCommandPayload.light(["runId": .string("run_1")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            kind: .stopRun,
            payload: payload,
            signingKey: signingKey
        )

        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(assertion, signingPublicKeyBase64: publicKey))

        var tampered = assertion
        tampered.kind = .stopAll
        XCTAssertFalse(try RemoteCrypto.verifyDeviceAssertion(tampered, signingPublicKeyBase64: publicKey))
    }

    func testRemoteEventEnvelopeSignsAndRejectsTampering() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let publicKey = RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        let event = RunEvent(
            id: "evt_1",
            seq: 1,
            ts: Date(timeIntervalSince1970: 1_750_000_000),
            kind: RunEventKind.synthesisCompleted,
            payload: ["runId": .string("run_1")]
        )

        let envelope = try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: event,
            signingKey: signingKey
        )
        XCTAssertEqual(envelope.event.kind, RunEventKind.stageCompleted)
        XCTAssertTrue(try RemoteCrypto.verifyRemoteRunEventEnvelope(envelope, signingPublicKeyBase64: publicKey))

        var tampered = envelope
        tampered.event.payload["runId"] = .string("run_2")
        XCTAssertFalse(try RemoteCrypto.verifyRemoteRunEventEnvelope(tampered, signingPublicKeyBase64: publicKey))
    }

    func testHPKESealedBlobRoundTripsAndCarriesNoPlaintext() throws {
        let recipient = Curve25519.KeyAgreement.PrivateKey()
        let recipientPublicKey = RemoteCrypto.sealingPublicKeyBase64(recipient.publicKey)
        let plaintext = Data("start run with the sealed prompt".utf8)

        let blob = try RemoteCrypto.seal(
            plaintext,
            to: recipientPublicKey,
            sealedForKeyId: "agent_seal_1",
            contentType: "application/vnd.allnighter.remote-command+json"
        )

        XCTAssertEqual(blob.suite, .hpkeCurve25519HKDFSHA256AESGCM256)
        XCTAssertNotEqual(blob.ciphertext, plaintext)
        XCTAssertFalse(String(decoding: blob.ciphertext, as: UTF8.self).contains("sealed prompt"))

        let opened = try RemoteCrypto.open(blob, with: recipient)
        XCTAssertEqual(opened, plaintext)
    }

    func testRemoteEventEnvelopeNormalizesLegacySynthesisKinds() {
        let event = RunEvent(
            id: "evt_1",
            seq: 7,
            ts: Date(timeIntervalSince1970: 1_750_000_000),
            kind: RunEventKind.synthesisCompleted,
            payload: ["runId": .string("run_1")]
        )

        let envelope = RemoteRunEventEnvelope(event: event, signature: "sig")
        XCTAssertEqual(envelope.event.kind, RunEventKind.stageCompleted)
        XCTAssertTrue(RunEventKind.isRemotePublicKind(envelope.event.kind))
    }

    func testSnapshotEnvelopeRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .done,
                    origin: .ios,
                    promptExcerpt: "Update the tests",
                    teamDisplayName: "Default Team",
                    createdAt: now,
                    completedAt: now.addingTimeInterval(20)
                )
            ],
            lastSeq: 42,
            serverTime: now
        )

        let decoded = try CoreJSON.decode(SnapshotEnvelope.self, from: CoreJSON.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }

    func testRemoteAuditEventCapsSummary() {
        let audit = RemoteAuditEvent(
            ts: Date(timeIntervalSince1970: 1_750_000_000),
            deviceId: "device_1",
            commandKind: .stopRun,
            requestId: "req_1",
            targetSummary: String(repeating: "x", count: 240),
            outcome: .accepted
        )

        XCTAssertEqual(audit.targetSummary.count, RemoteAuditEvent.targetSummaryLimit)
    }

    func testReducerAppliesSnapshotThenEventsIdempotently() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .running,
                    origin: .ios,
                    promptExcerpt: "Ship the reducer",
                    createdAt: now
                )
            ],
            lastSeq: 10,
            serverTime: now
        )
        let done = RemoteRunEventEnvelope(
            event: RunEvent(
                id: "evt_done",
                seq: 12,
                ts: now.addingTimeInterval(2),
                kind: RunEventKind.runStatusChanged,
                payload: ["runId": .string("run_1"), "to": .string("done")]
            ),
            signature: "sig"
        )
        let duplicate = RemoteRunEventEnvelope(
            event: RunEvent(
                id: "evt_done",
                seq: 13,
                ts: now.addingTimeInterval(3),
                kind: RunEventKind.runStatusChanged,
                payload: ["runId": .string("run_1"), "to": .string("failed")]
            ),
            signature: "sig"
        )

        let state = RemoteRunReducer.apply(snapshot: snapshot, events: [duplicate, done])
        XCTAssertEqual(state.lastSeq, 12)
        XCTAssertEqual(state.recentEvents.map(\.event.id), ["evt_done"])
        XCTAssertEqual(state.run(id: "run_1")?.status, .done)
        XCTAssertEqual(state.run(id: "run_1")?.completedAt, now.addingTimeInterval(2))
    }

    func testReducerUpsertsRunFromStartedEvent() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = SnapshotEnvelope(runs: [], lastSeq: 0, serverTime: now)
        let started = RemoteRunEventEnvelope(
            event: RunEvent(
                id: "evt_started",
                seq: 1,
                ts: now,
                kind: "run.started",
                payload: [
                    "runId": .string("run_new"),
                    "origin": .string("ios"),
                    "promptExcerpt": .string("Start fresh"),
                    "teamDisplayName": .string("Default Team"),
                ]
            ),
            signature: "sig"
        )

        let state = RemoteRunReducer.apply(snapshot: snapshot, events: [started])
        XCTAssertEqual(state.run(id: "run_new")?.status, .running)
        XCTAssertEqual(state.run(id: "run_new")?.promptExcerpt, "Start fresh")
        XCTAssertEqual(state.lastSeq, 1)
    }

    func testMockClientStreamsOnlyVerifiedEventsAfterSeq() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let agentSigningKey = Curve25519.Signing.PrivateKey()
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(agentSigningKey.publicKey),
            agentSealingPubkey: "agent-seal"
        )
        let older = try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(id: "evt_1", seq: 1, ts: now, kind: "run.started", payload: ["runId": .string("run_1")]),
            signingKey: agentSigningKey
        )
        let newer = try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(id: "evt_2", seq: 2, ts: now, kind: "run.completed", payload: ["runId": .string("run_1")]),
            signingKey: agentSigningKey
        )
        let forged = RemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(id: "evt_forged", seq: 3, ts: now, kind: "run.failed", payload: ["runId": .string("run_1")]),
            signature: Data("not a real signature".utf8).base64EncodedString()
        )
        let client = MockiOSClient(macs: [mac], events: ["mac_1": [older, newer, forged]], serverNow: now)

        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)
        let stream = await client.stream(macId: "mac_1", since: 1)
        var ids: [String] = []
        for await envelope in stream {
            ids.append(envelope.event.id)
        }

        XCTAssertEqual(ids, ["evt_2"])
    }

    func testMockClientVerifiesTrustedDeviceSignatureAndReplay() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let signingKey = Curve25519.Signing.PrivateKey()
        let sealingKey = Curve25519.KeyAgreement.PrivateKey()
        let trusted = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            deviceSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(sealingKey.publicKey),
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now,
            validUntil: now.addingTimeInterval(3600),
            capabilities: [.stopRun]
        )
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "agent-sign",
            agentSealingPubkey: "agent-seal"
        )
        let client = MockiOSClient(macs: [mac], trustedDevices: [trusted], serverNow: now)
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let payload = RemoteCommandPayload.light(["runId": .string("run_1")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: now,
            kind: .stopRun,
            payload: payload,
            signingKey: signingKey
        )
        let command = RemoteCommand(requestId: "req_1", kind: .stopRun, payload: payload, assertion: assertion)

        let accepted = try await client.send(command)
        XCTAssertTrue(accepted.accepted)
        XCTAssertEqual(accepted.outcome, .accepted)

        let replay = try await client.send(command)
        XCTAssertFalse(replay.accepted)
        XCTAssertEqual(replay.reason, .replayedRequestId)
        XCTAssertEqual(replay.outcome, .duplicate)
    }

    func testMockClientRejectsSkewAndReturnsServerTime() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let signingKey = Curve25519.Signing.PrivateKey()
        let trusted = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            deviceSealingPubkey: "sealing",
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now,
            validUntil: now.addingTimeInterval(3600),
            capabilities: [.stopRun]
        )
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "agent-sign",
            agentSealingPubkey: "agent-seal"
        )
        let client = MockiOSClient(macs: [mac], trustedDevices: [trusted], serverNow: now)
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let payload = RemoteCommandPayload.light(["runId": .string("run_1")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_skew",
            timestamp: now.addingTimeInterval(120),
            kind: .stopRun,
            payload: payload,
            signingKey: signingKey
        )
        let command = RemoteCommand(requestId: "req_skew", kind: .stopRun, payload: payload, assertion: assertion)

        let ack = try await client.send(command)
        XCTAssertFalse(ack.accepted)
        XCTAssertEqual(ack.reason, .clockSkew)
        XCTAssertEqual(ack.serverTime, now)
    }

    func testMockClientAcceptsOnlySealedStartRunPayload() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let signingKey = Curve25519.Signing.PrivateKey()
        let agentSealingKey = Curve25519.KeyAgreement.PrivateKey()
        let trusted = TrustedDevice(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            deviceSealingPubkey: "device-seal",
            accountId: "acct_1",
            macAgentId: "mac_1",
            pairedAt: now,
            validUntil: now.addingTimeInterval(3600),
            capabilities: [.startRun]
        )
        let mac = MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio",
            agentSigningPubkey: "agent-sign",
            agentSealingPubkey: RemoteCrypto.sealingPublicKeyBase64(agentSealingKey.publicKey)
        )
        let client = MockiOSClient(macs: [mac], trustedDevices: [trusted], serverNow: now)
        try await client.connect(account: RemoteAccountSession(accountId: "acct_1", provider: .apple), mode: .cloudRelay)

        let blob = try RemoteCrypto.seal(
            Data(#"{"prompt":"sealed"}"#.utf8),
            to: mac.agentSealingPubkey,
            sealedForKeyId: "agent_seal_1",
            contentType: "application/json"
        )
        let payload = RemoteCommandPayload.sealed(blob)
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_start",
            timestamp: now,
            kind: .startRun,
            payload: payload,
            signingKey: signingKey
        )
        let command = RemoteCommand(requestId: "req_start", kind: .startRun, payload: payload, assertion: assertion)

        let ack = try await client.send(command)
        XCTAssertTrue(ack.accepted)
    }
}
