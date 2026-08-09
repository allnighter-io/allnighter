import Foundation

/// Public CLI contract for `alln models --json` (Model Catalog And Bench Roster).
public struct ModelListJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var models: [Entry]
    public var diagnostics: [ModelCatalogDiagnostic]
    /// Present when `models` is empty — never return a bare `[]` without guidance.
    public var counsel: String?
    public var nextActions: [AgentSurfaceNextAction]

    public struct Entry: Codable, Sendable, Equatable {
        public var id: ModelID
        public var displayName: String
        public var modelLabel: String
        public var driverId: String
        public var driverName: String
        public var role: String
        public var origin: String
        public var enabled: Bool
        public var ready: Bool
        public var status: String
        public var state: String
        public var capabilities: ModelCapabilities
        /// When the source requires headless trust/mutation flags (e.g. Cursor `--trust`).
        public var headlessTrust: HeadlessTrustPolicy?
        /// PF-S04 — a model is never independently smoke-probed; it always
        /// inherits the OWNING DRIVER's evidence. The only decision an agent
        /// makes from a model row is "trust this readiness verdict or not",
        /// which is exactly this one boolean — `checkedAt`/`ageMinutes`/
        /// `evidenceSource`/`nextAction` stay on the driver row (`alln drivers
        /// --json`, reachable via this row's own `driverId`), which every
        /// model row was already duplicating verbatim (Menu_Envelope_
        /// Compression measured 4,130 of 6,325 added bytes as exact copies).
        /// This is a normalization, not the field-dropping that packet
        /// rejected: nothing left the payload, it moved to the row that
        /// actually owns it. Defaults to the honest "never checked" state
        /// for call sites that predate this field and don't compute it.
        public var stale: Bool

        public init(
            id: ModelID,
            displayName: String,
            modelLabel: String,
            driverId: String,
            driverName: String,
            role: String,
            origin: String,
            enabled: Bool,
            ready: Bool,
            status: String,
            state: String,
            capabilities: ModelCapabilities,
            headlessTrust: HeadlessTrustPolicy? = nil,
            stale: Bool = ProbeFreshnessDisclosure.unknownModel.stale
        ) {
            self.id = id
            self.displayName = displayName
            self.modelLabel = modelLabel
            self.driverId = driverId
            self.driverName = driverName
            self.role = role
            self.origin = origin
            self.enabled = enabled
            self.ready = ready
            self.status = status
            self.state = state
            self.capabilities = capabilities
            self.headlessTrust = headlessTrust
            self.stale = stale
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, contractVersion, models, diagnostics, counsel, nextActions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        contractVersion = try c.decode(String.self, forKey: .contractVersion)
        models = try c.decode([Entry].self, forKey: .models)
        diagnostics = try c.decodeIfPresent([ModelCatalogDiagnostic].self, forKey: .diagnostics) ?? []
        counsel = try c.decodeIfPresent(String.self, forKey: .counsel)
        nextActions = try c.decodeIfPresent([AgentSurfaceNextAction].self, forKey: .nextActions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(contractVersion, forKey: .contractVersion)
        try c.encode(models, forKey: .models)
        try c.encode(diagnostics, forKey: .diagnostics)
        try c.encodeIfPresent(counsel, forKey: .counsel)
        try c.encode(nextActions, forKey: .nextActions)
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        models: [Entry],
        diagnostics: [ModelCatalogDiagnostic] = [],
        counsel: String? = nil,
        nextActions: [AgentSurfaceNextAction] = []
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.models = models
        self.diagnostics = diagnostics
        self.counsel = counsel
        self.nextActions = nextActions
    }
}
