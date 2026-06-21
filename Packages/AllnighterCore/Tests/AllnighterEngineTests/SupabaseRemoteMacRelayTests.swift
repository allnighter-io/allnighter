import CryptoKit
import Foundation
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class SupabaseRemoteMacRelayTests: XCTestCase {
    private let supabaseURL = URL(string: "https://example.supabase.co")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testSubmitCommandWritesPostgRESTRowWithSignedTimestamp() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
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
        let entry = RemoteCommandInboxEntry(
            requestId: "req_1",
            accountId: "acct_1",
            macAgentId: "mac_1",
            fromDeviceId: "device_1",
            command: command,
            createdAt: now.addingTimeInterval(15)
        )
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 201, data: Data())
        ])
        let relay = try makeRelay(transport: transport)

        try await relay.submitCommand(entry)

        let recordedRequests = await transport.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/rest/v1/command_inbox")
        XCTAssertEqual(queryValue("on_conflict", in: request.url), "account_id,mac_agent_id,request_id")
        XCTAssertEqual(request.headers["apikey"], "publishable")
        XCTAssertEqual(request.headers["Authorization"], "Bearer jwt")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Prefer"], "resolution=ignore-duplicates,return=minimal")

        let row = try XCTUnwrap(bodyRows(from: request).first)
        XCTAssertEqual(row["request_id"] as? String, "req_1")
        XCTAssertEqual(row["account_id"] as? String, "acct_1")
        XCTAssertEqual(row["mac_agent_id"] as? String, "mac_1")
        XCTAssertEqual(row["from_device_id"] as? String, "device_1")
        XCTAssertEqual(row["kind"] as? String, "stopRun")
        XCTAssertEqual(row["signature"] as? String, assertion.signature)
        XCTAssertEqual(row["created_at"] as? String, iso(now))
        XCTAssertEqual(row["status"] as? String, "pending")

        let payloadRow = try XCTUnwrap(row["payload"] as? [String: Any])
        XCTAssertEqual(payloadRow["kind"] as? String, "lightJSON")
        let lightPayload = try XCTUnwrap(payloadRow["light_payload"] as? [String: Any])
        XCTAssertEqual(lightPayload["runId"] as? String, "run_1")
    }

    func testPendingCommandsReconstructVerifiableDeviceAssertion() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let payload = RemoteCommandPayload.light(["runId": .string("run_1")])
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: "device_1",
            requestId: "req_1",
            timestamp: now,
            kind: .stopRun,
            payload: payload,
            signingKey: signingKey
        )
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 200, data: try jsonData([commandInboxRow(assertion: assertion)]))
        ])
        let relay = try makeRelay(transport: transport)

        let entries = try await relay.pendingCommands(accountId: "acct_1", macAgentId: "mac_1", limit: 10)

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.accountId, "acct_1")
        XCTAssertEqual(entry.macAgentId, "mac_1")
        XCTAssertEqual(entry.fromDeviceId, "device_1")
        XCTAssertEqual(entry.command.kind, .stopRun)
        XCTAssertEqual(entry.command.assertion.method, RemoteProtocol.commandMethod)
        XCTAssertEqual(entry.command.assertion.protocolMajor, RemoteProtocol.currentMajor)
        XCTAssertEqual(entry.command.assertion.payloadSHA256, try RemoteCrypto.payloadDigest(payload))
        XCTAssertTrue(try RemoteCrypto.verifyDeviceAssertion(
            entry.command.assertion,
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))

        let recordedRequests = await transport.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.path, "/rest/v1/command_inbox")
        XCTAssertEqual(queryValue("account_id", in: request.url), "eq.acct_1")
        XCTAssertEqual(queryValue("mac_agent_id", in: request.url), "eq.mac_1")
        XCTAssertEqual(queryValue("status", in: request.url), "eq.pending")
        XCTAssertEqual(queryValue("limit", in: request.url), "10")
    }

    func testAcknowledgeWritesSignedAckServerTimeAndMarksInboxAcked() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let signedServerTime = now
        let envelopeCreatedAt = now.addingTimeInterval(30)
        let ack = try RemoteCrypto.makeCommandAck(
            macAgentId: "mac_1",
            requestId: "req_1",
            accepted: true,
            outcome: .accepted,
            serverTime: signedServerTime,
            signingKey: macSigningKey
        )
        let envelope = RemoteCommandAckEnvelope(
            requestId: "req_1",
            accountId: "acct_1",
            macAgentId: "mac_1",
            ack: ack,
            auditEvent: RemoteAuditEvent(
                ts: signedServerTime,
                deviceId: "device_1",
                commandKind: .stopAll,
                requestId: "req_1",
                targetSummary: "stopAll terminated=1",
                outcome: .accepted
            ),
            createdAt: envelopeCreatedAt
        )
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 201, data: Data()),
            SupabaseHTTPResponse(statusCode: 204, data: Data()),
        ])
        let relay = try makeRelay(transport: transport)

        try await relay.acknowledge(envelope)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        let ackRequest = requests[0]
        XCTAssertEqual(ackRequest.method, "POST")
        XCTAssertEqual(ackRequest.url.path, "/rest/v1/command_acks")
        XCTAssertEqual(ackRequest.headers["Prefer"], "resolution=ignore-duplicates,return=minimal")
        let ackRow = try XCTUnwrap(bodyRows(from: ackRequest).first)
        XCTAssertEqual(ackRow["sig"] as? String, ack.signature)
        XCTAssertEqual(ackRow["server_time"] as? String, iso(signedServerTime))
        XCTAssertEqual(ackRow["created_at"] as? String, iso(envelopeCreatedAt))
        XCTAssertEqual(ackRow["audit_ts"] as? String, iso(signedServerTime))
        XCTAssertEqual(ackRow["audit_device_id"] as? String, "device_1")
        XCTAssertEqual(ackRow["audit_command_kind"] as? String, "stopAll")
        XCTAssertEqual(ackRow["audit_target_summary"] as? String, "stopAll terminated=1")

        let patchRequest = requests[1]
        XCTAssertEqual(patchRequest.method, "PATCH")
        XCTAssertEqual(patchRequest.url.path, "/rest/v1/command_inbox")
        XCTAssertEqual(queryValue("account_id", in: patchRequest.url), "eq.acct_1")
        XCTAssertEqual(queryValue("mac_agent_id", in: patchRequest.url), "eq.mac_1")
        XCTAssertEqual(queryValue("request_id", in: patchRequest.url), "eq.req_1")
        let patchBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(patchRequest.body)) as? [String: Any])
        XCTAssertEqual(patchBody["status"] as? String, "acked")
    }

    func testCommandAckReadsCompleteVerifiableAckRow() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let ack = try RemoteCrypto.makeCommandAck(
            macAgentId: "mac_1",
            requestId: "req_1",
            accepted: true,
            outcome: .accepted,
            serverTime: now,
            signingKey: macSigningKey
        )
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 200, data: try jsonData([commandAckRow(ack: ack)])),
        ])
        let relay = try makeRelay(transport: transport)

        let fetchedEnvelope = try await relay.commandAck(
            accountId: "acct_1",
            macAgentId: "mac_1",
            requestId: "req_1"
        )
        let envelope = try XCTUnwrap(fetchedEnvelope)

        XCTAssertEqual(envelope.requestId, "req_1")
        XCTAssertEqual(envelope.accountId, "acct_1")
        XCTAssertEqual(envelope.macAgentId, "mac_1")
        XCTAssertEqual(envelope.createdAt, now)
        XCTAssertEqual(envelope.auditEvent.deviceId, "device_1")
        XCTAssertEqual(envelope.auditEvent.commandKind, .stopRun)
        XCTAssertEqual(envelope.auditEvent.targetSummary, "stopRun run_1")
        XCTAssertTrue(try RemoteCrypto.verifyCommandAck(
            envelope.ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        ))

        let recordedRequests = await transport.recordedRequests()
        XCTAssertEqual(recordedRequests.count, 1)
        XCTAssertEqual(recordedRequests.first?.url.path, "/rest/v1/command_acks")
    }

    func testCommandAckPreservesNilSignedServerTime() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let ack = try RemoteCrypto.makeCommandAck(
            macAgentId: "mac_1",
            requestId: "req_1",
            accepted: false,
            reason: .badSignature,
            outcome: .rejected,
            serverTime: nil,
            signingKey: macSigningKey
        )
        let rowCreatedAt = now.addingTimeInterval(12)
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 200, data: try jsonData([
                commandAckRow(
                    ack: ack,
                    createdAt: rowCreatedAt,
                    auditTs: rowCreatedAt,
                    auditCommandKind: .startRun,
                    auditTargetSummary: "startRun rejected"
                )
            ])),
        ])
        let relay = try makeRelay(transport: transport)

        let fetchedEnvelope = try await relay.commandAck(
            accountId: "acct_1",
            macAgentId: "mac_1",
            requestId: "req_1"
        )
        let envelope = try XCTUnwrap(fetchedEnvelope)

        XCTAssertNil(envelope.ack.serverTime)
        XCTAssertEqual(envelope.createdAt, rowCreatedAt)
        XCTAssertEqual(envelope.auditEvent.targetSummary, "startRun rejected")
        XCTAssertTrue(try RemoteCrypto.verifyCommandAck(
            envelope.ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        ))
    }

    func testPublishEventsWritesAndReadsFullSealedMediaRef() async throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let sealedRef = mediaRef()
        let envelope = try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(
                id: "evt_1",
                seq: 1,
                ts: now,
                kind: "run.started",
                payload: ["runId": .string("run_1"), "prompt": .string("sensitive")]
            ),
            sealedRef: sealedRef,
            signingKey: signingKey
        )
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 201, data: Data()),
            SupabaseHTTPResponse(statusCode: 200, data: try jsonData([try eventEnvelopeRow(envelope)])),
        ])
        let relay = try makeRelay(transport: transport)

        try await relay.publishEvents(accountId: "acct_1", macAgentId: "mac_1", events: [envelope])
        let fetched = try await relay.runEvents(accountId: "acct_1", macAgentId: "mac_1", after: 0, limit: 10)

        let requests = await transport.recordedRequests()
        let publishRequest = try XCTUnwrap(requests.first)
        let row = try XCTUnwrap(bodyRows(from: publishRequest).first)
        let persistedRef = try XCTUnwrap(row["sealed_ref"] as? [String: Any])
        XCTAssertEqual(persistedRef["ref"] as? String, "media_1")
        XCTAssertEqual(persistedRef["mac_agent_id"] as? String, "mac_1")
        XCTAssertEqual(fetched.first?.sealedRef, sealedRef)
        XCTAssertTrue(try RemoteCrypto.verifyRemoteRunEventEnvelope(
            try XCTUnwrap(fetched.first),
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey)
        ))
    }

    func testPublishEventsRejectsMismatchedMacScopeBeforeWriting() async throws {
        let transport = RecordingSupabaseHTTPTransport(responses: [])
        let relay = try makeRelay(transport: transport)
        let wrongMacEvent = RemoteRunEventEnvelope(
            macAgentId: "mac_2",
            event: RunEvent(
                id: "evt_wrong_mac",
                seq: 1,
                ts: now,
                kind: "run.started",
                payload: ["runId": .string("run_1")]
            ),
            signature: "sig"
        )

        do {
            try await relay.publishEvents(accountId: "acct_1", macAgentId: "mac_1", events: [wrongMacEvent])
            XCTFail("expected event scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .eventScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    eventId: "evt_wrong_mac"
                )
            )
        }

        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testPublishMediaRejectsMismatchedKeyScopeBeforeWriting() async throws {
        let transport = RecordingSupabaseHTTPTransport(responses: [])
        let relay = try makeRelay(transport: transport)
        let wrongMacKey = mediaKey(macAgentId: "mac_2")

        do {
            try await relay.publishMedia(ref: mediaRef(), data: Data("ciphertext".utf8), keys: [wrongMacKey])
            XCTFail("expected media scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .mediaScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    expectedRef: "media_1",
                    actualRef: "media_1"
                )
            )
        }

        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testUpsertMediaKeyRejectsMismatchedMacScopeBeforeWriting() async throws {
        let transport = RecordingSupabaseHTTPTransport(responses: [])
        let relay = try makeRelay(transport: transport)
        let wrongMacKey = mediaKey(macAgentId: "mac_2")

        do {
            try await relay.upsertMediaKey(wrongMacKey, macAgentId: "mac_1")
            XCTFail("expected media scope mismatch")
        } catch let error as RemoteMacRelayError {
            XCTAssertEqual(
                error,
                .mediaScopeMismatch(
                    expectedMacAgentId: "mac_1",
                    actualMacAgentId: "mac_2",
                    expectedRef: "media_1",
                    actualRef: "media_1"
                )
            )
        }

        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testPublishSnapshotWritesSnapshotEnvelopeRow() async throws {
        let fixedNow = now.addingTimeInterval(60)
        let snapshot = snapshotEnvelope()
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 201, data: Data())
        ])
        let relay = try makeRelay(transport: transport, now: { fixedNow })

        try await relay.publishSnapshot(accountId: "acct_1", macAgentId: "mac_1", snapshot: snapshot)

        let recordedRequests = await transport.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/rest/v1/snapshot_envelopes")
        XCTAssertEqual(queryValue("on_conflict", in: request.url), "account_id,mac_agent_id")
        XCTAssertEqual(request.headers["Prefer"], "resolution=merge-duplicates,return=minimal")

        let row = try XCTUnwrap(bodyRows(from: request).first)
        XCTAssertEqual(row["account_id"] as? String, "acct_1")
        XCTAssertEqual(row["mac_agent_id"] as? String, "mac_1")
        XCTAssertEqual(row["last_seq"] as? Int, 7)
        XCTAssertEqual(row["server_time"] as? String, iso(now))
        XCTAssertEqual(row["protocol_version"] as? Int, RemoteProtocol.currentMajor)
        XCTAssertEqual(row["updated_at"] as? String, iso(fixedNow))
        let runs = try XCTUnwrap(row["runs"] as? [[String: Any]])
        XCTAssertEqual(runs.first?["id"] as? String, "run_1")
        XCTAssertEqual(runs.first?["team_display_name"] as? String, "Default Team")
    }

    func testSnapshotReadsStoredEnvelope() async throws {
        let snapshot = snapshotEnvelope()
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 200, data: try jsonData([snapshotEnvelopeRow(snapshot)]))
        ])
        let relay = try makeRelay(transport: transport)

        let fetched = try await relay.snapshot(accountId: "acct_1", macAgentId: "mac_1", since: 7)

        XCTAssertEqual(fetched, snapshot)
        let recordedRequests = await transport.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.path, "/rest/v1/snapshot_envelopes")
        XCTAssertEqual(queryValue("account_id", in: request.url), "eq.acct_1")
        XCTAssertEqual(queryValue("mac_agent_id", in: request.url), "eq.mac_1")
        XCTAssertEqual(queryValue("limit", in: request.url), "1")
    }

    func testRunEventStreamDoesNotOpenRealtimeWhenBackfillFails() async throws {
        let transport = RecordingSupabaseHTTPTransport(responses: [
            SupabaseHTTPResponse(statusCode: 500, data: Data("backfill unavailable".utf8))
        ])
        let realtimeConnector = RecordingRelayRealtimeConnector()
        let relay = try makeRelay(transport: transport, realtimeConnector: realtimeConnector)

        var events: [RemoteRunEventEnvelope] = []
        let stream = await relay.runEventStream(
            accountId: "acct_1",
            macAgentId: "mac_1",
            after: 0,
            limit: 10
        )
        for await event in stream {
            events.append(event)
        }

        XCTAssertTrue(events.isEmpty)
        let requests = await realtimeConnector.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testLiveSupabaseRLSIsolatesAccountMacScopesWhenConfigured() async throws {
        let config = try LiveSupabaseRLSConfig.loadOrSkip()
        let accountARelay = try SupabaseRemoteMacRelay(
            supabaseURL: config.url,
            publishableKey: config.publishableKey,
            tokenProvider: StaticSupabaseAccessTokenProvider(token: config.accountAJWT)
        )
        let accountBRelay = try SupabaseRemoteMacRelay(
            supabaseURL: config.url,
            publishableKey: config.publishableKey,
            tokenProvider: StaticSupabaseAccessTokenProvider(token: config.accountBJWT)
        )

        let accountAMacs = try await accountARelay.macAgents(accountId: config.accountAId)
        XCTAssertTrue(
            accountAMacs.contains { $0.macAgentId == config.macAId },
            "RLS fixture is missing account A mac \(config.macAId)"
        )

        let accountBReadingAccountA = try await accountBRelay.macAgents(accountId: config.accountAId)
        XCTAssertFalse(accountBReadingAccountA.contains { $0.macAgentId == config.macAId })

        let signingKey = Curve25519.Signing.PrivateKey()
        let payload = RemoteCommandPayload.empty
        let assertion = try RemoteCrypto.makeDeviceAssertion(
            deviceId: config.deviceAId,
            requestId: "rls_probe_\(UUID().uuidString)",
            timestamp: Date(),
            kind: .stopAll,
            payload: payload,
            signingKey: signingKey
        )
        let command = RemoteCommand(
            requestId: assertion.requestId,
            kind: .stopAll,
            payload: payload,
            assertion: assertion
        )
        let entry = RemoteCommandInboxEntry(
            requestId: assertion.requestId,
            accountId: config.accountAId,
            macAgentId: config.macAId,
            fromDeviceId: config.deviceAId,
            command: command,
            createdAt: assertion.timestamp
        )

        do {
            try await accountBRelay.submitCommand(entry)
            XCTFail("account B must not be able to write account A's command inbox")
        } catch let error as SupabaseRemoteMacRelayError {
            guard case .http(let statusCode, _) = error else {
                XCTFail("expected PostgREST HTTP denial, got \(error)")
                return
            }
            XCTAssertTrue((400..<500).contains(statusCode), "expected RLS/client denial, got \(statusCode)")
        }
    }

    private func makeRelay(
        transport: RecordingSupabaseHTTPTransport,
        realtimeConnector: any SupabaseRealtimeConnecting = RecordingRelayRealtimeConnector(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws -> SupabaseRemoteMacRelay {
        try SupabaseRemoteMacRelay(
            supabaseURL: supabaseURL,
            publishableKey: "publishable",
            tokenProvider: StaticSupabaseAccessTokenProvider(token: "jwt"),
            transport: transport,
            realtimeConnector: realtimeConnector,
            now: now
        )
    }

    private func commandInboxRow(assertion: DeviceAssertion) -> [String: Any] {
        [
            "request_id": assertion.requestId,
            "account_id": "acct_1",
            "mac_agent_id": "mac_1",
            "from_device_id": assertion.deviceId,
            "kind": assertion.kind.rawValue,
            "payload": [
                "kind": "lightJSON",
                "light_payload": [
                    "runId": "run_1",
                ],
            ],
            "signature": assertion.signature,
            "created_at": iso(assertion.timestamp),
            "status": "pending",
        ]
    }

    private func commandAckRow(
        ack: CommandAck,
        createdAt: Date? = nil,
        auditTs: Date? = nil,
        auditCommandKind: RemoteCommandKind = .stopRun,
        auditTargetSummary: String = "stopRun run_1"
    ) throws -> [String: Any] {
        let rowCreatedAt = createdAt ?? ack.serverTime ?? now
        let rowAuditTs = auditTs ?? ack.serverTime ?? rowCreatedAt
        return [
            "request_id": ack.requestId,
            "account_id": "acct_1",
            "mac_agent_id": "mac_1",
            "accepted": ack.accepted,
            "reason": ack.reason?.rawValue ?? NSNull(),
            "outcome": ack.outcome.rawValue,
            "server_time": ack.serverTime.map(iso(_:)) ?? NSNull(),
            "audit_ts": iso(rowAuditTs),
            "audit_device_id": "device_1",
            "audit_command_kind": auditCommandKind.rawValue,
            "audit_target_summary": auditTargetSummary,
            "sig": ack.signature,
            "created_at": iso(rowCreatedAt),
        ]
    }

    private func eventEnvelopeRow(_ envelope: RemoteRunEventEnvelope) throws -> [String: Any] {
        [
            "id": envelope.event.id,
            "seq": envelope.event.seq,
            "ts": iso(envelope.event.ts),
            "account_id": "acct_1",
            "mac_agent_id": envelope.macAgentId,
            "run_id": envelope.event.payload["runId"]?.stringValue ?? NSNull(),
            "kind": envelope.event.kind,
            "light_payload": try jsonObject(envelope.event.payload),
            "sealed_ref": envelope.sealedRef.map(mediaRefRow(_:)) ?? NSNull(),
            "sig": envelope.signature,
        ]
    }

    private func snapshotEnvelope() -> SnapshotEnvelope {
        SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .running,
                    origin: .ios,
                    promptExcerpt: "Build the thing",
                    teamDisplayName: "Default Team",
                    createdAt: now
                ),
            ],
            lastSeq: 7,
            serverTime: now
        )
    }

    private func snapshotEnvelopeRow(_ snapshot: SnapshotEnvelope) -> [String: Any] {
        [
            "account_id": "acct_1",
            "mac_agent_id": "mac_1",
            "runs": snapshot.runs.map(teamRunLightRow(_:)),
            "last_seq": snapshot.lastSeq,
            "server_time": iso(snapshot.serverTime),
            "protocol_version": snapshot.protocolVersion,
            "updated_at": iso(now.addingTimeInterval(5)),
        ]
    }

    private func teamRunLightRow(_ run: TeamRunLight) -> [String: Any] {
        [
            "id": run.id,
            "status": run.status.rawValue,
            "origin": run.origin.rawValue,
            "prompt_excerpt": run.promptExcerpt,
            "team_display_name": run.teamDisplayName ?? NSNull(),
            "created_at": iso(run.createdAt),
            "completed_at": run.completedAt.map(iso(_:)) ?? NSNull(),
        ]
    }

    private func mediaRef() -> MediaRef {
        MediaRef(
            ref: "media_1",
            macAgentId: "mac_1",
            r2Key: "r2/media_1",
            contentType: "image/png",
            expiresAt: now.addingTimeInterval(3600)
        )
    }

    private func mediaRefRow(_ ref: MediaRef) -> [String: Any] {
        [
            "ref": ref.ref,
            "mac_agent_id": ref.macAgentId,
            "r2_key": ref.r2Key,
            "content_type": ref.contentType,
            "expires_at": iso(ref.expiresAt),
        ]
    }

    private func mediaKey(
        ref: String = "media_1",
        macAgentId: String = "mac_1",
        deviceId: String = "device_1"
    ) -> MediaKeyEnvelope {
        MediaKeyEnvelope(
            ref: ref,
            macAgentId: macAgentId,
            deviceId: deviceId,
            sealedKey: SealedBlob(
                ciphertext: Data("sealed-key-\(deviceId)".utf8),
                encapsulatedKey: Data("encapsulated".utf8),
                sealedForKeyId: deviceId,
                contentType: RemoteMediaCrypto.mediaKeyContentType
            )
        )
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: try SupabaseJSON.encode(value))
    }

    private func bodyRows(from request: SupabaseHTTPRequest) throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [[String: Any]])
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private actor RecordingSupabaseHTTPTransport: SupabaseHTTPTransport {
    private var requests: [SupabaseHTTPRequest] = []
    private var responses: [SupabaseHTTPResponse]

    init(responses: [SupabaseHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: SupabaseHTTPRequest) async throws -> SupabaseHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            return SupabaseHTTPResponse(statusCode: 200, data: Data("[]".utf8))
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [SupabaseHTTPRequest] {
        requests
    }
}

private enum RelayRealtimeSocketError: Error {
    case endOfMessages
}

private actor RecordingRelayRealtimeSocket: SupabaseRealtimeSocket {
    private var sent: [String] = []

    func send(_ text: String) async throws {
        sent.append(text)
    }

    func receive() async throws -> SupabaseRealtimeSocketMessage {
        throw RelayRealtimeSocketError.endOfMessages
    }

    func close() async {}

    func sentMessages() -> [String] {
        sent
    }
}

private actor RecordingRelayRealtimeConnector: SupabaseRealtimeConnecting {
    private var requests: [SupabaseRealtimeConnectionRequest] = []
    private let socket = RecordingRelayRealtimeSocket()

    func connect(_ request: SupabaseRealtimeConnectionRequest) async throws -> any SupabaseRealtimeSocket {
        requests.append(request)
        return socket
    }

    func recordedRequests() -> [SupabaseRealtimeConnectionRequest] {
        requests
    }
}

private struct LiveSupabaseRLSConfig {
    var url: URL
    var publishableKey: String
    var accountAId: String
    var accountBJWT: String
    var accountAJWT: String
    var macAId: String
    var deviceAId: String

    static func loadOrSkip(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LiveSupabaseRLSConfig {
        let required = [
            "ALLNIGHTER_SUPABASE_URL",
            "ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY",
            "ALLNIGHTER_SUPABASE_RLS_ACCOUNT_A_ID",
            "ALLNIGHTER_SUPABASE_RLS_ACCOUNT_A_JWT",
            "ALLNIGHTER_SUPABASE_RLS_ACCOUNT_B_JWT",
            "ALLNIGHTER_SUPABASE_RLS_MAC_A_ID",
            "ALLNIGHTER_SUPABASE_RLS_DEVICE_A_ID",
        ]
        let missing = required.filter { environment[$0, default: ""].isEmpty }
        guard missing.isEmpty else {
            throw XCTSkip("Live Supabase RLS proof not configured; missing \(missing.joined(separator: ", "))")
        }
        guard let url = URL(string: environment["ALLNIGHTER_SUPABASE_URL"]!) else {
            throw XCTSkip("ALLNIGHTER_SUPABASE_URL is not a valid URL")
        }
        return LiveSupabaseRLSConfig(
            url: url,
            publishableKey: environment["ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY"]!,
            accountAId: environment["ALLNIGHTER_SUPABASE_RLS_ACCOUNT_A_ID"]!,
            accountBJWT: environment["ALLNIGHTER_SUPABASE_RLS_ACCOUNT_B_JWT"]!,
            accountAJWT: environment["ALLNIGHTER_SUPABASE_RLS_ACCOUNT_A_JWT"]!,
            macAId: environment["ALLNIGHTER_SUPABASE_RLS_MAC_A_ID"]!,
            deviceAId: environment["ALLNIGHTER_SUPABASE_RLS_DEVICE_A_ID"]!
        )
    }
}
