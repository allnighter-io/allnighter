import CryptoKit
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class DirectModeRemoteClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_400_000)

    func testClientPostsCommandToLoopbackServerAndVerifiesSignedAck() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let handler = RecordingDirectModeClientHandler(envelope: try Self.ackEnvelope(
            requestId: "req_1",
            now: now,
            macSigningKey: macSigningKey
        ))
        let server = DirectModeCommandServer(handler: handler)
        let port = try server.start()
        defer { server.stop() }
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModeRemoteClient(
            mac: Self.mac(signingKey: macSigningKey),
            endpoint: endpoint,
            now: { fixedNow }
        )
        try await client.connect(account: Self.account, mode: .loopback)

        let ack = try await client.send(Self.command(requestId: "req_1", now: now))

        XCTAssertEqual(ack.requestId, "req_1")
        XCTAssertTrue(ack.accepted)
        XCTAssertTrue(try RemoteCrypto.verifyCommandAck(
            ack,
            macAgentId: "mac_1",
            signingPublicKeyBase64: RemoteCrypto.signingPublicKeyBase64(macSigningKey.publicKey)
        ))
        let entries = handler.entries
        XCTAssertEqual(entries.map(\.requestId), ["req_1"])
        XCTAssertEqual(entries.first?.accountId, "acct_1")
        XCTAssertEqual(entries.first?.macAgentId, "mac_1")
        XCTAssertEqual(entries.first?.fromDeviceId, "device_1")

        let diagnosis = await client.diagnose()
        XCTAssertEqual(diagnosis.rungs.first(where: { $0.rung == .macReachable })?.ok, true)
        XCTAssertEqual(diagnosis.rungs.first(where: { $0.rung == .deviceApproved })?.ok, true)
    }

    func testClientFetchesSnapshotFromLoopbackServer() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let snapshotHandler = RecordingDirectModeClientSnapshotHandler(snapshot: Self.snapshot(now: now))
        let server = DirectModeCommandServer(
            handler: RecordingDirectModeClientHandler(envelope: try Self.ackEnvelope(
                requestId: "req_unused",
                now: now,
                macSigningKey: macSigningKey
            )),
            snapshotHandler: snapshotHandler
        )
        let port = try server.start()
        defer { server.stop() }
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModeRemoteClient(
            mac: Self.mac(signingKey: macSigningKey),
            endpoint: endpoint,
            now: { fixedNow }
        )
        try await client.connect(account: Self.account, mode: .loopback)

        let snapshot = try await client.snapshot(macId: "mac_1", since: 12)

        XCTAssertEqual(snapshot.runs.map(\.id), ["run_1"])
        XCTAssertEqual(snapshot.lastSeq, 42)
        let requests = snapshotHandler.requests
        XCTAssertEqual(requests, [
            DirectModeSnapshotRequest(accountId: "acct_1", macAgentId: "mac_1", since: 12),
        ])
    }

    func testClientFetchesSealedMediaFromLoopbackServer() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let mediaHandler = RecordingDirectModeClientMediaHandler(response: DirectModeMediaResponse(
            ref: "media_1",
            data: Data("ciphertext".utf8)
        ))
        let server = DirectModeCommandServer(
            handler: RecordingDirectModeClientHandler(envelope: try Self.ackEnvelope(
                requestId: "req_unused",
                now: now,
                macSigningKey: macSigningKey
            )),
            mediaHandler: mediaHandler
        )
        let port = try server.start()
        defer { server.stop() }
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModeRemoteClient(
            mac: Self.mac(signingKey: macSigningKey),
            endpoint: endpoint,
            now: { fixedNow }
        )
        try await client.connect(account: Self.account, mode: .loopback)
        let ref = MediaRef(
            ref: "media_1",
            macAgentId: "mac_1",
            r2Key: "direct/media_1",
            contentType: "image/png",
            expiresAt: now.addingTimeInterval(60)
        )

        let data = try await client.fetchSealed(ref)

        XCTAssertEqual(data, Data("ciphertext".utf8))
        XCTAssertEqual(mediaHandler.requests, [
            DirectModeMediaRequest(
                accountId: "acct_1",
                macAgentId: "mac_1",
                ref: "media_1",
                checkedAt: now
            ),
        ])
    }

    func testClientRejectsBadAckSignature() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let otherSigningKey = Curve25519.Signing.PrivateKey()
        let fixedNow = now
        let handler = RecordingDirectModeClientHandler(envelope: try Self.ackEnvelope(
            requestId: "req_bad_sig",
            now: now,
            macSigningKey: otherSigningKey
        ))
        let server = DirectModeCommandServer(handler: handler)
        let port = try server.start()
        defer { server.stop() }
        let endpoint = try LoopbackExposureProvider()
            .plan(DirectModeExposureRequest(loopbackPort: port, transport: .loopback))
            .endpoint
        let client = DirectModeRemoteClient(
            mac: Self.mac(signingKey: macSigningKey),
            endpoint: endpoint,
            now: { fixedNow }
        )
        try await client.connect(account: Self.account, mode: .loopback)

        do {
            _ = try await client.send(Self.command(requestId: "req_bad_sig", now: now))
            XCTFail("bad Mac ack signature should be rejected")
        } catch let error as DirectModeRemoteClientError {
            XCTAssertEqual(error, .badAckSignature)
        }
    }

    func testClientRejectsWrongConnectionMode() async throws {
        let macSigningKey = Curve25519.Signing.PrivateKey()
        let endpoint = DirectModeEndpoint(
            baseURL: "http://127.0.0.1:1234",
            commandURL: "http://127.0.0.1:1234/remote/command",
            transport: .loopback,
            atsExceptionRequired: false
        )
        let client = DirectModeRemoteClient(mac: Self.mac(signingKey: macSigningKey), endpoint: endpoint)

        do {
            try await client.connect(account: Self.account, mode: .tailscaleDirect)
            XCTFail("loopback endpoint should require loopback mode")
        } catch let error as DirectModeRemoteClientError {
            XCTAssertEqual(error, .unsupportedMode(.tailscaleDirect))
        }
    }

    private static let account = RemoteAccountSession(accountId: "acct_1", provider: .apple)

    private static func mac(signingKey: Curve25519.Signing.PrivateKey) -> MacAgentRef {
        MacAgentRef(
            macAgentId: "mac_1",
            displayName: "Studio Mac",
            agentSigningPubkey: RemoteCrypto.signingPublicKeyBase64(signingKey.publicKey),
            agentSealingPubkey: "seal"
        )
    }

    private static func command(requestId: String, now: Date) throws -> RemoteCommand {
        let deviceSigningKey = Curve25519.Signing.PrivateKey()
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

    private static func ackEnvelope(
        requestId: String,
        now: Date,
        macSigningKey: Curve25519.Signing.PrivateKey
    ) throws -> RemoteCommandAckEnvelope {
        let ack = try RemoteCrypto.makeCommandAck(
            macAgentId: "mac_1",
            requestId: requestId,
            accepted: true,
            outcome: .accepted,
            serverTime: now,
            signingKey: macSigningKey
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

    private static func snapshot(now: Date) -> SnapshotEnvelope {
        SnapshotEnvelope(
            runs: [
                TeamRunLight(
                    id: "run_1",
                    status: .running,
                    origin: .ios,
                    promptExcerpt: "",
                    teamDisplayName: "Remote Team",
                    createdAt: now
                ),
            ],
            lastSeq: 42,
            serverTime: now
        )
    }
}

private final class RecordingDirectModeClientHandler: DirectModeCommandHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let envelope: RemoteCommandAckEnvelope
    private var storedEntries: [RemoteCommandInboxEntry] = []

    init(envelope: RemoteCommandAckEnvelope) {
        self.envelope = envelope
    }

    var entries: [RemoteCommandInboxEntry] {
        lock.withLock { storedEntries }
    }

    func handle(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandAckEnvelope {
        lock.withLock { storedEntries.append(entry) }
        return envelope
    }
}

private final class RecordingDirectModeClientSnapshotHandler: DirectModeSnapshotHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let storedSnapshot: SnapshotEnvelope
    private var storedRequests: [DirectModeSnapshotRequest] = []

    init(snapshot: SnapshotEnvelope) {
        self.storedSnapshot = snapshot
    }

    var requests: [DirectModeSnapshotRequest] {
        lock.withLock { storedRequests }
    }

    func snapshot(_ request: DirectModeSnapshotRequest) async throws -> SnapshotEnvelope {
        lock.withLock { storedRequests.append(request) }
        return storedSnapshot
    }
}

private final class RecordingDirectModeClientMediaHandler: DirectModeMediaHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let storedResponse: DirectModeMediaResponse
    private var storedRequests: [DirectModeMediaRequest] = []

    init(response: DirectModeMediaResponse) {
        self.storedResponse = response
    }

    var requests: [DirectModeMediaRequest] {
        lock.withLock { storedRequests }
    }

    func media(_ request: DirectModeMediaRequest) async throws -> DirectModeMediaResponse {
        lock.withLock { storedRequests.append(request) }
        return storedResponse
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
