import Foundation

/// Env-only credential resolution for the OpenCode Go dogfood spike (OCG-S02).
/// Promotion may add encrypted file storage; spike deliberately avoids Keychain/TCC.
public enum OpenCodeGoCredentialStore {

    public static let workspaceIdEnv = "OPENCODE_GO_WORKSPACE_ID"
    public static let authCookieEnv = "OPENCODE_GO_AUTH_COOKIE"

    public struct Credentials: Sendable, Equatable {
        public let workspaceId: String
        public let authCookie: String

        public init(workspaceId: String, authCookie: String) {
            self.workspaceId = workspaceId
            self.authCookie = authCookie
        }
    }

    public enum LoadError: Sendable, Equatable, Error {
        case partialEnvironment
        case missingWorkspaceId
        case missingAuthCookie
    }

    /// Both env vars must be set and non-empty; partial env is a hard refusal.
    public static func loadFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Result<Credentials, LoadError> {
        let workspace = environment[workspaceIdEnv]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = environment[authCookieEnv]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWorkspace = workspace.map { !$0.isEmpty } ?? false
        let hasCookie = cookie.map { !$0.isEmpty } ?? false
        if hasWorkspace != hasCookie {
            return .failure(.partialEnvironment)
        }
        guard hasWorkspace, hasCookie, let workspace, let cookie else {
            if !hasWorkspace { return .failure(.missingWorkspaceId) }
            return .failure(.missingAuthCookie)
        }
        return .success(Credentials(workspaceId: workspace, authCookie: cookie))
    }
}
