import Foundation

/// Stable machine identifier for one model definition (global namespace).
public typealias ModelID = String

public enum ModelOrigin: String, Codable, Sendable, CaseIterable {
    case builtIn = "built_in"
    case custom
    case discovered
}

public struct ModelDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: ModelID
    public var displayName: String
    public var modelLabel: String
    public var driverId: String
    public var role: ModelRole
    public var origin: ModelOrigin
    public var defaultEnabled: Bool
    /// Bench default reasoning effort when a run does not pass an explicit effort.
    public var defaultEffort: EffortLevel?
    public var capabilities: ModelCapabilities
    /// Per-effort model label overrides for CLIs that encode effort IN the model
    /// name (Antigravity, e.g. low → "Gemini 3.5 Flash (Low)"). nil = the model
    /// label is constant and effort (if any) is applied as a driver flag instead.
    public var effortVariants: [EffortLevel: String]?
    public var createdAt: Date?
    public var updatedAt: Date?
    /// AgentOS ModelSmokeStatus raw value for custom models. nil = built-in / legacy (treated as trusted).
    public var modelSmokeStatus: String?  // "recognized"|"unrecognized"|"unsupported"|"inconclusive"|"unverified"
    public var modelSmokeDetail: String?

    public init(
        id: ModelID,
        displayName: String,
        modelLabel: String,
        driverId: String,
        role: ModelRole,
        origin: ModelOrigin,
        defaultEnabled: Bool,
        defaultEffort: EffortLevel? = nil,
        capabilities: ModelCapabilities,
        effortVariants: [EffortLevel: String]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        modelSmokeStatus: String? = nil,
        modelSmokeDetail: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.modelLabel = modelLabel
        self.driverId = driverId
        self.role = role
        self.origin = origin
        self.defaultEnabled = defaultEnabled
        self.defaultEffort = defaultEffort
        self.capabilities = capabilities
        self.effortVariants = effortVariants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelSmokeStatus = modelSmokeStatus
        self.modelSmokeDetail = modelSmokeDetail
    }
}

public struct ModelRosterState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var enabledModelIds: [ModelID]
    /// Built-in catalog ids reconciled at least once — used to default-on newcomers
    /// without re-enabling models the user turned off.
    public var catalogSeenModelIds: [ModelID]?
    /// Once true, default-on OpenCode Go seats were seeded after Go auth connected.
    /// Further reconciles must not re-enable seats the user turned off.
    public var openCodeGoDefaultsSeeded: Bool?
    public var updatedAt: Date?

    public init(
        schemaVersion: Int = 1,
        enabledModelIds: [ModelID] = [],
        catalogSeenModelIds: [ModelID]? = nil,
        openCodeGoDefaultsSeeded: Bool? = nil,
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.enabledModelIds = enabledModelIds
        self.catalogSeenModelIds = catalogSeenModelIds
        self.openCodeGoDefaultsSeeded = openCodeGoDefaultsSeeded
        self.updatedAt = updatedAt
    }
}

public struct ModelCatalogDiagnostic: Codable, Sendable, Equatable {
    public var code: String
    public var modelId: ModelID?
    public var driverId: String?
    public var message: String

    public init(code: String, modelId: ModelID? = nil, driverId: String? = nil, message: String) {
        self.code = code
        self.modelId = modelId
        self.driverId = driverId
        self.message = message
    }
}

public enum ModelCatalogError: Error, Equatable, Sendable {
    case notFound(ModelID)
    case builtInImmutable
    case idCollision
    case idInvalid
    case driverMissing(String)
    case invalid(String)
}
