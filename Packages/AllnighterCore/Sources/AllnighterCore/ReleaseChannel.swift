import Foundation

// MARK: - Public projection

/// Agent-facing update announcement (menu / version / doctor).
///
/// Present only when a newer release is known. Omitted entirely from JSON when
/// there is nothing to announce (current ≥ latest, check failed, disabled,
/// future schema). Never carries remote `notes` or remote `installCommand`.
public struct ReleaseUpdateInfo: Codable, Sendable, Equatable {
    public var available: Bool
    public var current: String
    public var latest: String
    public var binaryPath: String?
    /// Always the compiled-in one-liner — never a remote string (law 9 / BUG-4).
    public var command: String

    public init(
        available: Bool = true,
        current: String,
        latest: String,
        binaryPath: String? = nil,
        command: String = ReleaseChannel.installCommand
    ) {
        self.available = available
        self.current = current
        self.latest = latest
        self.binaryPath = binaryPath
        self.command = command
    }
}

// MARK: - Wire manifest

/// `latest.json` wire shape (OPC-S06). Unknown fields are ignored by Codable.
public struct ReleaseManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var cliVersion: String
    public var appVersion: String
    public var releasedAt: String?
    public var notes: String?
    public var installCommand: String?
    public var cli: Asset?
    public var app: Asset?

    public struct Asset: Codable, Sendable, Equatable {
        public var url: String
        public var sha256: String

        public init(url: String, sha256: String) {
            self.url = url
            self.sha256 = sha256
        }
    }

    public init(
        schemaVersion: Int,
        cliVersion: String,
        appVersion: String,
        releasedAt: String? = nil,
        notes: String? = nil,
        installCommand: String? = nil,
        cli: Asset? = nil,
        app: Asset? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.cliVersion = cliVersion
        self.appVersion = appVersion
        self.releasedAt = releasedAt
        self.notes = notes
        self.installCommand = installCommand
        self.cli = cli
        self.app = app
    }
}

// MARK: - Semver

/// Numeric major.minor.patch compare for release strings.
///
/// Malformed input yields `nil` — never crash, never guess, never announce.
public struct ReleaseVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `X.Y.Z` with optional leading `v`. Rejects pre-release / build
    /// suffixes and non-numeric components (no announcement for those).
    public static func parse(_ raw: String) -> ReleaseVersion? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0,
              let patch = Int(parts[2]), patch >= 0
        else { return nil }
        // Reject trailing garbage that Int would ignore (e.g. "1.2.3-beta").
        guard String(parts[0]) == "\(major)",
              String(parts[1]) == "\(minor)",
              String(parts[2]) == "\(patch)"
        else { return nil }
        return ReleaseVersion(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - HTTP fetch (injectable)

/// Synchronous GET for `latest.json`. Production uses URLSession with a hard
/// request timeout; tests inject a mock so XCTest never hits the network.
public protocol ReleaseHTTPFetching: Sendable {
    func fetch(url: URL, timeout: TimeInterval) throws -> Data
}

public struct URLSessionReleaseHTTPFetcher: ReleaseHTTPFetching {
    public init() {}

    public func fetch(url: URL, timeout: TimeInterval) throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let box = FetchBox()
        let sem = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: url) { data, response, error in
            box.finish(data: data, response: response, error: error)
            sem.signal()
        }
        task.resume()
        let wait = sem.wait(timeout: .now() + timeout + 0.5)
        if wait == .timedOut {
            task.cancel()
            throw ReleaseChannelError.timeout
        }
        return try box.result()
    }

    /// Tiny thread-safe result box — URLSession callbacks leave the cooperative pool.
    private final class FetchBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private var response: URLResponse?
        private var error: Error?

        func finish(data: Data?, response: URLResponse?, error: Error?) {
            lock.lock()
            defer { lock.unlock() }
            self.data = data
            self.response = response
            self.error = error
        }

        func result() throws -> Data {
            lock.lock()
            defer { lock.unlock() }
            if let error { throw error }
            guard let http = response as? HTTPURLResponse else {
                throw ReleaseChannelError.nonHTTPResponse
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw ReleaseChannelError.httpStatus(http.statusCode)
            }
            guard let data, !data.isEmpty else {
                throw ReleaseChannelError.emptyBody
            }
            return data
        }
    }
}

public enum ReleaseChannelError: Error, Sendable, Equatable {
    case timeout
    case nonHTTPResponse
    case httpStatus(Int)
    case emptyBody
}

// MARK: - Cache record

/// On-disk cache at `…/Allnighter/Release/latest-check.json`.
public struct ReleaseCheckRecord: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    /// When set and `now < nextAttemptAt`, skip the network (failure backoff).
    public var nextAttemptAt: Date?
    /// Last successfully decoded manifest (may be nil after a pure failure write).
    public var manifest: ReleaseManifest?

    public init(fetchedAt: Date, nextAttemptAt: Date? = nil, manifest: ReleaseManifest? = nil) {
        self.fetchedAt = fetchedAt
        self.nextAttemptAt = nextAttemptAt
        self.manifest = manifest
    }
}

// MARK: - Channel owner

/// Shared release channel: one-liner constant + cached `latest.json` check.
///
/// **One owner, three projections** (menu / version --json / doctor) plus
/// `alln update --check`. Never call from `alln run` or loop dispatch — menu,
/// version, doctor, and update only. Auto-apply is out of scope (BQ-4).
///
/// Remote `installCommand` and `notes` are decoded for completeness but **never**
/// projected or executed (law 9 / BUG-4).
public enum ReleaseChannel {
    /// Public install and upgrade command. Never invent cousins; cite this string.
    public static let installCommand = "curl -fsSL https://get.allnighter.app | sh"

    /// Highest `latest.json` schemaVersion this binary understands.
    public static let knownManifestSchemaVersion = 1

    public static let defaultBaseURL = "https://get.allnighter.app"
    public static let cacheTTL: TimeInterval = 24 * 60 * 60
    public static let fetchTimeout: TimeInterval = 2
    public static let failureBackoff: TimeInterval = 60 * 60
    /// Clock-skew / tamper: fetchedAt more than this far in the future → stale.
    public static let futureSkewTolerance: TimeInterval = 5 * 60

    public static let noUpdateCheckEnvKey = "ALLN_NO_UPDATE_CHECK"
    public static let baseURLEnvKey = "ALLN_INSTALL_BASE_URL"

    /// `…/Allnighter/Release/` (honors `ALLNIGHTER_SUPPORT_DIR`).
    public static var releaseDirectory: URL {
        AllnighterSupportRoot.support.appendingPathComponent("Release", isDirectory: true)
    }

    /// `…/Allnighter/Release/latest-check.json`
    public static var defaultCacheURL: URL {
        releaseDirectory.appendingPathComponent("latest-check.json")
    }

    /// Resolve whether a newer CLI release should be announced.
    ///
    /// Returns `nil` (caller omits the `update` key) when disabled, equal/newer
    /// current, malformed versions, unknown future schema, or no usable data.
    public static func checkUpdate(
        currentVersion: String = AllnighterVersionIdentity.binaryVersion,
        binaryPath: String? = nil,
        now: Date = Date(),
        cacheURL: URL? = nil,
        fetcher: (any ReleaseHTTPFetching)? = nil,
        environment: [String: String]? = nil
    ) -> ReleaseUpdateInfo? {
        let env = environment ?? ProcessInfo.processInfo.environment
        if isUpdateCheckDisabled(environment: env) {
            return nil
        }

        let cachePath = cacheURL ?? defaultCacheURL
        let activeFetcher = fetcher ?? URLSessionReleaseHTTPFetcher()
        let record = loadOrRefresh(
            now: now,
            cacheURL: cachePath,
            fetcher: activeFetcher,
            environment: env
        )
        guard let manifest = record?.manifest else { return nil }
        return announce(
            manifest: manifest,
            currentVersion: currentVersion,
            binaryPath: binaryPath
        )
    }

    /// Decode + schema gate only (no network). Future schema → nil.
    public static func decodeManifest(_ data: Data) -> ReleaseManifest? {
        guard let manifest = try? JSONDecoder().decode(ReleaseManifest.self, from: data) else {
            return nil
        }
        guard manifest.schemaVersion <= knownManifestSchemaVersion else {
            return nil
        }
        return manifest
    }

    /// Pure announce decision from an already-trusted manifest.
    public static func announce(
        manifest: ReleaseManifest,
        currentVersion: String,
        binaryPath: String? = nil
    ) -> ReleaseUpdateInfo? {
        guard manifest.schemaVersion <= knownManifestSchemaVersion else { return nil }
        guard let current = ReleaseVersion.parse(currentVersion),
              let latest = ReleaseVersion.parse(manifest.cliVersion)
        else { return nil }
        guard current < latest else { return nil }
        return ReleaseUpdateInfo(
            available: true,
            current: currentVersion,
            latest: manifest.cliVersion,
            binaryPath: binaryPath,
            command: installCommand
        )
    }

    public static func isUpdateCheckDisabled(environment: [String: String]) -> Bool {
        guard let raw = environment[noUpdateCheckEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return false }
        switch raw.lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }

    public static func baseURL(environment: [String: String]) -> URL {
        let raw = environment[baseURLEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = (raw?.isEmpty == false ? raw! : defaultBaseURL)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: s) ?? URL(string: defaultBaseURL)!
    }

    public static func latestJSONURL(environment: [String: String]) -> URL {
        baseURL(environment: environment).appendingPathComponent("latest.json")
    }

    // MARK: Cache / fetch

    /// Load cache; refresh when stale/missing/backoff elapsed. Never throws.
    public static func loadOrRefresh(
        now: Date,
        cacheURL: URL,
        fetcher: any ReleaseHTTPFetching,
        environment: [String: String]
    ) -> ReleaseCheckRecord? {
        let existing = loadCache(at: cacheURL)

        // Failure backoff: never pay the network timeout until nextAttemptAt.
        if let existing, let next = existing.nextAttemptAt, next > now {
            return existing
        }

        // Fresh success within TTL — zero network.
        if let existing,
           existing.manifest != nil,
           !isCacheStale(existing, now: now)
        {
            return existing
        }

        // Miss, stale, corrupt (load returned nil), or backoff expired.
        return refresh(now: now, cacheURL: cacheURL, fetcher: fetcher, environment: environment, previous: existing)
    }

    public static func isCacheStale(_ record: ReleaseCheckRecord, now: Date) -> Bool {
        // Future fetchedAt beyond skew → treat as stale (clock defense).
        if record.fetchedAt > now.addingTimeInterval(futureSkewTolerance) {
            return true
        }
        if now.timeIntervalSince(record.fetchedAt) > cacheTTL {
            return true
        }
        return false
    }

    public static func loadCache(at url: URL) -> ReleaseCheckRecord? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        // Corrupt / unparseable → miss, never crash.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReleaseCheckRecord.self, from: data)
    }

    public static func writeCache(_ record: ReleaseCheckRecord, to url: URL) {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(record)
            try data.write(to: url, options: .atomic)
        } catch {
            // Fail-open: a cache write miss must never break menu/doctor.
        }
    }

    private static func refresh(
        now: Date,
        cacheURL: URL,
        fetcher: any ReleaseHTTPFetching,
        environment: [String: String],
        previous: ReleaseCheckRecord?
    ) -> ReleaseCheckRecord? {
        let url = latestJSONURL(environment: environment)
        do {
            let data = try fetcher.fetch(url: url, timeout: fetchTimeout)
            guard let manifest = decodeManifest(data) else {
                // Decode/schema failure: backoff; keep prior success if any.
                let failed = ReleaseCheckRecord(
                    fetchedAt: previous?.fetchedAt ?? now,
                    nextAttemptAt: now.addingTimeInterval(failureBackoff),
                    manifest: previous?.manifest
                )
                writeCache(failed, to: cacheURL)
                return failed
            }
            let ok = ReleaseCheckRecord(fetchedAt: now, nextAttemptAt: nil, manifest: manifest)
            writeCache(ok, to: cacheURL)
            return ok
        } catch {
            let failed = ReleaseCheckRecord(
                fetchedAt: previous?.fetchedAt ?? now,
                nextAttemptAt: now.addingTimeInterval(failureBackoff),
                manifest: previous?.manifest
            )
            writeCache(failed, to: cacheURL)
            return failed
        }
    }
}
