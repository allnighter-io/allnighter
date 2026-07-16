import Foundation

/// `DoctorResult` — the structured `alln doctor --json` contract
/// (docs/phases/CLI_Implementation_Contract.md §Doctor Contract).
///
/// The headless recovery surface: find sources/models, classify readiness, and
/// report the next fix. Check names are stable and registry-owned (CLI M1 step
/// 2). Never fakes liveness — a check reports the state it actually observed.
public struct DoctorResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var status: Status
    public var binaryVersion: String
    public var contractVersion: String
    public var docsVersionMatchesBinary: Bool
    public var checks: [Check]
    public var fixes: [ErrorEnvelope]
    public var models: [TeamRunJSON.ModelInfo]
    public var coordinator: Coordinator
    /// Present when setup is blocked (e.g. config dir missing) — agents should not infer next steps.
    public var counsel: String?
    public var nextActions: [AgentSurfaceNextAction]

    public init(
        schemaVersion: Int = 1,
        status: Status,
        binaryVersion: String,
        contractVersion: String,
        docsVersionMatchesBinary: Bool,
        checks: [Check] = [],
        fixes: [ErrorEnvelope] = [],
        models: [TeamRunJSON.ModelInfo] = [],
        coordinator: Coordinator,
        counsel: String? = nil,
        nextActions: [AgentSurfaceNextAction] = []
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.binaryVersion = binaryVersion
        self.contractVersion = contractVersion
        self.docsVersionMatchesBinary = docsVersionMatchesBinary
        self.checks = checks
        self.fixes = fixes
        self.models = models
        self.coordinator = coordinator
        self.counsel = counsel
        self.nextActions = nextActions
    }

    /// Overall status. `critical`: no runnable team / contract drift / corrupted
    /// config. `degraded`: something fails but a minimal team can run. `ok`: no
    /// problems detected by the checks that ran (a quota-free run can be `ok` with
    /// readiness still `notChecked`).
    public enum Status: String, Codable, Sendable {
        case ok, degraded, critical
    }

    /// Per-check status. Adds `notChecked` for the quota-free `alln doctor` path:
    /// auth/smoke/model-readiness are reported honestly as not checked (next
    /// action: `alln doctor --full`) rather than inferred from a skipped probe.
    public enum CheckStatus: String, Codable, Sendable {
        case ok, degraded, critical, notChecked
    }

    public struct Check: Codable, Equatable, Sendable {
        public var name: String
        public var status: CheckStatus
        public var detail: String
        public var fixCommand: String?
        public var requiresManual: Bool
        public init(name: String, status: CheckStatus, detail: String, fixCommand: String? = nil, requiresManual: Bool = false) {
            self.name = name; self.status = status; self.detail = detail
            self.fixCommand = fixCommand; self.requiresManual = requiresManual
        }
    }

    /// Resident-coordinator state. `foregroundOnly` is normal when resident mode
    /// is off — reported, never faked.
    public struct Coordinator: Codable, Equatable, Sendable {
        public var state: CoordinatorState
        public var available: Bool
        public var detail: String
        public var coordinatorId: String?
        public var pid: Int32?
        public var startedAt: Date?

        public init(
            state: CoordinatorState,
            detail: String,
            coordinatorId: String? = nil,
            pid: Int32? = nil,
            startedAt: Date? = nil
        ) {
            self.state = state
            self.available = state == .available
            self.detail = detail
            self.coordinatorId = coordinatorId
            self.pid = pid
            self.startedAt = startedAt
        }
    }

    public enum CoordinatorState: String, Codable, Sendable {
        case foregroundOnly
        case available
        case unavailable
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, status, binaryVersion, contractVersion, docsVersionMatchesBinary
        case checks, fixes, models, coordinator, counsel, nextActions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        status = try c.decode(Status.self, forKey: .status)
        binaryVersion = try c.decode(String.self, forKey: .binaryVersion)
        contractVersion = try c.decode(String.self, forKey: .contractVersion)
        docsVersionMatchesBinary = try c.decode(Bool.self, forKey: .docsVersionMatchesBinary)
        checks = try c.decode([Check].self, forKey: .checks)
        fixes = try c.decode([ErrorEnvelope].self, forKey: .fixes)
        models = try c.decode([TeamRunJSON.ModelInfo].self, forKey: .models)
        coordinator = try c.decode(Coordinator.self, forKey: .coordinator)
        counsel = try c.decodeIfPresent(String.self, forKey: .counsel)
        nextActions = try c.decodeIfPresent([AgentSurfaceNextAction].self, forKey: .nextActions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(status, forKey: .status)
        try c.encode(binaryVersion, forKey: .binaryVersion)
        try c.encode(contractVersion, forKey: .contractVersion)
        try c.encode(docsVersionMatchesBinary, forKey: .docsVersionMatchesBinary)
        try c.encode(checks, forKey: .checks)
        try c.encode(fixes, forKey: .fixes)
        try c.encode(models, forKey: .models)
        try c.encode(coordinator, forKey: .coordinator)
        try c.encodeIfPresent(counsel, forKey: .counsel)
        try c.encode(nextActions, forKey: .nextActions)
    }
}
