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

    // MARK: - Workspace discovery

    /// Local OpenCode CLI state that may already name the workspace.
    static func opencodeStateFiles(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".local/share/opencode/opencode.db"),
            home.appendingPathComponent(".local/share/opencode/auth.json"),
            home.appendingPathComponent(".config/opencode/config.json"),
        ]
    }

    /// Chromium user-data roots that exist on a typical Mac. History DBs are
    /// plaintext SQLite (no Keychain). Cookie values are a different store.
    public static func chromiumUserDataRoots(home: URL) -> [URL] {
        let appSupport = home.appendingPathComponent(
            "Library/Application Support", isDirectory: true
        )
        return [
            appSupport.appendingPathComponent("Google/Chrome", isDirectory: true),
            appSupport.appendingPathComponent("BraveSoftware/Brave-Browser", isDirectory: true),
            appSupport.appendingPathComponent("Microsoft Edge", isDirectory: true),
            appSupport.appendingPathComponent("Arc/User Data", isDirectory: true),
        ]
    }

    /// Recover the workspace id from local OpenCode CLI state and Chromium
    /// history so setup does not have to ask for something the machine already
    /// knows.
    ///
    /// The id is NOT a secret — it is a path segment in the dashboard URL — so
    /// reading it costs nothing in exposure. OpenCode state is scanned bytewise
    /// for the `wrk_` token rather than parsed, because `opencode.db` is SQLite
    /// and its schema is not ours to depend on. Browser History is copied then
    /// read read-only (Chrome holds a lock on the live file). Returns nil
    /// unless exactly one distinct id is present across every source: two
    /// would mean a genuine choice, and guessing which workspace to meter is
    /// precisely the kind of silent inference this project bans.
    public static func discoverWorkspaceId(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) -> String? {
        var found = Set<String>()
        for url in opencodeStateFiles(home: home) {
            guard let data = try? Data(contentsOf: url) else { continue }
            found.formUnion(workspaceIds(in: data))
        }
        for url in chromiumHistoryDatabases(home: home, fileManager: fileManager) {
            found.formUnion(workspaceIdsFromHistoryDatabase(at: url, fileManager: fileManager))
        }
        return found.count == 1 ? found.first : nil
    }

    /// `History` files under every Chromium profile that exists on this home.
    static func chromiumHistoryDatabases(
        home: URL,
        fileManager: FileManager
    ) -> [URL] {
        var out: [URL] = []
        for root in chromiumUserDataRoots(home: home) {
            guard let kids = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for profile in kids {
                let history = profile.appendingPathComponent("History")
                if fileManager.fileExists(atPath: history.path) {
                    out.append(history)
                }
            }
        }
        return out
    }

    /// Copy the History DB (Chrome holds a lock) and read it read-only.
    /// Never logs URL query strings — we only harvest `wrk_` path segments.
    static func workspaceIdsFromHistoryDatabase(
        at url: URL,
        fileManager: FileManager
    ) -> Set<String> {
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("alln-chromium-history-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return []
        }
        defer { try? fileManager.removeItem(at: tempDir) }

        let dest = tempDir.appendingPathComponent("History")
        do {
            try fileManager.copyItem(at: url, to: dest)
        } catch {
            return []
        }
        // WAL/SHM sit beside History. Copy when present so a locked live DB
        // still yields recent visits after the snapshot.
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: side.path) {
                try? fileManager.copyItem(
                    at: side,
                    to: URL(fileURLWithPath: dest.path + suffix)
                )
            }
        }

        if let queried = workspaceIdsFromHistorySQLite(at: dest), !queried.isEmpty {
            return queried
        }
        guard let data = try? Data(contentsOf: dest) else { return [] }
        return workspaceIds(in: data)
    }

    /// Prefer a targeted URL query over a whole-file byte scan.
    private static func workspaceIdsFromHistorySQLite(at url: URL) -> Set<String>? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [
            "-readonly",
            url.path,
            "select url from urls where url like '%opencode.ai%'",
        ]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let output = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        return workspaceIds(in: output)
    }

    /// `wrk_` followed by the id's alphanumeric body, scanned over raw bytes.
    static func workspaceIds(in data: Data) -> Set<String> {
        let marker = Array("wrk_".utf8)
        let bytes = [UInt8](data)
        var out = Set<String>()
        guard bytes.count > marker.count else { return out }
        for start in 0...(bytes.count - marker.count) where Array(bytes[start..<start + marker.count]) == marker {
            var end = start + marker.count
            while end < bytes.count, isIdentifierByte(bytes[end]) { end += 1 }
            let body = end - (start + marker.count)
            // Real ids are long; a short run is noise, not an id.
            guard body >= 10 else { continue }
            if let id = String(bytes: bytes[start..<end], encoding: .utf8) { out.insert(id) }
        }
        return out
    }

    private static func isIdentifierByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
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
