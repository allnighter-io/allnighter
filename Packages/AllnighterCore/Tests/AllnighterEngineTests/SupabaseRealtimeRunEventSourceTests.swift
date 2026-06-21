import CryptoKit
import Foundation
import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class SupabaseRealtimeRunEventSourceTests: XCTestCase {
    private let supabaseURL = URL(string: "https://example.supabase.co")!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testRealtimeSourceJoinsFilteredEventEnvelopeChannel() async throws {
        let socket = RecordingSupabaseRealtimeSocket(messages: [
            .string(try postgresChangeMessage(envelope: signedEnvelope(id: "evt_5", seq: 5)))
        ])
        let connector = RecordingSupabaseRealtimeConnector(socket: socket)
        let source = SupabaseRealtimeRunEventSource(
            supabaseURL: supabaseURL,
            publishableKey: "publishable",
            tokenProvider: StaticSupabaseAccessTokenProvider(token: "jwt"),
            connector: connector,
            referenceFactory: { "ref_1" }
        )

        var events: [RemoteRunEventEnvelope] = []
        for await event in source.stream(accountId: "acct_1", macAgentId: "mac_1", after: 4) {
            events.append(event)
        }

        XCTAssertEqual(events.map(\.event.id), ["evt_5"])
        let recordedRequests = await connector.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.url.scheme, "wss")
        XCTAssertEqual(request.url.path, "/realtime/v1/websocket")
        XCTAssertEqual(queryValue("apikey", in: request.url), "publishable")
        XCTAssertEqual(queryValue("vsn", in: request.url), "1.0.0")
        XCTAssertEqual(request.headers["apikey"], "publishable")
        XCTAssertEqual(request.headers["Authorization"], "Bearer jwt")

        let sentMessages = await socket.sentMessages()
        let sent = try XCTUnwrap(sentMessages.first)
        let join = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any])
        XCTAssertEqual(join["topic"] as? String, "realtime:allnighter:acct_1:event_envelopes:mac_1")
        XCTAssertEqual(join["event"] as? String, "phx_join")
        XCTAssertEqual(join["ref"] as? String, "ref_1")
        XCTAssertEqual(join["join_ref"] as? String, "ref_1")

        let payload = try XCTUnwrap(join["payload"] as? [String: Any])
        XCTAssertEqual(payload["access_token"] as? String, "jwt")
        let config = try XCTUnwrap(payload["config"] as? [String: Any])
        XCTAssertEqual(config["private"] as? Bool, false)
        let postgresChanges = try XCTUnwrap(config["postgres_changes"] as? [[String: Any]])
        let change = try XCTUnwrap(postgresChanges.first)
        XCTAssertEqual(change["event"] as? String, "INSERT")
        XCTAssertEqual(change["schema"] as? String, "public")
        XCTAssertEqual(change["table"] as? String, "event_envelopes")
        XCTAssertEqual(change["filter"] as? String, "mac_agent_id=eq.mac_1")
    }

    func testRealtimeSourceIgnoresWrongTableWrongMacAndOldSeq() async throws {
        let socket = RecordingSupabaseRealtimeSocket(messages: [
            .string(try postgresChangeMessage(envelope: signedEnvelope(id: "evt_old", seq: 4))),
            .string(try postgresChangeMessage(envelope: signedEnvelope(id: "evt_other", seq: 6, macAgentId: "mac_other"))),
            .string(try postgresChangeMessage(envelope: signedEnvelope(id: "evt_wrong_table", seq: 7), table: "command_acks")),
            .string(try postgresChangeMessage(envelope: signedEnvelope(id: "evt_8", seq: 8))),
        ])
        let source = SupabaseRealtimeRunEventSource(
            supabaseURL: supabaseURL,
            publishableKey: "publishable",
            tokenProvider: StaticSupabaseAccessTokenProvider(token: "jwt"),
            connector: RecordingSupabaseRealtimeConnector(socket: socket),
            referenceFactory: { "ref_1" }
        )

        var ids: [String] = []
        for await envelope in source.stream(accountId: "acct_1", macAgentId: "mac_1", after: 4) {
            ids.append(envelope.event.id)
        }

        XCTAssertEqual(ids, ["evt_8"])
    }

    private func signedEnvelope(id: String, seq: Int64, macAgentId: String = "mac_1") throws -> RemoteRunEventEnvelope {
        let signingKey = Curve25519.Signing.PrivateKey()
        return try RemoteCrypto.makeRemoteRunEventEnvelope(
            macAgentId: macAgentId,
            event: RunEvent(
                id: id,
                seq: seq,
                ts: now.addingTimeInterval(TimeInterval(seq)),
                kind: "run.started",
                payload: ["runId": .string("run_1")]
            ),
            signingKey: signingKey
        )
    }

    private func postgresChangeMessage(envelope: RemoteRunEventEnvelope, table: String = "event_envelopes") throws -> String {
        let row = EventEnvelopeRow(accountId: "acct_1", envelope: envelope)
        let rowJSON = try JSONSerialization.jsonObject(with: SupabaseJSON.encode(row))
        let message: [String: Any] = [
            "event": "postgres_changes",
            "payload": [
                "ids": [1],
                "data": [
                    "schema": "public",
                    "table": table,
                    "type": "INSERT",
                    "commit_timestamp": iso(now),
                    "columns": [],
                    "record": rowJSON,
                    "old_record": [:],
                    "errors": NSNull(),
                ],
            ],
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]), as: UTF8.self)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private enum SupabaseRealtimeTestError: Error {
    case endOfMessages
}

private actor RecordingSupabaseRealtimeSocket: SupabaseRealtimeSocket {
    private var messages: [SupabaseRealtimeSocketMessage]
    private var sent: [String] = []
    private(set) var isClosed = false

    init(messages: [SupabaseRealtimeSocketMessage]) {
        self.messages = messages
    }

    func send(_ text: String) async throws {
        sent.append(text)
    }

    func receive() async throws -> SupabaseRealtimeSocketMessage {
        guard !messages.isEmpty else {
            throw SupabaseRealtimeTestError.endOfMessages
        }
        return messages.removeFirst()
    }

    func close() async {
        isClosed = true
    }

    func sentMessages() -> [String] {
        sent
    }
}

private actor RecordingSupabaseRealtimeConnector: SupabaseRealtimeConnecting {
    private let socket: RecordingSupabaseRealtimeSocket
    private var requests: [SupabaseRealtimeConnectionRequest] = []

    init(socket: RecordingSupabaseRealtimeSocket) {
        self.socket = socket
    }

    func connect(_ request: SupabaseRealtimeConnectionRequest) async throws -> any SupabaseRealtimeSocket {
        requests.append(request)
        return socket
    }

    func recordedRequests() -> [SupabaseRealtimeConnectionRequest] {
        requests
    }
}
