import Foundation

public actor RefreshingSupabaseAccessTokenProvider: SupabaseAccessTokenProviding {
    private var session: RemoteSupabaseSession
    private let authClient: RemoteSupabaseAuthClient
    private let sessionStore: RemoteSupabaseSessionStore

    public init(
        session: RemoteSupabaseSession,
        authClient: RemoteSupabaseAuthClient,
        sessionStore: RemoteSupabaseSessionStore = RemoteSupabaseSessionStore()
    ) {
        self.session = session
        self.authClient = authClient
        self.sessionStore = sessionStore
    }

    public func accessToken() async throws -> String {
        if session.isExpired() {
            session = try await authClient.refreshSession(refreshToken: session.refreshToken)
            try sessionStore.save(session)
        }
        return session.accessToken
    }

    public func currentSession() -> RemoteSupabaseSession {
        session
    }
}
