import Foundation

public enum RemoteAuthClaimsError: Error, Equatable, Sendable {
    case http(statusCode: Int, body: String)
    case decodeFailed(String)
}

/// Provisions relay JWT claims through authenticated PostgREST RPCs.
public struct RemoteAuthClaimsClient: Sendable {
    public var supabaseURL: URL
    public var publishableKey: String
    public var accessToken: String
    public var transport: any SupabaseHTTPTransport

    public init(
        supabaseURL: URL,
        publishableKey: String,
        accessToken: String,
        transport: any SupabaseHTTPTransport = URLSessionSupabaseHTTPTransport()
    ) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.accessToken = accessToken
        self.transport = transport
    }

    public func provisionMacAgentClaim(macAgentId: String) async throws {
        _ = try await callRPC(
            name: "provision_mac_agent_claim",
            body: ["p_mac_agent_id": macAgentId]
        )
    }

    public func provisionRemoteDeviceClaim(deviceId: String) async throws {
        _ = try await callRPC(
            name: "provision_remote_device_claim",
            body: ["p_remote_device_id": deviceId]
        )
    }

    private func callRPC(name: String, body: [String: String]) async throws -> Data {
        let url = supabaseURL
            .appendingPathComponent("rest/v1/rpc")
            .appendingPathComponent(name)
        let response = try await transport.send(SupabaseHTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "apikey": publishableKey,
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: try CoreJSON.encode(body)
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw RemoteAuthClaimsError.http(
                statusCode: response.statusCode,
                body: String(decoding: response.data, as: UTF8.self)
            )
        }
        return response.data
    }
}

public enum RemoteAuthClaimsProvisioner {
    public static func provisionMacAgent(
        session: RemoteSupabaseSession,
        macAgentId: String,
        publicConfig: RemoteSupabasePublicConfig.Values,
        authClient: RemoteSupabaseAuthClient,
        transport: any SupabaseHTTPTransport = URLSessionSupabaseHTTPTransport()
    ) async throws -> RemoteSupabaseSession {
        let claims = RemoteAuthClaimsClient(
            supabaseURL: publicConfig.supabaseURL,
            publishableKey: publicConfig.publishableKey,
            accessToken: session.accessToken,
            transport: transport
        )
        try await claims.provisionMacAgentClaim(macAgentId: macAgentId)
        return try await authClient.refreshSession(refreshToken: session.refreshToken, provider: session.provider)
    }

    public static func provisionDevice(
        session: RemoteSupabaseSession,
        deviceId: String,
        publicConfig: RemoteSupabasePublicConfig.Values,
        authClient: RemoteSupabaseAuthClient,
        transport: any SupabaseHTTPTransport = URLSessionSupabaseHTTPTransport()
    ) async throws -> RemoteSupabaseSession {
        let claims = RemoteAuthClaimsClient(
            supabaseURL: publicConfig.supabaseURL,
            publishableKey: publicConfig.publishableKey,
            accessToken: session.accessToken,
            transport: transport
        )
        try await claims.provisionRemoteDeviceClaim(deviceId: deviceId)
        return try await authClient.refreshSession(refreshToken: session.refreshToken, provider: session.provider)
    }
}
