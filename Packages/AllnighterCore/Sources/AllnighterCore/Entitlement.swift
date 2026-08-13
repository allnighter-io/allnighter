#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
#if os(macOS)
import IOKit
#endif

/// Trial / paid admission. Offer numbers live in
/// `docs/marketing/Pricing_Recommendation.md`; this file is the runtime gate.
///
/// Sign in with Apple is not part of the buy path. Identity is a machine hash.
/// Token lives under Application Support, never Keychain (BUG-9).

// MARK: - Constants

public enum EntitlementPolicy {
    public static let trialDurationDays = 14
    public static let freeRunsPerDay = 3
    public static let offlineGraceHours: Double = 72
    public static let cacheTTLHours: Double = 24
    public static let defaultBaseURL = URL(string: "https://pay.allnighter.io")!
    public static let checkoutCommand = "alln billing checkout --plan monthly --json"
    public static let skipEnvKey = "ALLN_NO_ENTITLEMENT_CHECK"
    public static let baseURLEnvKey = "ALLN_ENTITLEMENT_BASE_URL"

    /// HMAC salt — hides the raw IOKit UUID on the wire. Not a payment secret.
    static let machineHashSalt = "allnighter.entitlement.v1"
}

public enum EntitlementPlan: String, Codable, Sendable, Equatable, CaseIterable {
    case trial
    case free
    case monthly
    case yearly
    case founding

    public var isPaid: Bool {
        switch self {
        case .monthly, .yearly, .founding: return true
        case .trial, .free: return false
        }
    }

    public var isUnlimited: Bool { isPaid || self == .trial }
}

public enum BillingCheckoutPlan: String, Sendable, Equatable, CaseIterable {
    case monthly
    case yearly
    case founding
}

// MARK: - Wire / menu

/// Optional `menu.entitlement` — sibling of `update`. Omit the key when skipped.
public struct EntitlementInfo: Codable, Sendable, Equatable {
    public var plan: String
    public var trialEndsAt: String?
    public var runsRemainingToday: Int?
    public var checkoutCommand: String

    public init(
        plan: String,
        trialEndsAt: String? = nil,
        runsRemainingToday: Int? = nil,
        checkoutCommand: String = EntitlementPolicy.checkoutCommand
    ) {
        self.plan = plan
        self.trialEndsAt = trialEndsAt
        self.runsRemainingToday = runsRemainingToday
        self.checkoutCommand = checkoutCommand
    }
}

/// `alln billing` / `alln billing checkout --json`.
public struct BillingJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var plan: String
    public var paid: Bool
    public var trialStartedAt: String?
    public var trialEndsAt: String?
    public var runsUsedToday: Int?
    public var runsAllowedToday: Int?
    public var checkoutCommand: String
    public var url: String?
    public var message: String?

    public init(
        schemaVersion: Int = 1,
        plan: String,
        paid: Bool,
        trialStartedAt: String? = nil,
        trialEndsAt: String? = nil,
        runsUsedToday: Int? = nil,
        runsAllowedToday: Int? = nil,
        checkoutCommand: String = EntitlementPolicy.checkoutCommand,
        url: String? = nil,
        message: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.plan = plan
        self.paid = paid
        self.trialStartedAt = trialStartedAt
        self.trialEndsAt = trialEndsAt
        self.runsUsedToday = runsUsedToday
        self.runsAllowedToday = runsAllowedToday
        self.checkoutCommand = checkoutCommand
        self.url = url
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, plan, paid, trialStartedAt, trialEndsAt
        case runsUsedToday, runsAllowedToday, checkoutCommand, url, message
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(plan, forKey: .plan)
        try c.encode(paid, forKey: .paid)
        try c.encodeIfPresent(trialStartedAt, forKey: .trialStartedAt)
        try c.encodeIfPresent(trialEndsAt, forKey: .trialEndsAt)
        try c.encodeIfPresent(runsUsedToday, forKey: .runsUsedToday)
        try c.encodeIfPresent(runsAllowedToday, forKey: .runsAllowedToday)
        try c.encode(checkoutCommand, forKey: .checkoutCommand)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(message, forKey: .message)
    }
}

public enum EntitlementAdmission {
    /// Loop start admits once; inner `RunService.run` calls must not count again.
    @TaskLocal public static var skipInnerDispatch = false

    public static func skippingInner(
        _ body: @Sendable () async -> Void
    ) async {
        await $skipInnerDispatch.withValue(true, operation: body)
    }
}

public struct EntitlementRefusal: Sendable, Equatable, Error {
    public var message: String
    public init(_ message: String) { self.message = message }

    public static let dailyCap = EntitlementRefusal(
        "Free allowance used (3 runs today). Trial ended. Open Stripe Checkout with `alln billing checkout --plan monthly --json` and open the returned url in a browser — do not exec the url."
    )
}

public enum EntitlementDecision: Sendable, Equatable {
    case admit
    case refuse(EntitlementRefusal)
}

// MARK: - Local state

struct EntitlementState: Codable, Equatable, Sendable {
    var plan: EntitlementPlan
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var serverTrialStartedAt: Date?
    var lastServerSync: Date?
    var lastServerIssuedAt: Date?
    var provisionalStartedAt: Date?
    var dayKey: String
    var runsUsedToday: Int
    var paid: Bool

    static func empty(now: Date, calendar: Calendar) -> EntitlementState {
        EntitlementState(
            plan: .free,
            trialStartedAt: nil,
            trialEndsAt: nil,
            serverTrialStartedAt: nil,
            lastServerSync: nil,
            lastServerIssuedAt: nil,
            provisionalStartedAt: nil,
            dayKey: EntitlementState.dayKey(now: now, calendar: calendar),
            runsUsedToday: 0,
            paid: false
        )
    }

    static func dayKey(now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func rollDayIfNeeded(now: Date, calendar: Calendar) {
        let key = EntitlementState.dayKey(now: now, calendar: calendar)
        if key != dayKey {
            dayKey = key
            runsUsedToday = 0
        }
    }
}

struct EntitlementServerStatus: Equatable, Sendable {
    var plan: EntitlementPlan
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var paid: Bool
}

// MARK: - Seams

public protocol MachineIdentity: Sendable {
    func machineHash() -> String
}

public protocol EntitlementTransport: Sendable {
    func post(path: String, json: Data) async throws -> (status: Int, body: Data)
}

protocol EntitlementStoring: Sendable {
    func load() -> EntitlementState?
    func save(_ state: EntitlementState)
}

// MARK: - Machine hash

public struct PlatformMachineIdentity: MachineIdentity {
    public init() {}

    public func machineHash() -> String {
        let material = hardwareIdentity() ?? fallbackStoredIdentity()
        return Self.hash(material)
    }

    public static func hash(_ material: String) -> String {
        let key = SymmetricKey(data: Data(EntitlementPolicy.machineHashSalt.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(material.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private func hardwareIdentity() -> String? {
        #if os(macOS)
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return (cf.takeRetainedValue() as? String)
        #else
        return nil
        #endif
    }

    /// Last resort when IOKit is missing. Reinstall may mint a new id — residual.
    private func fallbackStoredIdentity() -> String {
        let url = AllnighterSupportRoot.entitlement.appendingPathComponent("local-machine-id")
        if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.isEmpty {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let minted = UUID().uuidString
        try? FileManager.default.createDirectory(
            at: AllnighterSupportRoot.entitlement,
            withIntermediateDirectories: true
        )
        try? minted.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return minted
    }
}

// MARK: - Store

struct FileEntitlementStore: EntitlementStoring {
    let directory: URL

    init(directory: URL = AllnighterSupportRoot.entitlement) {
        self.directory = directory
    }

    private var fileURL: URL {
        directory.appendingPathComponent("state.json")
    }

    func load() -> EntitlementState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EntitlementState.self, from: data)
    }

    func save(_ state: EntitlementState) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

// MARK: - HTTP

public struct EntitlementHTTPTransport: EntitlementTransport {
    let baseURL: URL
    let session: URLSession

    public init(baseURL: URL = EntitlementPolicy.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 2
            config.timeoutIntervalForResource = 2
            self.session = URLSession(configuration: config)
        }
    }

    public static func baseURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = env[EntitlementPolicy.baseURLEnvKey],
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return EntitlementPolicy.defaultBaseURL
    }

    public func post(path: String, json: Data) async throws -> (status: Int, body: Data) {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root: URL
        if baseURL.absoluteString.hasSuffix("/") {
            root = baseURL
        } else if let withSlash = URL(string: baseURL.absoluteString + "/") {
            root = withSlash
        } else {
            root = baseURL
        }
        guard let url = URL(string: trimmed, relativeTo: root) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url.absoluteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json
        let (body, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, body)
    }
}

// MARK: - Gate

public struct EntitlementGate: Sendable {
    let clock: @Sendable () -> Date
    let calendar: Calendar
    let identity: any MachineIdentity
    let transport: any EntitlementTransport
    let store: any EntitlementStoring
    let isTestHost: Bool
    let env: [String: String]

    public static let standard = EntitlementGate()

    init(
        clock: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        identity: any MachineIdentity = PlatformMachineIdentity(),
        transport: any EntitlementTransport = EntitlementHTTPTransport(
            baseURL: EntitlementHTTPTransport.baseURL()
        ),
        store: (any EntitlementStoring)? = nil,
        isTestHost: Bool = AllnighterSupportRoot.isRunningUnderTestHost,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.clock = clock
        self.calendar = calendar
        self.identity = identity
        self.transport = transport
        self.store = store ?? FileEntitlementStore()
        self.isTestHost = isTestHost
        self.env = env
    }

    public func shouldSkipNetwork() -> Bool {
        if isTestHost { return true }
        let flag = env[EntitlementPolicy.skipEnvKey] ?? ""
        return flag == "1" || flag.lowercased() == "true"
    }

    /// Sync projection for `menu.entitlement`. Local file only — never starts a trial.
    public func menuProjection() -> EntitlementInfo? {
        if shouldSkipNetwork() { return nil }
        guard var state = store.load() else { return nil }
        let now = clock()
        state.rollDayIfNeeded(now: now, calendar: calendar)
        let remaining: Int?
        if state.plan.isUnlimited {
            remaining = nil
        } else {
            remaining = max(0, EntitlementPolicy.freeRunsPerDay - state.runsUsedToday)
        }
        return EntitlementInfo(
            plan: state.plan.rawValue,
            trialEndsAt: state.trialEndsAt.map(iso),
            runsRemainingToday: remaining
        )
    }

    public func statusJSON() async -> BillingJSON {
        if shouldSkipNetwork() {
            return BillingJSON(
                plan: "skipped",
                paid: false,
                message: "Entitlement check skipped (test host or \(EntitlementPolicy.skipEnvKey))."
            )
        }
        var state = await refresh(force: true)
        state.rollDayIfNeeded(now: clock(), calendar: calendar)
        return projectJSON(state, url: nil, message: nil)
    }

    public func checkoutJSON(plan: BillingCheckoutPlan) async -> Result<BillingJSON, EntitlementRefusal> {
        if shouldSkipNetwork() {
            return .failure(EntitlementRefusal("Checkout skipped in test host."))
        }
        let hash = identity.machineHash()
        let body: [String: String] = ["machineHash": hash, "plan": plan.rawValue]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(EntitlementRefusal("Could not encode checkout request."))
        }
        do {
            let (status, data) = try await transport.post(path: "v1/checkout", json: json)
            if status == 200, let url = parseCheckoutURL(data) {
                let state = store.load() ?? EntitlementState.empty(now: clock(), calendar: calendar)
                return .success(projectJSON(
                    state,
                    url: url,
                    message: "Open this url in Safari or Chrome to pay (not Cursor's preview). Do not exec it. Then run `alln billing --json`."
                ))
            }
            let msg = parseErrorMessage(data) ?? "Checkout failed (HTTP \(status))."
            return .failure(EntitlementRefusal(msg))
        } catch {
            return .failure(EntitlementRefusal(
                "Could not reach pay.allnighter.io (\(error.localizedDescription)). Try again, or set \(EntitlementPolicy.baseURLEnvKey)."
            ))
        }
    }

    /// One admission for a user-started dispatch. Increments the free-tier counter
    /// only when admitting a counted free run.
    public func admitDispatch() async -> EntitlementDecision {
        if EntitlementAdmission.skipInnerDispatch { return .admit }
        if shouldSkipNetwork() { return .admit }

        var state = await refresh(force: false)
        let now = clock()
        state.rollDayIfNeeded(now: now, calendar: calendar)

        if state.plan.isUnlimited {
            store.save(state)
            return .admit
        }

        if state.runsUsedToday >= EntitlementPolicy.freeRunsPerDay {
            store.save(state)
            return .refuse(.dailyCap)
        }

        state.runsUsedToday += 1
        store.save(state)
        return .admit
    }

    // MARK: refresh

    private func refresh(force: Bool) async -> EntitlementState {
        var state = store.load() ?? EntitlementState.empty(now: clock(), calendar: calendar)
        let now = clock()
        state.rollDayIfNeeded(now: now, calendar: calendar)

        let cacheStale: Bool = {
            if force { return true }
            if let issued = state.lastServerIssuedAt, now < issued { return true }
            guard let synced = state.lastServerSync else { return true }
            return now.timeIntervalSince(synced) > EntitlementPolicy.cacheTTLHours * 3600
        }()

        if cacheStale {
            if let remote = await fetchStatus() {
                applyServer(&state, remote: remote, now: now)
            } else {
                applyOffline(&state, now: now)
                state.lastServerSync = now
            }
            store.save(state)
        }
        return state
    }

    private func applyServer(_ state: inout EntitlementState, remote: EntitlementServerStatus, now: Date) {
        state.lastServerSync = now
        state.lastServerIssuedAt = now
        state.paid = remote.paid
        state.plan = remote.plan
        if let started = remote.trialStartedAt {
            if let existing = state.serverTrialStartedAt {
                state.serverTrialStartedAt = min(existing, started)
            } else {
                state.serverTrialStartedAt = started
            }
        }
        state.trialStartedAt = state.serverTrialStartedAt ?? remote.trialStartedAt
        state.trialEndsAt = remote.trialEndsAt
            ?? state.trialStartedAt.map { $0.addingTimeInterval(Double(EntitlementPolicy.trialDurationDays) * 86400) }
        state.provisionalStartedAt = nil
    }

    private func applyOffline(_ state: inout EntitlementState, now: Date) {
        if state.serverTrialStartedAt != nil {
            if let started = state.serverTrialStartedAt {
                let end = started.addingTimeInterval(Double(EntitlementPolicy.trialDurationDays) * 86400)
                state.trialStartedAt = started
                state.trialEndsAt = end
                if now < end {
                    state.plan = .trial
                } else if !state.paid {
                    state.plan = .free
                }
            }
            return
        }
        if state.provisionalStartedAt == nil {
            state.provisionalStartedAt = now
            state.trialStartedAt = now
            state.trialEndsAt = now.addingTimeInterval(EntitlementPolicy.offlineGraceHours * 3600)
            state.plan = .trial
            return
        }
        if let start = state.provisionalStartedAt,
           now.timeIntervalSince(start) < EntitlementPolicy.offlineGraceHours * 3600 {
            state.plan = .trial
            return
        }
        if !state.paid {
            state.plan = .free
        }
    }

    private func fetchStatus() async -> EntitlementServerStatus? {
        let hash = identity.machineHash()
        let body: [String: String] = ["machineHash": hash]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        do {
            let (status, data) = try await transport.post(path: "v1/status", json: json)
            guard status == 200 else { return nil }
            return parseStatus(data)
        } catch {
            return nil
        }
    }

    private func parseStatus(_ data: Data) -> EntitlementServerStatus? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let planRaw = (obj["plan"] as? String) ?? "free"
        let plan = EntitlementPlan(rawValue: planRaw) ?? .free
        return EntitlementServerStatus(
            plan: plan,
            trialStartedAt: msDate(obj["trialStartedAt"]),
            trialEndsAt: msDate(obj["trialEndsAt"]),
            paid: (obj["paid"] as? Bool) ?? plan.isPaid
        )
    }

    private func parseCheckoutURL(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["url"] as? String
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["message"] as? String ?? obj["error"] as? String
    }

    private func msDate(_ value: Any?) -> Date? {
        if let n = value as? Double { return Date(timeIntervalSince1970: n / 1000) }
        if let n = value as? Int { return Date(timeIntervalSince1970: Double(n) / 1000) }
        if let s = value as? String, let d = ISO8601DateFormatter().date(from: s) { return d }
        return nil
    }

    private func projectJSON(_ state: EntitlementState, url: String?, message: String?) -> BillingJSON {
        let unlimited = state.plan.isUnlimited
        return BillingJSON(
            plan: state.plan.rawValue,
            paid: state.paid || state.plan.isPaid,
            trialStartedAt: state.trialStartedAt.map(iso),
            trialEndsAt: state.trialEndsAt.map(iso),
            runsUsedToday: unlimited ? nil : state.runsUsedToday,
            runsAllowedToday: unlimited ? nil : EntitlementPolicy.freeRunsPerDay,
            url: url,
            message: message
        )
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

public enum EntitlementLimitNextAction {
    public static let agent = AgentNextAction(
        kind: "openCheckout",
        label: "Start Stripe Checkout (human opens the url)",
        command: EntitlementPolicy.checkoutCommand
    )
}
