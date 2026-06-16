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

    public init(
        schemaVersion: Int = 1,
        status: Status,
        binaryVersion: String,
        contractVersion: String,
        docsVersionMatchesBinary: Bool,
        checks: [Check] = [],
        fixes: [ErrorEnvelope] = [],
        models: [TeamRunJSON.ModelInfo] = [],
        coordinator: Coordinator
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
    }

    /// Overall and per-check status. `critical`: no runnable team / contract
    /// drift / corrupted config. `degraded`: something fails but a minimal team
    /// can run. `ok`: all required checks pass.
    public enum Status: String, Codable, Sendable {
        case ok, degraded, critical
    }

    public struct Check: Codable, Equatable, Sendable {
        public var name: String
        public var status: Status
        public var detail: String
        public var fixCommand: String?
        public var requiresManual: Bool
        public init(name: String, status: Status, detail: String, fixCommand: String? = nil, requiresManual: Bool = false) {
            self.name = name; self.status = status; self.detail = detail
            self.fixCommand = fixCommand; self.requiresManual = requiresManual
        }
    }

    /// Resident-coordinator state. May be `available: false` in milestone 1
    /// (foreground CLI only) — reported, never faked.
    public struct Coordinator: Codable, Equatable, Sendable {
        public var available: Bool
        public var detail: String
        public init(available: Bool, detail: String) {
            self.available = available; self.detail = detail
        }
    }
}
