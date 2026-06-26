import Foundation

/// Public Supabase relay settings read from process environment.
/// Secrets (access tokens) stay in env or secure storage — never in repo config.
public struct RemoteSupabaseEnvironment: Equatable, Sendable {
    public var supabaseURL: URL
    public var publishableKey: String
    public var accessToken: String?
    public var accountId: String?
    public var accountProvider: RemoteAccountSession.Provider
    public var macAgentId: String?
    public var macDisplayName: String?
    public var deviceAccessToken: String?

    public init(
        supabaseURL: URL,
        publishableKey: String,
        accessToken: String? = nil,
        accountId: String? = nil,
        accountProvider: RemoteAccountSession.Provider = .apple,
        macAgentId: String? = nil,
        macDisplayName: String? = nil,
        deviceAccessToken: String? = nil
    ) {
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
        self.accessToken = accessToken
        self.accountId = accountId
        self.accountProvider = accountProvider
        self.macAgentId = macAgentId
        self.macDisplayName = macDisplayName
        self.deviceAccessToken = deviceAccessToken
    }

    public var hasMacAgentCredentials: Bool {
        guard let accessToken, !accessToken.isEmpty else { return false }
        guard let accountId, !accountId.isEmpty else { return false }
        return true
    }

    public var hasDeviceCredentials: Bool {
        guard let token = deviceAccessToken ?? accessToken, !token.isEmpty else { return false }
        guard let accountId, !accountId.isEmpty else { return false }
        return true
    }

    public func macAccountSession() -> RemoteAccountSession? {
        guard let accountId, !accountId.isEmpty else { return nil }
        return RemoteAccountSession(accountId: accountId, provider: accountProvider)
    }

    public func deviceAccountSession() -> RemoteAccountSession? {
        macAccountSession()
    }

    public func deviceAccessTokenValue() -> String? {
        let token = deviceAccessToken ?? accessToken
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    public static func load(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RemoteSupabaseEnvironment? {
        if let fromEnvironment = loadFromEnvironment(environment) {
            return fromEnvironment
        }
        return loadFromSessionStore()
    }

    public static func loadFromEnvironment(_ environment: [String: String]) -> RemoteSupabaseEnvironment? {
        guard let urlString = trimmed(environment["ALLNIGHTER_SUPABASE_URL"]),
              let url = URL(string: urlString),
              url.scheme != nil,
              url.host != nil,
              let publishableKey = trimmed(environment["ALLNIGHTER_SUPABASE_PUBLISHABLE_KEY"])
        else {
            return nil
        }

        let providerRaw = trimmed(environment["ALLNIGHTER_REMOTE_ACCOUNT_PROVIDER"]) ?? "apple"
        let provider = RemoteAccountSession.Provider(rawValue: providerRaw) ?? .apple

        return RemoteSupabaseEnvironment(
            supabaseURL: url,
            publishableKey: publishableKey,
            accessToken: trimmed(environment["ALLNIGHTER_SUPABASE_ACCESS_TOKEN"]),
            accountId: trimmed(environment["ALLNIGHTER_REMOTE_ACCOUNT_ID"]),
            accountProvider: provider,
            macAgentId: trimmed(environment["ALLNIGHTER_REMOTE_MAC_AGENT_ID"]),
            macDisplayName: trimmed(environment["ALLNIGHTER_REMOTE_MAC_DISPLAY_NAME"]),
            deviceAccessToken: trimmed(environment["ALLNIGHTER_SUPABASE_DEVICE_ACCESS_TOKEN"])
        )
    }

    public static func loadFromSessionStore(
        publicConfig: RemoteSupabasePublicConfig.Values? = RemoteSupabasePublicConfig.load(),
        sessionStore: RemoteSupabaseSessionStore = RemoteSupabaseSessionStore(),
        macCredentialStore: RemoteMacAgentCredentialStore = RemoteMacAgentCredentialStore()
    ) -> RemoteSupabaseEnvironment? {
        guard let publicConfig,
              let session = try? sessionStore.load() else {
            return nil
        }

        let macCredentials = try? macCredentialStore.load()

        return session.makeEnvironment(
            publicConfig: publicConfig,
            macAgentId: macCredentials?.macAgentId,
            macDisplayName: macCredentials?.displayName ?? ProcessInfo.processInfo.hostName
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
