import Foundation

/// Credential resolution for the OpenCode Go dashboard scrape.
///
/// Two sources, in strict order: environment override first (both-or-neither),
/// then an AES-GCM file under Application Support. No Keychain — a Keychain
/// item prompts on first use and breaks headless/detached runs, which is
/// exactly the path this feature lives on.
public enum OpenCodeGoCredentialStore {

    public static let workspaceIdEnv = "OPENCODE_GO_WORKSPACE_ID"
    public static let authCookieEnv = "OPENCODE_GO_AUTH_COOKIE"

    public struct Credentials: Sendable, Equatable, Codable {
        public let workspaceId: String
        public let authCookie: String

        public init(workspaceId: String, authCookie: String) {
            self.workspaceId = workspaceId
            self.authCookie = authCookie
        }
    }

    /// Where a resolved credential came from. Surfaced by `status`; never
    /// carries the secret itself.
    public enum Source: String, Sendable, Equatable, Codable {
        case environment
        case encryptedFile
    }

    public enum LoadError: Sendable, Equatable, Error {
        case partialEnvironment
        case missingWorkspaceId
        case missingAuthCookie
        /// A stored credential exists but could not be decrypted or decoded —
        /// rotated or corrupt machine key, truncated or tampered file. Distinct
        /// from "not configured": the caller must surface `authRequired` and
        /// never silently retry with an empty cookie.
        case decryptFailed
        case notConfigured
    }

    public struct Resolved: Sendable, Equatable {
        public let credentials: Credentials
        public let source: Source

        public init(credentials: Credentials, source: Source) {
            self.credentials = credentials
            self.source = source
        }
    }

    // MARK: - Paths

    static var machineKeyURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("machine.key")
    }

    static var credentialFileURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("opencode_go.enc")
    }

    // MARK: - Resolution

    /// Environment override wins when both vars are set. Partial env is a hard
    /// refusal rather than a fall-through to the file — a half-set environment
    /// is far likelier to be a mistake than an intention, and falling back
    /// would scrape with credentials the caller did not mean to use.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialURL: URL? = nil,
        keyURL: URL? = nil
    ) -> Result<Resolved, LoadError> {
        switch loadFromEnvironment(environment: environment) {
        case .success(let creds):
            return .success(Resolved(credentials: creds, source: .environment))
        case .failure(.partialEnvironment):
            return .failure(.partialEnvironment)
        case .failure:
            break
        }
        return loadFromFile(credentialURL: credentialURL, keyURL: keyURL)
            .map { Resolved(credentials: $0, source: .encryptedFile) }
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

    // MARK: - Encrypted file

    public static func loadFromFile(
        credentialURL: URL? = nil,
        keyURL: URL? = nil
    ) -> Result<Credentials, LoadError> {
        let credentialURL = credentialURL ?? credentialFileURL
        let keyURL = keyURL ?? machineKeyURL
        guard FileManager.default.fileExists(atPath: credentialURL.path) else {
            return .failure(.notConfigured)
        }
        do {
            let key = try Data(contentsOf: keyURL)
            let ciphertext = try Data(contentsOf: credentialURL)
            let plaintext = try RemoteMediaCrypto.decrypt(ciphertext, contentKey: key)
            let creds = try JSONDecoder().decode(Credentials.self, from: plaintext)
            guard !creds.workspaceId.isEmpty, !creds.authCookie.isEmpty else {
                return .failure(.decryptFailed)
            }
            return .success(creds)
        } catch {
            // Missing key, rotated key, truncated file, tampered ciphertext, or
            // a schema change all land here. Every one of them means "we hold
            // something we cannot use" — never "not configured", which would
            // invite a retry with no cookie.
            return .failure(.decryptFailed)
        }
    }

    /// Encrypt and persist. Creates the machine key on first use.
    @discardableResult
    public static func save(
        _ credentials: Credentials,
        credentialURL: URL? = nil,
        keyURL: URL? = nil
    ) throws -> URL {
        let credentialURL = credentialURL ?? credentialFileURL
        let keyURL = keyURL ?? machineKeyURL
        try FileManager.default.createDirectory(
            at: credentialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let key = try loadOrCreateMachineKey(at: keyURL)
        let plaintext = try JSONEncoder().encode(credentials)
        let ciphertext = try RemoteMediaCrypto.encrypt(plaintext, contentKey: key)
        try writeOwnerOnly(ciphertext, to: credentialURL)
        return credentialURL
    }

    static func loadOrCreateMachineKey(at url: URL) throws -> Data {
        if let existing = try? Data(contentsOf: url),
           existing.count == RemoteMediaCrypto.contentKeyByteCount {
            return existing
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let key = RemoteMediaCrypto.randomContentKey()
        try writeOwnerOnly(key, to: url)
        return key
    }

    /// Owner-only (0600) from the moment the file is reachable: written to a
    /// temp sibling, chmod'd there, and only then moved into place. Writing
    /// first and chmod'ing after would leave a readable window containing a
    /// live session cookie.
    private static func writeOwnerOnly(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
