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
    public var capabilities: ModelCapabilities
    /// Per-effort model label overrides for CLIs that encode effort IN the model
    /// name (Antigravity, e.g. low → "Gemini 3.5 Flash (Low)"). nil = the model
    /// label is constant and effort (if any) is applied as a driver flag instead.
    public var effortVariants: [EffortLevel: String]?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: ModelID,
        displayName: String,
        modelLabel: String,
        driverId: String,
        role: ModelRole,
        origin: ModelOrigin,
        defaultEnabled: Bool,
        capabilities: ModelCapabilities,
        effortVariants: [EffortLevel: String]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.modelLabel = modelLabel
        self.driverId = driverId
        self.role = role
        self.origin = origin
        self.defaultEnabled = defaultEnabled
        self.capabilities = capabilities
        self.effortVariants = effortVariants
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ModelRosterState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var enabledModelIds: [ModelID]
    public var updatedAt: Date?

    public init(schemaVersion: Int = 1, enabledModelIds: [ModelID] = [], updatedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.enabledModelIds = enabledModelIds
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
