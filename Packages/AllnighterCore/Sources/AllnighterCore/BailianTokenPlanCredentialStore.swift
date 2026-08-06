import Foundation

/// Credential resolution for the Bailian Token Plan Personal dashboard scrape.
public enum BailianTokenPlanCredentialStore {

    public static let cookieEnv = "BAILIAN_TOKEN_PLAN_COOKIE"

    public struct Credentials: Sendable, Equatable, Codable {
        public let cookieHeader: String

        public init(cookieHeader: String) {
            self.cookieHeader = cookieHeader
        }
    }

    public enum Source: String, Sendable, Equatable, Codable {
        case environment
        case encryptedFile
    }

    public enum LoadError: Sendable, Equatable, Error {
        case missingCookie
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

    static var credentialFileURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("bailian_token_plan.enc")
    }

    static var machineKeyURL: URL {
        AllnighterSupportRoot.config.appendingPathComponent("machine.key")
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialURL: URL? = nil,
        keyURL: URL? = nil
    ) -> Result<Resolved, LoadError> {
        if let cookie = environment[cookieEnv]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cookie.isEmpty
        {
            return .success(Resolved(credentials: .init(cookieHeader: cookie), source: .environment))
        }
        return loadFromFile(credentialURL: credentialURL, keyURL: keyURL)
            .map { Resolved(credentials: $0, source: .encryptedFile) }
    }

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
            guard !creds.cookieHeader.isEmpty else { return .failure(.decryptFailed) }
            return .success(creds)
        } catch {
            return .failure(.decryptFailed)
        }
    }

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
        let key = try OpenCodeGoCredentialStore.loadOrCreateMachineKey(at: keyURL)
        let plaintext = try JSONEncoder().encode(credentials)
        let ciphertext = try RemoteMediaCrypto.encrypt(plaintext, contentKey: key)
        try writeOwnerOnly(ciphertext, to: credentialURL)
        return credentialURL
    }

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
