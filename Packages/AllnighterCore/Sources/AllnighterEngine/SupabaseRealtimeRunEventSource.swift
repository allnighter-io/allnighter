import Foundation
import AllnighterCore

public protocol RemoteRunEventStreamingRelay: RemoteMacRelay {
    func runEventStream(
        accountId: String,
        macAgentId: String,
        after seq: Int64,
        limit: Int
    ) async -> AsyncStream<RemoteRunEventEnvelope>
}

public struct SupabaseRealtimeConnectionRequest: Sendable {
    public var url: URL
    public var headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

public enum SupabaseRealtimeSocketMessage: Sendable, Equatable {
    case string(String)
    case data(Data)
}

public protocol SupabaseRealtimeSocket: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> SupabaseRealtimeSocketMessage
    func close() async
}

public protocol SupabaseRealtimeConnecting: Sendable {
    func connect(_ request: SupabaseRealtimeConnectionRequest) async throws -> any SupabaseRealtimeSocket
}

public struct URLSessionSupabaseRealtimeConnector: SupabaseRealtimeConnecting {
    public init() {}

    public func connect(_ request: SupabaseRealtimeConnectionRequest) async throws -> any SupabaseRealtimeSocket {
        var urlRequest = URLRequest(url: request.url)
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let task = URLSession.shared.webSocketTask(with: urlRequest)
        task.resume()
        return URLSessionSupabaseRealtimeSocket(task: task)
    }
}

private actor URLSessionSupabaseRealtimeSocket: SupabaseRealtimeSocket {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> SupabaseRealtimeSocketMessage {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return .string(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            return .data(Data())
        }
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }
}

public struct SupabaseRealtimeRunEventSource: Sendable {
    private let supabaseURL: URL
    private let publishableKey: String
    private let tokenProvider: any SupabaseAccessTokenProviding
    private let connector: any SupabaseRealtimeConnecting
    private let referenceFactory: @Sendable () -> String
    private let heartbeatInterval: TimeInterval

    public init(
        supabaseURL: URL,
        publishableKey: String,
        tokenProvider: any SupabaseAccessTokenProviding,
        connector: any SupabaseRealtimeConnecting = URLSessionSupabaseRealtimeConnector(),
        referenceFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        heartbeatInterval: TimeInterval = 25
    ) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.tokenProvider = tokenProvider
        self.connector = connector
        self.referenceFactory = referenceFactory
        self.heartbeatInterval = max(1, heartbeatInterval)
    }

    public func stream(accountId: String, macAgentId: String, after seq: Int64) -> AsyncStream<RemoteRunEventEnvelope> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let token = try await tokenProvider.accessToken()
                    let socket = try await connector.connect(SupabaseRealtimeConnectionRequest(
                        url: try realtimeURL(),
                        headers: [
                            "apikey": publishableKey,
                            "Authorization": "Bearer \(token)",
                        ]
                    ))
                    defer {
                        Task { await socket.close() }
                    }

                    let join = try joinMessage(accountId: accountId, macAgentId: macAgentId, accessToken: token)
                    try await socket.send(join)
                    let heartbeatTask = startHeartbeat(socket: socket)
                    defer { heartbeatTask.cancel() }

                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard let envelope = Self.decodeRunEventEnvelope(message, expectedMacAgentId: macAgentId),
                              envelope.event.seq > seq else {
                            continue
                        }
                        continuation.yield(envelope)
                    }
                } catch {}
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func realtimeURL() throws -> URL {
        guard var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false) else {
            throw SupabaseRemoteMacRelayError.invalidBaseURL(supabaseURL.absoluteString)
        }
        switch components.scheme {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            throw SupabaseRemoteMacRelayError.invalidBaseURL(supabaseURL.absoluteString)
        }
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: publishableKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components.url else {
            throw SupabaseRemoteMacRelayError.invalidURL(supabaseURL.absoluteString)
        }
        return url
    }

    private func joinMessage(accountId: String, macAgentId: String, accessToken: String) throws -> String {
        let ref = referenceFactory()
        let message = SupabaseRealtimeV1Message(
            topic: "realtime:allnighter:\(accountId):event_envelopes:\(macAgentId)",
            event: "phx_join",
            payload: SupabaseRealtimeJoinPayload(
                config: SupabaseRealtimeChannelConfig(
                    broadcast: SupabaseRealtimeBroadcastConfig(ack: false, receivesOwnBroadcasts: false),
                    presence: SupabaseRealtimePresenceConfig(enabled: false),
                    postgresChanges: [
                        SupabaseRealtimePostgresChangeConfig(
                            event: "INSERT",
                            schema: "public",
                            table: "event_envelopes",
                            filter: "mac_agent_id=eq.\(macAgentId)"
                        ),
                    ],
                    isPrivate: false
                ),
                accessToken: accessToken
            ),
            ref: ref,
            joinRef: ref
        )
        return String(decoding: try SupabaseJSON.encode(message), as: UTF8.self)
    }

    private func startHeartbeat(socket: any SupabaseRealtimeSocket) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                let message = SupabaseRealtimeV1Message(
                    topic: "phoenix",
                    event: "heartbeat",
                    payload: SupabaseRealtimeEmptyPayload(),
                    ref: referenceFactory(),
                    joinRef: nil
                )
                guard let text = try? String(decoding: SupabaseJSON.encode(message), as: UTF8.self) else { continue }
                try? await socket.send(text)
            }
        }
    }

    private static func decodeRunEventEnvelope(
        _ message: SupabaseRealtimeSocketMessage,
        expectedMacAgentId: String
    ) -> RemoteRunEventEnvelope? {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let raw):
            data = raw
        }
        guard let decoded = try? SupabaseJSON.decode(SupabaseRealtimeIncomingMessage.self, from: data),
              decoded.event == "postgres_changes",
              decoded.payload?.data?.schema == "public",
              decoded.payload?.data?.table == "event_envelopes",
              decoded.payload?.data?.type == "INSERT",
              let envelope = decoded.payload?.data?.record?.envelope(),
              envelope.macAgentId == expectedMacAgentId else {
            return nil
        }
        return envelope
    }
}

private struct SupabaseRealtimeV1Message<Payload: Encodable>: Encodable {
    var topic: String
    var event: String
    var payload: Payload
    var ref: String
    var joinRef: String?

    enum CodingKeys: String, CodingKey {
        case topic
        case event
        case payload
        case ref
        case joinRef = "join_ref"
    }
}

private struct SupabaseRealtimeEmptyPayload: Encodable {}

private struct SupabaseRealtimeJoinPayload: Encodable {
    var config: SupabaseRealtimeChannelConfig
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case config
        case accessToken = "access_token"
    }
}

private struct SupabaseRealtimeChannelConfig: Encodable {
    var broadcast: SupabaseRealtimeBroadcastConfig
    var presence: SupabaseRealtimePresenceConfig
    var postgresChanges: [SupabaseRealtimePostgresChangeConfig]
    var isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case broadcast
        case presence
        case postgresChanges = "postgres_changes"
        case isPrivate = "private"
    }
}

private struct SupabaseRealtimeBroadcastConfig: Encodable {
    var ack: Bool
    var receivesOwnBroadcasts: Bool

    enum CodingKeys: String, CodingKey {
        case ack
        case receivesOwnBroadcasts = "self"
    }
}

private struct SupabaseRealtimePresenceConfig: Encodable {
    var enabled: Bool
}

private struct SupabaseRealtimePostgresChangeConfig: Encodable {
    var event: String
    var schema: String
    var table: String
    var filter: String
}

private struct SupabaseRealtimeIncomingMessage: Decodable {
    var event: String
    var payload: SupabaseRealtimeIncomingPayload?
}

private struct SupabaseRealtimeIncomingPayload: Decodable {
    var data: SupabaseRealtimePostgresChangeData?
}

private struct SupabaseRealtimePostgresChangeData: Decodable {
    var schema: String
    var table: String
    var type: String
    var record: EventEnvelopeRow?
}
