import Foundation

public protocol SupabaseAccessTokenProviding: Sendable {
    func accessToken() async throws -> String
}

public struct StaticSupabaseAccessTokenProvider: SupabaseAccessTokenProviding {
    public var token: String

    public init(token: String) {
        self.token = token
    }

    public func accessToken() async throws -> String {
        token
    }
}

public struct SupabaseHTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct SupabaseHTTPResponse: Sendable {
    public var statusCode: Int
    public var data: Data
    public var headers: [String: String]

    public init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

public protocol SupabaseHTTPTransport: Sendable {
    func send(_ request: SupabaseHTTPRequest) async throws -> SupabaseHTTPResponse
}

public struct URLSessionSupabaseHTTPTransport: SupabaseHTTPTransport {
    public init() {}

    public func send(_ request: SupabaseHTTPRequest) async throws -> SupabaseHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseRemoteMacRelayError.nonHTTPResponse
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = String(describing: entry.value)
        }
        return SupabaseHTTPResponse(statusCode: http.statusCode, data: data, headers: headers)
    }
}

public enum SupabaseRemoteMacRelayError: Error, Equatable, Sendable {
    case invalidBaseURL(String)
    case invalidURL(String)
    case nonHTTPResponse
    case http(statusCode: Int, body: String)
    case decodeFailed(String)
    case unsupportedOperation(String)
}

public actor SupabaseRemoteMacRelay: RemoteRunEventStreamingRelay {
    private let baseURL: URL
    private let publishableKey: String
    private let tokenProvider: any SupabaseAccessTokenProviding
    private let transport: any SupabaseHTTPTransport
    private let realtimeEventSource: SupabaseRealtimeRunEventSource
    private let now: @Sendable () -> Date

    public init(
        supabaseURL: URL,
        publishableKey: String,
        tokenProvider: any SupabaseAccessTokenProviding,
        transport: any SupabaseHTTPTransport = URLSessionSupabaseHTTPTransport(),
        realtimeConnector: any SupabaseRealtimeConnecting = URLSessionSupabaseRealtimeConnector(),
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        guard supabaseURL.scheme != nil, supabaseURL.host != nil else {
            throw SupabaseRemoteMacRelayError.invalidBaseURL(supabaseURL.absoluteString)
        }
        self.baseURL = supabaseURL
        self.publishableKey = publishableKey
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.realtimeEventSource = SupabaseRealtimeRunEventSource(
            supabaseURL: supabaseURL,
            publishableKey: publishableKey,
            tokenProvider: tokenProvider,
            connector: realtimeConnector
        )
        self.now = now
    }

    public func registerMacAgent(_ registration: RemoteMacAgentRegistration) async throws -> MacAgentRef {
        try Self.validateProtocolVersion(registration.protocolVersion)
        let row = MacAgentRow(
            id: registration.macAgentId,
            accountId: registration.accountId,
            displayName: registration.displayName,
            agentSigningPubkey: registration.agentSigningPubkey,
            agentSealingPubkey: registration.agentSealingPubkey,
            lastSeenAt: nil
        )
        let rows: [MacAgentRow] = try await post(
            table: "mac_agents",
            rows: [row],
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            prefer: "resolution=merge-duplicates,return=representation"
        )
        return try (rows.first(where: {
            $0.id == registration.macAgentId && $0.accountId == registration.accountId
        }) ?? row).macRef()
    }

    public func heartbeat(_ heartbeat: RemoteMacAgentHeartbeat) async throws {
        try Self.validateProtocolVersion(heartbeat.protocolVersion)
        try await patch(
            table: "mac_agents",
            body: MacAgentHeartbeatPatch(lastSeenAt: heartbeat.at),
            query: [
                eq("id", heartbeat.macAgentId),
                eq("account_id", heartbeat.accountId),
            ]
        )
    }

    public func macAgents(accountId: String) async throws -> [MacAgentRef] {
        let rows: [MacAgentRow] = try await get(
            table: "mac_agents",
            query: [
                select("id,account_id,display_name,agent_signing_pubkey,agent_sealing_pubkey,last_seen_at"),
                eq("account_id", accountId),
                URLQueryItem(name: "order", value: "display_name.asc,id.asc"),
            ]
        )
        return try rows
            .filter { $0.accountId == accountId }
            .map { try $0.macRef() }
    }

    public func submitPairRequest(_ request: RemotePairRequestDraft) async throws -> RemotePairRequest {
        let row = PairRequestInsertRow(from: request)
        let rows: [PairRequestRow] = try await post(
            table: "pair_requests",
            rows: [row],
            prefer: "return=representation"
        )
        guard let inserted = rows.first(where: {
            $0.accountId == request.accountId
                && $0.macAgentId == request.macAgentId
                && $0.deviceId == request.deviceId
        }) else {
            throw SupabaseRemoteMacRelayError.decodeFailed("missing pair_requests insert representation")
        }
        return try inserted.model()
    }

    public func pendingPairRequests(accountId: String, macAgentId: String) async throws -> [RemotePairRequest] {
        let rows: [PairRequestRow] = try await get(
            table: "pair_requests",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                eq("status", RemotePairRequestStatus.pending.rawValue),
                URLQueryItem(name: "order", value: "requested_at.asc,device_id.asc"),
            ]
        )
        return try rows
            .filter {
                $0.accountId == accountId
                    && $0.macAgentId == macAgentId
                    && $0.status == .pending
            }
            .map { try $0.model() }
    }

    public func pairRequestStatus(
        accountId: String,
        macAgentId: String,
        requestId: String,
        deviceId: String,
        checkedAt: Date
    ) async throws -> RemotePairingStatusResponse {
        let requests: [PairRequestRow] = try await get(
            table: "pair_requests",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                eq("id", requestId),
                eq("device_id", deviceId),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let request = try requests.first(where: {
            $0.accountId == accountId
                && $0.macAgentId == macAgentId
                && $0.id == requestId
                && $0.deviceId == deviceId
        })?.model() else {
            return RemotePairingStatusResponse(requestId: requestId, deviceId: deviceId, status: .notFound, checkedAt: checkedAt)
        }

        let trustedDevice = try await trustedDevices(accountId: accountId, macAgentId: macAgentId)
            .first { $0.deviceId == deviceId }
        let status: RemotePairingStatusKind
        if let trustedDevice, trustedDevice.revoked {
            status = .revoked
        } else if let trustedDevice, trustedDevice.validUntil < checkedAt {
            status = .expired
        } else if trustedDevice != nil {
            status = .approved
        } else if request.status == .rejected {
            status = .rejected
        } else if request.expiresAt < checkedAt || request.status == .expired {
            status = .expired
        } else {
            status = .pending
        }
        return RemotePairingStatusResponse(
            requestId: requestId,
            deviceId: deviceId,
            status: status,
            pairRequest: request,
            trustedDevice: trustedDevice,
            checkedAt: checkedAt
        )
    }

    public func updatePairRequest(_ request: RemotePairRequest) async throws -> RemotePairRequest {
        let rows: [PairRequestRow] = try await patch(
            table: "pair_requests",
            body: PairRequestUpdateRow(from: request),
            query: [
                eq("id", request.id),
                eq("account_id", request.accountId),
                eq("mac_agent_id", request.macAgentId),
            ],
            prefer: "return=representation"
        )
        return try (rows.first(where: {
            $0.id == request.id
                && $0.accountId == request.accountId
                && $0.macAgentId == request.macAgentId
        })?.model() ?? request)
    }

    public func trustedDevices(accountId: String, macAgentId: String) async throws -> [TrustedDevice] {
        let rows: [TrustedDeviceRow] = try await get(
            table: "trusted_devices",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                URLQueryItem(name: "order", value: "display_name.asc,device_id.asc"),
            ]
        )
        return rows
            .filter { $0.accountId == accountId && $0.macAgentId == macAgentId }
            .map { $0.model() }
    }

    public func upsertTrustedDevice(_ device: TrustedDevice) async throws {
        _ = try await post(
            table: "trusted_devices",
            rows: [TrustedDeviceRow(device)],
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id,device_id")],
            prefer: "resolution=merge-duplicates,return=minimal"
        ) as [TrustedDeviceRow]
    }

    public func submitCommand(_ entry: RemoteCommandInboxEntry) async throws {
        _ = try await post(
            table: "command_inbox",
            rows: [CommandInboxRow(entry)],
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id,request_id")],
            prefer: "resolution=ignore-duplicates,return=minimal"
        ) as [CommandInboxRow]
    }

    public func commandAck(
        accountId: String,
        macAgentId: String,
        requestId: String
    ) async throws -> RemoteCommandAckEnvelope? {
        let rows: [CommandAckRow] = try await get(
            table: "command_acks",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                eq("request_id", requestId),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = rows.first(where: {
            $0.accountId == accountId && $0.macAgentId == macAgentId && $0.requestId == requestId
        }) else { return nil }
        return row.envelope()
    }

    public func pendingCommands(accountId: String, macAgentId: String, limit: Int) async throws -> [RemoteCommandInboxEntry] {
        guard limit > 0 else { return [] }
        let rows: [CommandInboxRow] = try await get(
            table: "command_inbox",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                eq("status", RemoteCommandInboxStatus.pending.rawValue),
                URLQueryItem(name: "order", value: "created_at.asc,request_id.asc"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return try rows
            .filter {
                $0.accountId == accountId
                    && $0.macAgentId == macAgentId
                    && $0.status == .pending
            }
            .map { try $0.entry() }
    }

    public func acknowledge(_ envelope: RemoteCommandAckEnvelope) async throws {
        _ = try await post(
            table: "command_acks",
            rows: [CommandAckRow(envelope)],
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id,request_id")],
            prefer: "resolution=ignore-duplicates,return=minimal"
        ) as [CommandAckRow]
        try await patch(
            table: "command_inbox",
            body: CommandInboxStatusPatch(status: .acked),
            query: [
                eq("account_id", envelope.accountId),
                eq("mac_agent_id", envelope.macAgentId),
                eq("request_id", envelope.requestId),
            ]
        )
    }

    public func runEvents(
        accountId: String,
        macAgentId: String,
        after seq: Int64,
        limit: Int
    ) async throws -> [RemoteRunEventEnvelope] {
        guard limit > 0 else { return [] }
        let rows: [EventEnvelopeRow] = try await get(
            table: "event_envelopes",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                URLQueryItem(name: "seq", value: "gt.\(seq)"),
                URLQueryItem(name: "order", value: "seq.asc,id.asc"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return rows
            .filter { $0.accountId == accountId && $0.macAgentId == macAgentId && $0.seq > seq }
            .map { $0.envelope() }
    }

    public func runEventStream(
        accountId: String,
        macAgentId: String,
        after seq: Int64,
        limit: Int
    ) async -> AsyncStream<RemoteRunEventEnvelope> {
        guard limit > 0 else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let backfill: [RemoteRunEventEnvelope]
        do {
            backfill = try await runEvents(accountId: accountId, macAgentId: macAgentId, after: seq, limit: limit)
        } catch {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let live = realtimeEventSource.stream(accountId: accountId, macAgentId: macAgentId, after: seq)
        return AsyncStream { continuation in
            Task {
                var yieldedIds = Set<String>()
                var yielded = 0

                for envelope in backfill where envelope.event.seq > seq {
                    guard envelope.macAgentId == macAgentId, yieldedIds.insert(envelope.event.id).inserted else { continue }
                    continuation.yield(envelope)
                    yielded += 1
                    if yielded >= limit {
                        continuation.finish()
                        return
                    }
                }

                for await envelope in live where envelope.event.seq > seq {
                    guard envelope.macAgentId == macAgentId, yieldedIds.insert(envelope.event.id).inserted else { continue }
                    continuation.yield(envelope)
                    yielded += 1
                    if yielded >= limit {
                        break
                    }
                }
                continuation.finish()
            }
        }
    }

    public func publishEvents(accountId: String, macAgentId: String, events: [RemoteRunEventEnvelope]) async throws {
        if let mismatchedEvent = events.first(where: { $0.macAgentId != macAgentId }) {
            throw RemoteMacRelayError.eventScopeMismatch(
                expectedMacAgentId: macAgentId,
                actualMacAgentId: mismatchedEvent.macAgentId,
                eventId: mismatchedEvent.event.id
            )
        }
        if let mismatchedEvent = events.first(where: { event in
            guard let sealedMacAgentId = event.sealedRef?.macAgentId else { return false }
            return sealedMacAgentId != macAgentId
        }) {
            throw RemoteMacRelayError.eventScopeMismatch(
                expectedMacAgentId: macAgentId,
                actualMacAgentId: mismatchedEvent.sealedRef?.macAgentId ?? mismatchedEvent.macAgentId,
                eventId: mismatchedEvent.event.id
            )
        }
        let rows = events.map { EventEnvelopeRow(accountId: accountId, envelope: $0) }
        guard !rows.isEmpty else { return }
        _ = try await post(
            table: "event_envelopes",
            rows: rows,
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id,id")],
            prefer: "resolution=ignore-duplicates,return=minimal"
        ) as [EventEnvelopeRow]
    }

    public func publishSnapshot(accountId: String, macAgentId: String, snapshot: SnapshotEnvelope) async throws {
        _ = try await post(
            table: "snapshot_envelopes",
            rows: [SnapshotEnvelopeRow(accountId: accountId, macAgentId: macAgentId, snapshot: snapshot, updatedAt: now())],
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id")],
            prefer: "resolution=merge-duplicates,return=minimal"
        ) as [SnapshotEnvelopeRow]
    }

    public func snapshot(accountId: String, macAgentId: String, since _: Int64?) async throws -> SnapshotEnvelope? {
        let rows: [SnapshotEnvelopeRow] = try await get(
            table: "snapshot_envelopes",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first(where: { $0.accountId == accountId && $0.macAgentId == macAgentId })?.envelope()
    }

    public func publishThreadSnapshot(
        accountId: String,
        macAgentId: String,
        snapshot: RemoteThreadSnapshotEnvelope
    ) async throws {
        _ = try await post(
            table: "thread_snapshot_envelopes",
            rows: [ThreadSnapshotEnvelopeRow(
                accountId: accountId,
                macAgentId: macAgentId,
                snapshot: snapshot,
                updatedAt: now()
            )],
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id")],
            prefer: "resolution=merge-duplicates,return=minimal"
        ) as [ThreadSnapshotEnvelopeRow]
    }

    public func threadSnapshot(
        accountId: String,
        macAgentId: String
    ) async throws -> RemoteThreadSnapshotEnvelope? {
        let rows: [ThreadSnapshotEnvelopeRow] = try await get(
            table: "thread_snapshot_envelopes",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first(where: { $0.accountId == accountId && $0.macAgentId == macAgentId })?.envelope()
    }

    public func publishThreadDetail(
        accountId: String,
        macAgentId: String,
        threadId: String,
        deviceId: String,
        sealedDetail: SealedBlob
    ) async throws {
        try Self.validateThreadDetail(threadId: threadId, deviceId: deviceId, sealedDetail: sealedDetail)
        _ = try await post(
            table: "thread_detail_blobs",
            rows: [ThreadDetailBlobRow(
                accountId: accountId,
                macAgentId: macAgentId,
                threadId: threadId,
                deviceId: deviceId,
                sealedDetail: sealedDetail,
                updatedAt: now()
            )],
            query: [URLQueryItem(name: "on_conflict", value: "account_id,mac_agent_id,thread_id,device_id")],
            prefer: "resolution=merge-duplicates,return=minimal"
        ) as [ThreadDetailBlobRow]
    }

    public func sealedThreadDetail(
        accountId: String,
        macAgentId: String,
        threadId: String,
        deviceId: String
    ) async throws -> SealedBlob? {
        let rows: [ThreadDetailBlobRow] = try await get(
            table: "thread_detail_blobs",
            query: [
                eq("account_id", accountId),
                eq("mac_agent_id", macAgentId),
                eq("thread_id", threadId),
                eq("device_id", deviceId),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first(where: {
            $0.accountId == accountId
                && $0.macAgentId == macAgentId
                && $0.threadId == threadId
                && $0.deviceId == deviceId
        })?.sealedDetail
    }

    public func publishMedia(ref: MediaRef, data _: Data, keys: [MediaKeyEnvelope]) async throws {
        if let mismatchedKey = keys.first(where: { $0.macAgentId != ref.macAgentId || $0.ref != ref.ref }) {
            throw RemoteMacRelayError.mediaScopeMismatch(
                expectedMacAgentId: ref.macAgentId,
                actualMacAgentId: mismatchedKey.macAgentId,
                expectedRef: ref.ref,
                actualRef: mismatchedKey.ref
            )
        }
        _ = try await post(
            table: "media_refs",
            rows: [MediaRefRow(ref)],
            query: [URLQueryItem(name: "on_conflict", value: "mac_agent_id,ref")],
            prefer: "resolution=merge-duplicates,return=minimal"
        ) as [MediaRefRow]
        if !keys.isEmpty {
            _ = try await post(
                table: "media_keys",
                rows: keys.map(MediaKeyRow.init),
                query: [URLQueryItem(name: "on_conflict", value: "mac_agent_id,ref,device_id")],
                prefer: "resolution=merge-duplicates,return=minimal"
            ) as [MediaKeyRow]
        }
    }

    public func upsertMediaKey(_ key: MediaKeyEnvelope, macAgentId: String) async throws {
        guard key.macAgentId == macAgentId else {
            throw RemoteMacRelayError.mediaScopeMismatch(
                expectedMacAgentId: macAgentId,
                actualMacAgentId: key.macAgentId,
                expectedRef: key.ref,
                actualRef: key.ref
            )
        }
        _ = try await post(
            table: "media_keys",
            rows: [MediaKeyRow(key)],
            query: [URLQueryItem(name: "on_conflict", value: "mac_agent_id,ref,device_id")],
            prefer: "resolution=merge-duplicates,return=minimal"
        ) as [MediaKeyRow]
    }

    public func mediaData(ref _: String, macAgentId _: String, at _: Date) async throws -> Data? {
        throw SupabaseRemoteMacRelayError.unsupportedOperation("mediaData requires the R2 media plane")
    }

    public func mediaKey(ref: String, macAgentId: String, deviceId: String, at now: Date) async throws -> MediaKeyEnvelope? {
        let rows: [MediaKeyRow] = try await get(
            table: "media_keys",
            query: [
                eq("mac_agent_id", macAgentId),
                eq("ref", ref),
                eq("device_id", deviceId),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = rows.first(where: {
            $0.macAgentId == macAgentId && $0.ref == ref && $0.deviceId == deviceId
        }) else { return nil }
        let refs: [MediaRefRow] = try await get(
            table: "media_refs",
            query: [
                eq("mac_agent_id", macAgentId),
                eq("ref", ref),
                URLQueryItem(name: "expires_at", value: "gte.\(SupabaseJSON.string(from: now))"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard refs.contains(where: { $0.macAgentId == macAgentId && $0.ref == ref && $0.expiresAt >= now }) else {
            return nil
        }
        return row.model()
    }

    private func get<T: Decodable>(table: String, query: [URLQueryItem]) async throws -> [T] {
        let response = try await request(method: "GET", table: table, query: query)
        guard !response.data.isEmpty else { return [] }
        return try SupabaseJSON.decode([T].self, from: response.data)
    }

    private func post<Body: Encodable, Row: Decodable>(
        table: String,
        rows: [Body],
        query: [URLQueryItem] = [],
        prefer: String
    ) async throws -> [Row] {
        let body = try SupabaseJSON.encode(rows)
        let response = try await request(method: "POST", table: table, query: query, body: body, prefer: prefer)
        guard !response.data.isEmpty else { return [] }
        return try SupabaseJSON.decode([Row].self, from: response.data)
    }

    @discardableResult
    private func patch<Body: Encodable, Row: Decodable>(
        table: String,
        body: Body,
        query: [URLQueryItem],
        prefer: String = "return=minimal"
    ) async throws -> [Row] {
        let data = try SupabaseJSON.encode(body)
        let response = try await request(method: "PATCH", table: table, query: query, body: data, prefer: prefer)
        guard !response.data.isEmpty else { return [] }
        return try SupabaseJSON.decode([Row].self, from: response.data)
    }

    private func patch<Body: Encodable>(
        table: String,
        body: Body,
        query: [URLQueryItem],
        prefer: String = "return=minimal"
    ) async throws {
        let _: [EmptyRow] = try await patch(table: table, body: body, query: query, prefer: prefer)
    }

    private func request(
        method: String,
        table: String,
        query: [URLQueryItem],
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> SupabaseHTTPResponse {
        let token = try await tokenProvider.accessToken()
        let url = try tableURL(table, query: query)
        var headers = [
            "apikey": publishableKey,
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
        ]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        if let prefer {
            headers["Prefer"] = prefer
        }
        let response = try await transport.send(SupabaseHTTPRequest(method: method, url: url, headers: headers, body: body))
        guard (200..<300).contains(response.statusCode) else {
            throw SupabaseRemoteMacRelayError.http(
                statusCode: response.statusCode,
                body: String(decoding: response.data, as: UTF8.self)
            )
        }
        return response
    }

    private func tableURL(_ table: String, query: [URLQueryItem]) throws -> URL {
        let restURL = baseURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent(table)
        guard var components = URLComponents(url: restURL, resolvingAgainstBaseURL: false) else {
            throw SupabaseRemoteMacRelayError.invalidURL(restURL.absoluteString)
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw SupabaseRemoteMacRelayError.invalidURL(restURL.absoluteString)
        }
        return url
    }

    private func select(_ value: String) -> URLQueryItem {
        URLQueryItem(name: "select", value: value)
    }

    private func eq(_ column: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: column, value: "eq.\(value)")
    }

    private static func validateProtocolVersion(_ version: Int) throws {
        guard version == RemoteProtocol.currentMajor else {
            throw RemoteMacRelayError.unsupportedProtocolVersion(expected: RemoteProtocol.currentMajor, actual: version)
        }
    }

    private static func validateThreadDetail(threadId: String, deviceId: String, sealedDetail: SealedBlob) throws {
        guard sealedDetail.sealedForKeyId == deviceId else {
            throw RemoteMacRelayError.threadDetailDeviceMismatch(
                threadId: threadId,
                expectedDeviceId: deviceId,
                actualSealedForKeyId: sealedDetail.sealedForKeyId
            )
        }
        guard sealedDetail.contentType == RemoteThreadDetail.sealedContentType else {
            throw RemoteMacRelayError.threadDetailContentTypeMismatch(
                threadId: threadId,
                expectedContentType: RemoteThreadDetail.sealedContentType,
                actualContentType: sealedDetail.contentType
            )
        }
    }
}

public enum SupabaseJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SupabaseRemoteMacRelayError.decodeFailed(String(describing: error))
        }
    }

    static func string(from date: Date) -> String {
        formatter(fractionalSeconds: true).string(from: date)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            for formatter in [formatter(fractionalSeconds: true), formatter(fractionalSeconds: false)] {
                if let date = formatter.date(from: value) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Supabase timestamp \(value)")
        }
        return decoder
    }

    private static func formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}

private struct EmptyRow: Codable {}

private struct MacAgentRow: Codable {
    var id: String
    var accountId: String
    var displayName: String
    var agentSigningPubkey: String
    var agentSealingPubkey: String
    var lastSeenAt: Date?

    func macRef() throws -> MacAgentRef {
        MacAgentRef(
            macAgentId: id,
            displayName: displayName,
            agentSigningPubkey: agentSigningPubkey,
            agentSealingPubkey: agentSealingPubkey,
            lastSeenAt: lastSeenAt
        )
    }
}

private struct MacAgentHeartbeatPatch: Codable {
    var lastSeenAt: Date
}

private struct PairRequestInsertRow: Codable {
    var accountId: String
    var macAgentId: String
    var deviceId: String
    var displayName: String
    var deviceSigningPubkey: String
    var deviceSealingPubkey: String
    var requestedAt: Date
    var expiresAt: Date

    init(from draft: RemotePairRequestDraft) {
        accountId = draft.accountId
        macAgentId = draft.macAgentId
        deviceId = draft.deviceId
        displayName = draft.displayName
        deviceSigningPubkey = draft.deviceSigningPubkey
        deviceSealingPubkey = draft.deviceSealingPubkey
        requestedAt = draft.requestedAt
        expiresAt = draft.expiresAt
    }
}

private struct PairRequestUpdateRow: Codable {
    var status: RemotePairRequestStatus
    var approvedAt: Date?
    var rejectedAt: Date?

    init(from request: RemotePairRequest) {
        status = request.status
        approvedAt = request.approvedAt
        rejectedAt = request.rejectedAt
    }
}

private struct PairRequestRow: Codable {
    var id: String
    var accountId: String
    var macAgentId: String
    var deviceId: String
    var displayName: String
    var deviceSigningPubkey: String
    var deviceSealingPubkey: String
    var status: RemotePairRequestStatus
    var requestedAt: Date
    var expiresAt: Date
    var approvedAt: Date?
    var rejectedAt: Date?

    func model() throws -> RemotePairRequest {
        RemotePairRequest(
            id: id,
            accountId: accountId,
            macAgentId: macAgentId,
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: deviceSigningPubkey,
            deviceSealingPubkey: deviceSealingPubkey,
            status: status,
            requestedAt: requestedAt,
            expiresAt: expiresAt,
            approvedAt: approvedAt,
            rejectedAt: rejectedAt
        )
    }
}

private struct TrustedDeviceRow: Codable {
    var deviceId: String
    var accountId: String
    var macAgentId: String
    var displayName: String
    var deviceSigningPubkey: String
    var deviceSealingPubkey: String
    var pairedAt: Date
    var validUntil: Date
    var revoked: Bool
    var revokedAt: Date?
    var lastSeenAt: Date?
    var capabilities: Set<RemoteCapability>

    init(_ device: TrustedDevice) {
        deviceId = device.deviceId
        accountId = device.accountId
        macAgentId = device.macAgentId
        displayName = device.displayName
        deviceSigningPubkey = device.deviceSigningPubkey
        deviceSealingPubkey = device.deviceSealingPubkey
        pairedAt = device.pairedAt
        validUntil = device.validUntil
        revoked = device.revoked
        revokedAt = device.revokedAt
        lastSeenAt = device.lastSeenAt
        capabilities = device.capabilities
    }

    func model() -> TrustedDevice {
        TrustedDevice(
            deviceId: deviceId,
            displayName: displayName,
            deviceSigningPubkey: deviceSigningPubkey,
            deviceSealingPubkey: deviceSealingPubkey,
            accountId: accountId,
            macAgentId: macAgentId,
            pairedAt: pairedAt,
            validUntil: validUntil,
            revoked: revoked,
            revokedAt: revokedAt,
            lastSeenAt: lastSeenAt,
            capabilities: capabilities
        )
    }
}

private struct CommandInboxRow: Codable {
    var requestId: String
    var accountId: String
    var macAgentId: String
    var fromDeviceId: String
    var kind: RemoteCommandKind
    var payload: RemoteCommandPayload
    var signature: String
    var createdAt: Date
    var status: RemoteCommandInboxStatus

    init(_ entry: RemoteCommandInboxEntry) {
        requestId = entry.requestId
        accountId = entry.accountId
        macAgentId = entry.macAgentId
        fromDeviceId = entry.fromDeviceId
        kind = entry.command.kind
        payload = entry.command.payload
        signature = entry.command.assertion.signature
        createdAt = entry.command.assertion.timestamp
        status = entry.status
    }

    func entry() throws -> RemoteCommandInboxEntry {
        let assertion = DeviceAssertion(
            deviceId: fromDeviceId,
            requestId: requestId,
            timestamp: createdAt,
            kind: kind,
            payloadSHA256: try RemoteCrypto.payloadDigest(payload),
            signature: signature
        )
        let command = RemoteCommand(requestId: requestId, kind: kind, payload: payload, assertion: assertion)
        return RemoteCommandInboxEntry(
            requestId: requestId,
            accountId: accountId,
            macAgentId: macAgentId,
            fromDeviceId: fromDeviceId,
            command: command,
            createdAt: createdAt,
            status: status
        )
    }
}

private struct CommandInboxStatusPatch: Codable {
    var status: RemoteCommandInboxStatus
}

private struct CommandAckRow: Codable {
    var requestId: String
    var accountId: String
    var macAgentId: String
    var accepted: Bool
    var reason: RemoteCommandRejectReason?
    var outcome: RemoteCommandAckOutcome
    var serverTime: Date?
    var auditTs: Date
    var auditDeviceId: String
    var auditCommandKind: RemoteCommandKind
    var auditTargetSummary: String
    var sig: String
    var createdAt: Date

    init(_ envelope: RemoteCommandAckEnvelope) {
        requestId = envelope.requestId
        accountId = envelope.accountId
        macAgentId = envelope.macAgentId
        accepted = envelope.ack.accepted
        reason = envelope.ack.reason
        outcome = envelope.ack.outcome
        serverTime = envelope.ack.serverTime
        auditTs = envelope.auditEvent.ts
        auditDeviceId = envelope.auditEvent.deviceId
        auditCommandKind = envelope.auditEvent.commandKind
        auditTargetSummary = envelope.auditEvent.targetSummary
        sig = envelope.ack.signature
        createdAt = envelope.createdAt
    }

    func envelope() -> RemoteCommandAckEnvelope {
        let ack = CommandAck(
            requestId: requestId,
            accepted: accepted,
            reason: reason,
            outcome: outcome,
            serverTime: serverTime,
            signature: sig
        )
        let audit = RemoteAuditEvent(
            ts: auditTs,
            deviceId: auditDeviceId,
            commandKind: auditCommandKind,
            requestId: requestId,
            targetSummary: auditTargetSummary,
            outcome: outcome
        )
        return RemoteCommandAckEnvelope(
            requestId: requestId,
            accountId: accountId,
            macAgentId: macAgentId,
            ack: ack,
            auditEvent: audit,
            createdAt: createdAt
        )
    }
}

public struct EventEnvelopeRow: Codable {
    var id: String
    var seq: Int64
    var ts: Date
    var accountId: String
    var macAgentId: String
    var runId: String?
    var kind: String
    var lightPayload: [String: JSONValue]
    var sealedRef: MediaRef?
    var sig: String

    public init(accountId: String, envelope: RemoteRunEventEnvelope) {
        id = envelope.event.id
        seq = envelope.event.seq
        ts = envelope.event.ts
        self.accountId = accountId
        macAgentId = envelope.macAgentId
        runId = envelope.event.payload["runId"]?.stringValue
        kind = envelope.event.kind
        lightPayload = envelope.event.payload
        sealedRef = envelope.sealedRef
        sig = envelope.signature
    }

    func envelope() -> RemoteRunEventEnvelope {
        RemoteRunEventEnvelope(
            macAgentId: macAgentId,
            event: RunEvent(id: id, seq: seq, ts: ts, kind: kind, payload: lightPayload),
            sealedRef: sealedRef,
            signature: sig
        )
    }
}

private struct SnapshotEnvelopeRow: Codable {
    var accountId: String
    var macAgentId: String
    var runs: [TeamRunLight]
    var lastSeq: Int64
    var serverTime: Date
    var protocolVersion: Int
    var updatedAt: Date

    init(accountId: String, macAgentId: String, snapshot: SnapshotEnvelope, updatedAt: Date) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        runs = snapshot.runs
        lastSeq = snapshot.lastSeq
        serverTime = snapshot.serverTime
        protocolVersion = snapshot.protocolVersion
        self.updatedAt = updatedAt
    }

    func envelope() -> SnapshotEnvelope {
        SnapshotEnvelope(
            runs: runs,
            lastSeq: lastSeq,
            serverTime: serverTime,
            protocolVersion: protocolVersion
        )
    }
}

private struct ThreadSnapshotEnvelopeRow: Codable {
    var accountId: String
    var macAgentId: String
    var threads: [RemoteThreadSummary]
    var serverTime: Date
    var protocolVersion: Int
    var updatedAt: Date

    init(accountId: String, macAgentId: String, snapshot: RemoteThreadSnapshotEnvelope, updatedAt: Date) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        threads = snapshot.threads
        serverTime = snapshot.serverTime
        protocolVersion = snapshot.protocolVersion
        self.updatedAt = updatedAt
    }

    func envelope() -> RemoteThreadSnapshotEnvelope {
        RemoteThreadSnapshotEnvelope(
            threads: threads,
            protocolVersion: protocolVersion,
            serverTime: serverTime
        )
    }
}

private struct ThreadDetailBlobRow: Codable {
    var accountId: String
    var macAgentId: String
    var threadId: String
    var deviceId: String
    var sealedDetail: SealedBlob
    var updatedAt: Date

    init(
        accountId: String,
        macAgentId: String,
        threadId: String,
        deviceId: String,
        sealedDetail: SealedBlob,
        updatedAt: Date
    ) {
        self.accountId = accountId
        self.macAgentId = macAgentId
        self.threadId = threadId
        self.deviceId = deviceId
        self.sealedDetail = sealedDetail
        self.updatedAt = updatedAt
    }
}

private struct MediaRefRow: Codable {
    var ref: String
    var macAgentId: String
    var r2Key: String
    var contentType: String
    var expiresAt: Date

    init(_ ref: MediaRef) {
        self.ref = ref.ref
        macAgentId = ref.macAgentId
        r2Key = ref.r2Key
        contentType = ref.contentType
        expiresAt = ref.expiresAt
    }
}

private struct MediaKeyRow: Codable {
    var ref: String
    var macAgentId: String
    var deviceId: String
    var sealedKey: SealedBlob

    init(_ key: MediaKeyEnvelope) {
        ref = key.ref
        macAgentId = key.macAgentId
        deviceId = key.deviceId
        sealedKey = key.sealedKey
    }

    func model() -> MediaKeyEnvelope {
        MediaKeyEnvelope(ref: ref, macAgentId: macAgentId, deviceId: deviceId, sealedKey: sealedKey)
    }
}
