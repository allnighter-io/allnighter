import XCTest
import Darwin
import AllnighterCore
@testable import AllnighterEngine

final class DirectModeCommandServerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_300_000)

    func testHandlerRoutesThroughSharedRouterAndBuildsAckEnvelope() async throws {
        let router = RecordingDirectModeRouter(result: Self.routingResult(requestId: "req_1", now: now))
        let auditRecorder = RecordingDirectModeAuditRecorder()
        let fixedNow = now
        let handler = DirectModeCommandHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            router: router,
            auditRecorder: auditRecorder,
            now: { fixedNow }
        )
        let entry = Self.entry(requestId: "req_1")

        let envelope = try await handler.handle(entry)

        let entries = await router.recordedEntries()
        XCTAssertEqual(entries.map(\.requestId), ["req_1"])
        XCTAssertEqual(envelope.requestId, "req_1")
        XCTAssertEqual(envelope.accountId, "acct_1")
        XCTAssertEqual(envelope.macAgentId, "mac_1")
        XCTAssertEqual(envelope.ack.accepted, true)
        XCTAssertEqual(envelope.auditEvent.targetSummary, "stopAll terminated=1")
        XCTAssertEqual(envelope.createdAt, now)
        XCTAssertEqual(auditRecorder.envelopes.map(\.requestId), ["req_1"])
    }

    func testHandlerRejectsWrongAccountOrMacBeforeRouting() async throws {
        let router = RecordingDirectModeRouter(result: Self.routingResult(requestId: "req_1", now: now))
        let fixedNow = now
        let handler = DirectModeCommandHandler(
            accountId: "acct_1",
            macAgentId: "mac_1",
            router: router,
            now: { fixedNow }
        )
        let entry = Self.entry(requestId: "req_1", accountId: "acct_other", macAgentId: "mac_other")

        do {
            _ = try await handler.handle(entry)
            XCTFail("expected mismatch")
        } catch let error as DirectModeCommandError {
            XCTAssertEqual(error, .inboxEntryMismatch(
                requestId: "req_1",
                expectedAccountId: "acct_1",
                actualAccountId: "acct_other",
                expectedMacAgentId: "mac_1",
                actualMacAgentId: "mac_other"
            ))
        }
        let entries = await router.recordedEntries()
        XCTAssertEqual(entries.count, 0)
    }

    func testLoopbackCommandServerPostsCommandToHandler() throws {
        let handler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let server = DirectModeCommandServer(handler: handler)
        defer { server.stop() }
        let port = try server.start()
        let entry = Self.entry(requestId: "req_http")

        let result = try post(entry, port: port)

        XCTAssertEqual(result.statusCode, 200)
        let envelope = try CoreJSON.decode(RemoteCommandAckEnvelope.self, from: result.body)
        XCTAssertEqual(envelope.requestId, "req_http")
        XCTAssertEqual(envelope.ack.accepted, true)
        XCTAssertEqual(handler.entries.map(\.requestId), ["req_http"])
    }

    func testLoopbackCommandServerPostsPairingRequestToHandler() throws {
        let commandHandler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let pairingHandler = RecordingDirectModePairingHandler(response: Self.pairingResponse(now: now))
        let server = DirectModeCommandServer(handler: commandHandler, pairingHandler: pairingHandler)
        defer { server.stop() }
        let port = try server.start()
        let request = DirectModePairingSubmitRequest(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            pairingToken: "pair_token_1"
        )

        let result = try postPairing(request, port: port)

        XCTAssertEqual(result.statusCode, 200)
        let response = try CoreJSON.decode(DirectModePairingSubmitResponse.self, from: result.body)
        XCTAssertEqual(response.sessionId, "session_1")
        XCTAssertEqual(response.request.deviceId, "device_1")
        XCTAssertEqual(pairingHandler.requests.map(\.deviceId), ["device_1"])
        XCTAssertTrue(commandHandler.entries.isEmpty)
    }

    func testLoopbackCommandServerPostsSnapshotRequestToHandler() throws {
        let commandHandler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let snapshotHandler = RecordingDirectModeSnapshotHandler(snapshot: Self.snapshot(now: now))
        let server = DirectModeCommandServer(handler: commandHandler, snapshotHandler: snapshotHandler)
        defer { server.stop() }
        let port = try server.start()
        let request = DirectModeSnapshotRequest(accountId: "acct_1", macAgentId: "mac_1", since: 12)

        let result = try postSnapshot(request, port: port)

        XCTAssertEqual(result.statusCode, 200)
        let snapshot = try CoreJSON.decode(SnapshotEnvelope.self, from: result.body)
        XCTAssertEqual(snapshot.runs.map(\.id), ["run_1"])
        XCTAssertEqual(snapshot.lastSeq, 42)
        XCTAssertEqual(snapshotHandler.requests, [request])
        XCTAssertTrue(commandHandler.entries.isEmpty)
    }

    func testLoopbackCommandServerPostsMediaRequestToHandler() throws {
        let commandHandler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let mediaHandler = RecordingDirectModeMediaHandler(response: DirectModeMediaResponse(
            ref: "media_1",
            data: Data("ciphertext".utf8)
        ))
        let server = DirectModeCommandServer(handler: commandHandler, mediaHandler: mediaHandler)
        defer { server.stop() }
        let port = try server.start()
        let request = DirectModeMediaRequest(
            accountId: "acct_1",
            macAgentId: "mac_1",
            ref: "media_1",
            checkedAt: now
        )

        let result = try postMedia(request, port: port)

        XCTAssertEqual(result.statusCode, 200)
        let response = try CoreJSON.decode(DirectModeMediaResponse.self, from: result.body)
        XCTAssertEqual(response.data, Data("ciphertext".utf8))
        XCTAssertEqual(mediaHandler.requests, [request])
        XCTAssertTrue(commandHandler.entries.isEmpty)
    }

    func testLoopbackCommandServerPostsMediaKeyRequestToHandler() throws {
        let commandHandler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let key = Self.mediaKey(ref: "media_1", deviceId: "device_1")
        let mediaKeyHandler = RecordingDirectModeMediaKeyHandler(response: DirectModeMediaKeyResponse(key: key))
        let server = DirectModeCommandServer(handler: commandHandler, mediaKeyHandler: mediaKeyHandler)
        defer { server.stop() }
        let port = try server.start()
        let request = DirectModeMediaKeyRequest(
            accountId: "acct_1",
            macAgentId: "mac_1",
            ref: "media_1",
            deviceId: "device_1",
            checkedAt: now
        )

        let result = try postMediaKey(request, port: port)

        XCTAssertEqual(result.statusCode, 200)
        let response = try CoreJSON.decode(DirectModeMediaKeyResponse.self, from: result.body)
        XCTAssertEqual(response.key, key)
        XCTAssertEqual(mediaKeyHandler.requests, [request])
        XCTAssertTrue(commandHandler.entries.isEmpty)
    }

    func testLoopbackCommandServerPostsEventsRequestToHandler() throws {
        let commandHandler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let eventsHandler = RecordingDirectModeEventsHandler(response: DirectModeEventsResponse(events: [
            Self.eventEnvelope(id: "evt_1", seq: 1),
        ]))
        let server = DirectModeCommandServer(handler: commandHandler, eventsHandler: eventsHandler)
        defer { server.stop() }
        let port = try server.start()
        let request = DirectModeEventsRequest(accountId: "acct_1", macAgentId: "mac_1", afterSeq: 7, limit: 50)

        let result = try postEvents(request, port: port)

        XCTAssertEqual(result.statusCode, 200)
        let response = try CoreJSON.decode(DirectModeEventsResponse.self, from: result.body)
        XCTAssertEqual(response.events.map(\.event.id), ["evt_1"])
        XCTAssertEqual(eventsHandler.requests, [request])
        XCTAssertTrue(commandHandler.entries.isEmpty)
    }

    func testLoopbackCommandServerRejectsPairingPathWithoutPairingHandler() throws {
        let handler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let server = DirectModeCommandServer(handler: handler)
        defer { server.stop() }
        let port = try server.start()
        let request = DirectModePairingSubmitRequest(
            deviceId: "device_1",
            displayName: "Mike's iPhone",
            deviceSigningPubkey: "device_sign",
            deviceSealingPubkey: "device_seal",
            pairingToken: "pair_token_1"
        )

        let result = try postPairing(request, port: port)

        XCTAssertEqual(result.statusCode, 404)
        XCTAssertTrue(handler.entries.isEmpty)
    }

    func testLoopbackCommandServerRejectsNonCommandPath() throws {
        let handler = RecordingDirectModeHandler(envelope: Self.ackEnvelope(requestId: "req_http", now: now))
        let server = DirectModeCommandServer(handler: handler)
        defer { server.stop() }
        let port = try server.start()

        let result = try request(method: "POST", path: "/health", body: Data("{}".utf8), port: port)

        XCTAssertEqual(result.statusCode, 404)
        XCTAssertTrue(handler.entries.isEmpty)
    }

    private func post(_ entry: RemoteCommandInboxEntry, port: UInt16) throws -> HTTPResult {
        try request(
            method: "POST",
            path: DirectModeCommandServer.commandPath,
            body: CoreJSON.encode(entry),
            port: port
        )
    }

    private func postSnapshot(_ request: DirectModeSnapshotRequest, port: UInt16) throws -> HTTPResult {
        try self.request(
            method: "POST",
            path: DirectModeCommandServer.snapshotPath,
            body: CoreJSON.encode(request),
            port: port
        )
    }

    private func postMedia(_ request: DirectModeMediaRequest, port: UInt16) throws -> HTTPResult {
        try self.request(
            method: "POST",
            path: DirectModeCommandServer.mediaPath,
            body: CoreJSON.encode(request),
            port: port
        )
    }

    private func postMediaKey(_ request: DirectModeMediaKeyRequest, port: UInt16) throws -> HTTPResult {
        try self.request(
            method: "POST",
            path: DirectModeCommandServer.mediaKeyPath,
            body: CoreJSON.encode(request),
            port: port
        )
    }

    private func postEvents(_ request: DirectModeEventsRequest, port: UInt16) throws -> HTTPResult {
        try self.request(
            method: "POST",
            path: DirectModeCommandServer.eventsPath,
            body: CoreJSON.encode(request),
            port: port
        )
    }

    private func postPairing(_ request: DirectModePairingSubmitRequest, port: UInt16) throws -> HTTPResult {
        try self.request(
            method: "POST",
            path: DirectModeCommandServer.pairingPath,
            body: CoreJSON.encode(request),
            port: port
        )
    }

    private func request(method: String, path: String, body: Data, port: UInt16) throws -> HTTPResult {
        let client = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(client, 0)
        defer { close(client) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connectResult, 0)

        let header = [
            "\(method) \(path) HTTP/1.1",
            "Host: 127.0.0.1",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        _ = header.withCString { write(client, $0, strlen($0)) }
        body.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress { _ = write(client, base, body.count) }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { ptr in
                read(client, ptr.baseAddress, ptr.count)
            }
            guard count > 0 else { break }
            response.append(contentsOf: buffer.prefix(count))
        }

        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              let headerString = String(data: Data(response[..<separator.lowerBound]), encoding: .utf8),
              let statusLine = headerString.components(separatedBy: "\r\n").first,
              let status = statusLine.split(separator: " ")[safe: 1],
              let statusCode = Int(status) else {
            throw TestHTTPError.invalidResponse
        }
        return HTTPResult(statusCode: statusCode, body: Data(response[separator.upperBound...]))
    }

    private static func entry(
        requestId: String,
        accountId: String = "acct_1",
        macAgentId: String = "mac_1"
    ) -> RemoteCommandInboxEntry {
        let command = RemoteCommand(
            requestId: requestId,
            kind: .stopAll,
            payload: .empty,
            assertion: DeviceAssertion(
                deviceId: "device_1",
                requestId: requestId,
                timestamp: Date(timeIntervalSince1970: 1_750_300_000),
                kind: .stopAll,
                payloadSHA256: "digest",
                signature: "signature"
            )
        )
        return RemoteCommandInboxEntry(
            requestId: requestId,
            accountId: accountId,
            macAgentId: macAgentId,
            fromDeviceId: "device_1",
            command: command,
            createdAt: Date(timeIntervalSince1970: 1_750_300_000)
        )
    }

    private static func routingResult(requestId: String, now: Date) -> RemoteCommandRoutingResult {
        RemoteCommandRoutingResult(
            ack: CommandAck(requestId: requestId, accepted: true, outcome: .accepted, serverTime: now, signature: "sig"),
            auditEvent: RemoteAuditEvent(
                ts: now,
                deviceId: "device_1",
                commandKind: .stopAll,
                requestId: requestId,
                targetSummary: "stopAll terminated=1",
                outcome: .accepted
            ),
            stopAllResult: StopAllResult(terminated: 1)
        )
    }

    private static func ackEnvelope(requestId: String, now: Date) -> RemoteCommandAckEnvelope {
        let result = routingResult(requestId: requestId, now: now)
        return RemoteCommandAckEnvelope(
            requestId: requestId,
            accountId: "acct_1",
            macAgentId: "mac_1",
            ack: result.ack,
            auditEvent: result.auditEvent,
            createdAt: now
        )
    }

    private static func pairingResponse(now: Date) -> DirectModePairingSubmitResponse {
        DirectModePairingSubmitResponse(
            request: RemotePairRequest(
                id: "pair_request_1",
                accountId: "acct_1",
                macAgentId: "mac_1",
                deviceId: "device_1",
                displayName: "Mike's iPhone",
                deviceSigningPubkey: "device_sign",
                deviceSealingPubkey: "device_seal",
                requestedAt: now,
                expiresAt: now.addingTimeInterval(300)
            ),
            sessionId: "session_1",
            acceptedAt: now
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

    private static func eventEnvelope(id: String, seq: Int64) -> RemoteRunEventEnvelope {
        RemoteRunEventEnvelope(
            macAgentId: "mac_1",
            event: RunEvent(
                id: id,
                seq: seq,
                ts: Date(timeIntervalSince1970: 1_750_300_000),
                kind: "run.started",
                payload: ["runId": .string("run_1")]
            ),
            signature: "sig"
        )
    }

    private static func mediaKey(ref: String, macAgentId: String = "mac_1", deviceId: String) -> MediaKeyEnvelope {
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

private struct HTTPResult {
    var statusCode: Int
    var body: Data
}

private enum TestHTTPError: Error {
    case invalidResponse
}

private actor RecordingDirectModeRouter: RemoteCommandRouting {
    private var entries: [RemoteCommandInboxEntry] = []
    private let result: RemoteCommandRoutingResult

    init(result: RemoteCommandRoutingResult) {
        self.result = result
    }

    func route(_ entry: RemoteCommandInboxEntry) async throws -> RemoteCommandRoutingResult {
        entries.append(entry)
        return result
    }

    func recordedEntries() -> [RemoteCommandInboxEntry] {
        entries
    }
}

private final class RecordingDirectModeHandler: DirectModeCommandHandling, @unchecked Sendable {
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

private final class RecordingDirectModePairingHandler: DirectModePairingHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let response: DirectModePairingSubmitResponse
    private var storedRequests: [DirectModePairingSubmitRequest] = []

    init(response: DirectModePairingSubmitResponse) {
        self.response = response
    }

    var requests: [DirectModePairingSubmitRequest] {
        lock.withLock { storedRequests }
    }

    func handle(_ request: DirectModePairingSubmitRequest) throws -> DirectModePairingSubmitResponse {
        lock.withLock { storedRequests.append(request) }
        return response
    }
}

private final class RecordingDirectModeSnapshotHandler: DirectModeSnapshotHandling, @unchecked Sendable {
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

private final class RecordingDirectModeMediaHandler: DirectModeMediaHandling, @unchecked Sendable {
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

private final class RecordingDirectModeMediaKeyHandler: DirectModeMediaKeyHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let storedResponse: DirectModeMediaKeyResponse
    private var storedRequests: [DirectModeMediaKeyRequest] = []

    init(response: DirectModeMediaKeyResponse) {
        self.storedResponse = response
    }

    var requests: [DirectModeMediaKeyRequest] {
        lock.withLock { storedRequests }
    }

    func mediaKey(_ request: DirectModeMediaKeyRequest) async throws -> DirectModeMediaKeyResponse {
        lock.withLock { storedRequests.append(request) }
        return storedResponse
    }
}

private final class RecordingDirectModeEventsHandler: DirectModeEventsHandling, @unchecked Sendable {
    private let lock = NSLock()
    private let storedResponse: DirectModeEventsResponse
    private var storedRequests: [DirectModeEventsRequest] = []

    init(response: DirectModeEventsResponse) {
        self.storedResponse = response
    }

    var requests: [DirectModeEventsRequest] {
        lock.withLock { storedRequests }
    }

    func events(_ request: DirectModeEventsRequest) async throws -> DirectModeEventsResponse {
        lock.withLock { storedRequests.append(request) }
        return storedResponse
    }
}

private final class RecordingDirectModeAuditRecorder: RemoteAuditRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEnvelopes: [RemoteCommandAckEnvelope] = []

    var envelopes: [RemoteCommandAckEnvelope] {
        lock.withLock { storedEnvelopes }
    }

    func record(_ envelope: RemoteCommandAckEnvelope) throws {
        lock.withLock { storedEnvelopes.append(envelope) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
