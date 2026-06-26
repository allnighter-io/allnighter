import Foundation

public struct RemoteSupabaseSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userId: String
    public var provider: RemoteAccountSession.Provider

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        userId: String,
        provider: RemoteAccountSession.Provider
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
        self.provider = provider
    }

    public var accountSession: RemoteAccountSession {
        RemoteAccountSession(accountId: userId, provider: provider)
    }

    public func isExpired(at now: Date = Date(), refreshLeeway: TimeInterval = 120) -> Bool {
        now.addingTimeInterval(refreshLeeway) >= expiresAt
    }
}

public enum RemoteSupabaseAuthError: Error, Equatable, Sendable {
    case missingPublicConfig
    case invalidResponse(String)
    case http(statusCode: Int, body: String)
    case missingAccessToken
    case missingRefreshToken
    case missingUserId
}

public struct RemoteSupabaseAuthClient: Sendable {
    public var supabaseURL: URL
    public var publishableKey: String
    public var transport: any SupabaseHTTPTransport

    public init(
        supabaseURL: URL,
        publishableKey: String,
        transport: any SupabaseHTTPTransport = URLSessionSupabaseHTTPTransport()
    ) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.transport = transport
    }

    public init?(publicConfig: RemoteSupabasePublicConfig.Values, transport: any SupabaseHTTPTransport = URLSessionSupabaseHTTPTransport()) {
        self.init(
            supabaseURL: publicConfig.supabaseURL,
            publishableKey: publicConfig.publishableKey,
            transport: transport
        )
    }

    public func signInWithApple(idToken: String, nonce: String) async throws -> RemoteSupabaseSession {
        try await exchangeToken(
            grantType: "id_token",
            body: [
                "provider": "apple",
                "id_token": idToken,
                "nonce": nonce,
            ],
            provider: .apple
        )
    }

    public func refreshSession(refreshToken: String, provider: RemoteAccountSession.Provider = .apple) async throws -> RemoteSupabaseSession {
        try await exchangeToken(
            grantType: "refresh_token",
            body: ["refresh_token": refreshToken],
            provider: provider
        )
    }

    private func exchangeToken(
        grantType: String,
        body: [String: String],
        provider: RemoteAccountSession.Provider
    ) async throws -> RemoteSupabaseSession {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components?.url else {
            throw RemoteSupabaseAuthError.invalidResponse("invalid auth url")
        }

        let response = try await transport.send(SupabaseHTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "apikey": publishableKey,
                "Content-Type": "application/json",
            ],
            body: try CoreJSON.encode(body)
        ))

        guard (200..<300).contains(response.statusCode) else {
            throw RemoteSupabaseAuthError.http(
                statusCode: response.statusCode,
                body: String(decoding: response.data, as: UTF8.self)
            )
        }

        let payload = try CoreJSON.decode(AuthTokenResponse.self, from: response.data)
        guard let accessToken = payload.access_token, !accessToken.isEmpty else {
            throw RemoteSupabaseAuthError.missingAccessToken
        }
        guard let refreshToken = payload.refresh_token, !refreshToken.isEmpty else {
            throw RemoteSupabaseAuthError.missingRefreshToken
        }
        guard let userId = payload.user?.id ?? decodeJWTSubject(accessToken) else {
            throw RemoteSupabaseAuthError.missingUserId
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(payload.expires_in ?? 3600))
        return RemoteSupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            provider: provider
        )
    }

    private struct AuthTokenResponse: Decodable {
        var access_token: String?
        var refresh_token: String?
        var expires_in: Int?
        var user: AuthUserResponse?
    }

    private struct AuthUserResponse: Decodable {
        var id: String
    }

    private struct JWTClaimsProbe: Decodable {
        var sub: String?
        var provider: String?
    }

    private func decodeJWTSubject(_ token: String) -> String? {
        try? decodeJWTClaims(token).sub
    }

    private func decodeJWTClaims(_ token: String) throws -> JWTClaimsProbe {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw RemoteSupabaseAuthError.invalidResponse("invalid jwt")
        }
        var payload = String(parts[1])
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) else {
            throw RemoteSupabaseAuthError.invalidResponse("invalid jwt payload")
        }
        return try CoreJSON.decode(JWTClaimsProbe.self, from: data)
    }
}
