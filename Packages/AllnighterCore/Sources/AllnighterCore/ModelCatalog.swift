import Foundation

/// Core-owned, deterministic model catalog: built-in/custom definitions, Bench
/// roster overlay, and capability metadata for resolver fallback.
public enum ModelCatalog {
    // MARK: - Built-in capability metadata

    public static let builtInCapabilities: [String: ModelCapabilities] = [
        "model_opus": ModelCapabilities(
            laneTags: [.build, .design, .copy],
            capabilityTags: [.code, .planner, .review, .security, .copy, .localContext],
            strengthRank: 100),
        "model_chatgpt": ModelCapabilities(
            laneTags: [.build, .design, .copy],
            capabilityTags: [.code, .planner, .review, .security],
            strengthRank: 90),
        "model_sonnet": ModelCapabilities(
            laneTags: [.build, .design, .copy],
            capabilityTags: [.code, .planner, .review, .fast],
            strengthRank: 80),
        "model_gemini": ModelCapabilities(
            laneTags: [.design, .build],
            capabilityTags: [.code, .design, .image, .fast],
            strengthRank: 75),
        "model_grok": ModelCapabilities(
            laneTags: [.build, .copy],
            capabilityTags: [.code, .planner],
            strengthRank: 70),
        "model_composer": ModelCapabilities(
            laneTags: [.build],
            capabilityTags: [.code, .fast],
            strengthRank: 60)
    ]

    public static var builtIns: [ModelDefinition] {
        [
            def("model_opus", "Opus 4.8", "opus", "claude_code", .both, defaultEnabled: true),
            def("model_sonnet", "Sonnet 4.6", "sonnet", "claude_code", .answerer, defaultEnabled: true),
            def("model_chatgpt", "ChatGPT 5.5", "gpt-5.5", "codex", .answerer, defaultEnabled: true),
            def("model_composer", "Composer 2.5", "grok-composer-2.5-fast", "grok", .answerer, defaultEnabled: true),
            def("model_grok", "Grok Build", "grok-build", "grok", .answerer, defaultEnabled: true),
            def("model_gemini", "Gemini (Antigravity)", "Gemini 3.5 Flash (Medium)", "antigravity", .answerer, defaultEnabled: true),
        ]
    }

    // MARK: - Test overrides

    nonisolated(unsafe) private static var rosterPersistenceOverride: ModelRosterPersistence?

    public static func overrideRosterForTesting(fileURL: URL) {
        rosterPersistenceOverride = ModelRosterPersistence(fileURL: fileURL)
    }

    public static func resetTestingOverrides() {
        rosterPersistenceOverride = nil
    }

    // MARK: - Lookup

    public static func list(
        driverId: String? = nil,
        includeUnavailableDrivers: Bool = true
    ) -> [ModelDefinition] {
        var defs = mergedDefinitions()
        if let driverId {
            defs = defs.filter { $0.driverId == driverId }
        }
        if !includeUnavailableDrivers {
            let known = Set(builtIns.map(\.driverId))
            defs = defs.filter { known.contains($0.driverId) || $0.origin != .custom }
        }
        return defs.sorted { $0.id < $1.id }
    }

    public static func get(_ id: ModelID) -> ModelDefinition? {
        builtIns.first { $0.id == id }
            ?? CatalogFileIO.loadOne(id: id, kind: .model, root: CatalogRoots.models, as: ModelDefinition.self)
    }

    public static func resolvedModels(registry: DriverRegistry) -> [Model] {
        materialize(mergedDefinitions(), registry: registry)
    }

    public static func benchModels(registry: DriverRegistry) -> [Model] {
        resolvedModels(registry: registry).filter(\.enabled)
    }

    public static func probeModelLabel(driverId: String) -> String? {
        let defs = mergedDefinitions().filter { $0.driverId == driverId }
        guard !defs.isEmpty else { return nil }
        let enabledMap = enabledModelIDs(definitions: mergedDefinitions())
        let enabled = defs.filter { enabledMap[$0.id] == true }
        if let label = selectProbeLabel(from: enabled) { return label }
        let custom = defs.filter { $0.origin == .custom || $0.origin == .discovered }
        if let label = selectProbeLabel(from: custom) { return label }
        return selectProbeLabel(from: defs.filter { $0.origin == .builtIn })
    }

    public static func probeModelLabels(registry: DriverRegistry) -> [String: String] {
        var out: [String: String] = [:]
        for manifest in registry.all where manifest.kind == .headlessCLI {
            if let label = probeModelLabel(driverId: manifest.id) {
                out[manifest.id] = label
            }
        }
        return out
    }

    public static func diagnostics(registry: DriverRegistry) -> [ModelCatalogDiagnostic] {
        var diags: [ModelCatalogDiagnostic] = []
        let manifestIDs = Set(registry.all.map(\.id))
        let defs = mergedDefinitions()
        let knownIDs = Set(defs.map(\.id))
        for custom in CatalogFileIO.loadAll(kind: .model, root: CatalogRoots.models, as: ModelDefinition.self) {
            if !manifestIDs.contains(custom.driverId) {
                diags.append(ModelCatalogDiagnostic(
                    code: "MODEL_DRIVER_MISSING",
                    modelId: custom.id,
                    driverId: custom.driverId,
                    message: "Custom model references driver '\(custom.driverId)' not installed in this build."
                ))
            }
        }
        if let roster = rosterPersistence().load() {
            for stale in roster.enabledModelIds where !knownIDs.contains(stale) {
                diags.append(ModelCatalogDiagnostic(
                    code: "MODEL_ROSTER_STALE_ID",
                    modelId: stale,
                    message: "Roster enabled set references model '\(stale)' that no longer exists."
                ))
            }
        }
        return diags
    }

    // MARK: - Roster mutations

    public static func isEnabled(_ id: ModelID) -> Bool {
        guard let def = get(id) else { return false }
        return enabledModelIDs(definitions: mergedDefinitions())[id] ?? def.defaultEnabled
    }

    public static func setEnabled(_ id: ModelID, _ enabled: Bool) throws {
        guard get(id) != nil else { throw ModelCatalogError.notFound(id) }
        var roster = rosterPersistence().load() ?? defaultRosterState(definitions: mergedDefinitions())
        if enabled {
            if !roster.enabledModelIds.contains(id) { roster.enabledModelIds.append(id) }
        } else {
            roster.enabledModelIds.removeAll { $0 == id }
        }
        try rosterPersistence().save(roster)
    }

    // MARK: - Custom CRUD

    @discardableResult
    public static func createCustom(
        driverId: String,
        displayName: String,
        modelLabel: String,
        role: ModelRole,
        enabled: Bool = true,
        registry: DriverRegistry
    ) throws -> ModelDefinition {
        try validateDriver(driverId, registry: registry)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = modelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedLabel.isEmpty else {
            throw ModelCatalogError.invalid("display name and model label must not be empty")
        }
        var newId = ModelIDGenerator.customID(driverId: driverId, displayName: trimmedName)
        while get(newId) != nil {
            newId = ModelIDGenerator.customID(
                driverId: driverId, displayName: trimmedName,
                suffix: String(Int.random(in: 1000...9999)))
        }
        let now = Date()
        let def = ModelDefinition(
            id: newId,
            displayName: trimmedName,
            modelLabel: trimmedLabel,
            driverId: driverId,
            role: role,
            origin: .custom,
            defaultEnabled: enabled,
            capabilities: fallbackCapabilities(driverId: driverId),
            createdAt: now,
            updatedAt: now
        )
        try saveCustom(def)
        if enabled { try setEnabled(newId, true) }
        else { try ensureRosterExists(); try setEnabled(newId, false) }
        return def
    }

    public static func updateCustom(_ model: ModelDefinition) throws {
        guard model.origin == .custom else { throw ModelCatalogError.builtInImmutable }
        guard let existing = CatalogFileIO.loadOne(
            id: model.id, kind: .model, root: CatalogRoots.models, as: ModelDefinition.self
        ) else { throw ModelCatalogError.notFound(model.id) }
        guard existing.driverId == model.driverId, existing.id == model.id, existing.origin == model.origin else {
            throw ModelCatalogError.invalid("id, driverId, and origin cannot change; delete and recreate")
        }
        let trimmedName = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = model.modelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedLabel.isEmpty else {
            throw ModelCatalogError.invalid("display name and model label must not be empty")
        }
        var updated = model
        updated.displayName = trimmedName
        updated.modelLabel = trimmedLabel
        updated.updatedAt = Date()
        try CatalogFileIO.save(updated, id: updated.id, kind: .model, root: CatalogRoots.models)
    }

    public static func deleteCustom(_ id: ModelID) throws {
        if builtIns.contains(where: { $0.id == id }) { throw ModelCatalogError.builtInImmutable }
        guard CatalogFileIO.loadOne(id: id, kind: .model, root: CatalogRoots.models, as: ModelDefinition.self) != nil else {
            throw ModelCatalogError.notFound(id)
        }
        try CatalogFileIO.delete(id: id, root: CatalogRoots.models)
        if var roster = rosterPersistence().load() {
            roster.enabledModelIds.removeAll { $0 == id }
            try rosterPersistence().save(roster)
        }
    }

    /// Capabilities for a model id — built-in table, then definition, then empty.
    public static func capabilities(_ modelId: String) -> ModelCapabilities {
        if let caps = builtInCapabilities[modelId] { return caps }
        if let def = get(modelId), !def.capabilities.capabilityTags.isEmpty { return def.capabilities }
        if let def = get(modelId) { return fallbackCapabilities(driverId: def.driverId) }
        return ModelCapabilities()
    }

    /// Default fresh-install Bench as runtime `[Model]` (all built-ins enabled).
    public static func defaultFreshModels() -> [Model] {
        builtIns.map { def in
            Model(
                id: def.id, displayName: def.displayName, modelLabel: def.modelLabel,
                driverId: def.driverId, role: def.role, enabled: def.defaultEnabled)
        }
    }

    // MARK: - Private

    private static func def(
        _ id: String, _ name: String, _ label: String, _ driver: String, _ role: ModelRole,
        defaultEnabled: Bool
    ) -> ModelDefinition {
        ModelDefinition(
            id: id, displayName: name, modelLabel: label, driverId: driver, role: role,
            origin: .builtIn, defaultEnabled: defaultEnabled,
            capabilities: builtInCapabilities[id] ?? ModelCapabilities())
    }

    private static func mergedDefinitions() -> [ModelDefinition] {
        var byID: [ModelID: ModelDefinition] = [:]
        for builtIn in builtIns { byID[builtIn.id] = builtIn }
        for custom in CatalogFileIO.loadAll(kind: .model, root: CatalogRoots.models, as: ModelDefinition.self) {
            byID[custom.id] = custom
        }
        return Array(byID.values)
    }

    private static func enabledModelIDs(definitions: [ModelDefinition]) -> [ModelID: Bool] {
        if let roster = rosterPersistence().load() {
            let enabled = Set(roster.enabledModelIds)
            return Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, enabled.contains($0.id)) })
        }
        return Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.defaultEnabled) })
    }

    private static func materialize(_ definitions: [ModelDefinition], registry: DriverRegistry) -> [Model] {
        let enabled = enabledModelIDs(definitions: definitions)
        let manifestIDs = Set(registry.all.map(\.id))
        return definitions
            .filter { manifestIDs.contains($0.driverId) || $0.origin == .builtIn }
            .sorted { $0.id < $1.id }
            .map { def in
                Model(
                    id: def.id,
                    displayName: def.displayName,
                    modelLabel: def.modelLabel,
                    driverId: def.driverId,
                    role: def.role,
                    enabled: enabled[def.id] ?? def.defaultEnabled)
            }
    }

    private static func defaultRosterState(definitions: [ModelDefinition]) -> ModelRosterState {
        ModelRosterState(enabledModelIds: definitions.filter(\.defaultEnabled).map(\.id))
    }

    private static func ensureRosterExists() throws {
        if rosterPersistence().load() == nil {
            try rosterPersistence().save(defaultRosterState(definitions: mergedDefinitions()))
        }
    }

    private static func rosterPersistence() -> ModelRosterPersistence {
        rosterPersistenceOverride ?? ModelRosterPersistence()
    }

    private static func validateDriver(_ driverId: String, registry: DriverRegistry) throws {
        guard registry.manifest(id: driverId) != nil else {
            throw ModelCatalogError.driverMissing(driverId)
        }
    }

    private static func saveCustom(_ def: ModelDefinition) throws {
        guard def.origin == .custom else { throw ModelCatalogError.builtInImmutable }
        guard CatalogIDValidator.isValid(def.id) else { throw ModelCatalogError.idInvalid }
        if builtIns.contains(where: { $0.id == def.id }) { throw ModelCatalogError.idCollision }
        if CatalogFileIO.loadOne(id: def.id, kind: .model, root: CatalogRoots.models, as: ModelDefinition.self) != nil {
            throw ModelCatalogError.idCollision
        }
        try CatalogFileIO.save(def, id: def.id, kind: .model, root: CatalogRoots.models)
    }

    private static func selectProbeLabel(from definitions: [ModelDefinition]) -> String? {
        guard !definitions.isEmpty else { return nil }
        let ranked = definitions.sorted { lhs, rhs in
            let lhsBoth = lhs.role == .both ? 1 : 0
            let rhsBoth = rhs.role == .both ? 1 : 0
            if lhsBoth != rhsBoth { return lhsBoth > rhsBoth }
            if lhs.capabilities.strengthRank != rhs.capabilities.strengthRank {
                return lhs.capabilities.strengthRank > rhs.capabilities.strengthRank
            }
            return lhs.id < rhs.id
        }
        return ranked.first?.modelLabel
    }

    private static func fallbackCapabilities(driverId: String) -> ModelCapabilities {
        list(driverId: driverId).first { $0.origin == .builtIn }?.capabilities ?? ModelCapabilities()
    }
}

enum ModelCatalogPaths {
    static var config: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Allnighter/Config", isDirectory: true)
    }
}

enum ModelIDGenerator {
    static func customID(driverId: String, displayName: String, suffix: String = "") -> ModelID {
        let slug = slugify(displayName)
        let base = "custom_\(driverId)_\(slug)\(suffix.isEmpty ? "" : "_\(suffix)")"
        return String(base.prefix(64))
    }

    private static func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        for ch in lowered.unicodeScalars {
            if ch.isASCII && (ch.properties.isAlphabetic || ch.properties.numericType == .decimal) {
                out.append(Character(ch))
            } else if ch == " " || ch == "-" {
                out.append("_")
            }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if out.isEmpty { out = "item" }
        if let first = out.first, !first.isLetter { out = "x_\(out)" }
        return String(out.prefix(48))
    }
}
