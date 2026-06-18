import Foundation

/// Public CLI contract for `alln models --json` (Model Catalog And Bench Roster).
public struct ModelListJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var models: [Entry]
    public var diagnostics: [ModelCatalogDiagnostic]

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
            capabilities: ModelCapabilities
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
        }
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        models: [Entry],
        diagnostics: [ModelCatalogDiagnostic] = []
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.models = models
        self.diagnostics = diagnostics
    }
}
