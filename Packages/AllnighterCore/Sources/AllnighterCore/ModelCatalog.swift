import Foundation

/// Core-owned, deterministic model catalog: built-in/custom definitions, Bench
/// roster overlay, and capability metadata for resolver fallback.
public enum ModelCatalog {
    // MARK: - Built-in capability metadata

    public static let builtInCapabilities: [String: ModelCapabilities] = [
        "model_opus": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .copy, .localContext],
            strengthRank: 100),
        "model_chatgpt": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security],
            strengthRank: 90),
        "model_sonnet": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .fast],
            strengthRank: 80),
        "model_gemini": ModelCapabilities(
            laneTags: [.design, .code, .signal],
            capabilityTags: [.code, .design, .image, .fast],
            strengthRank: 75),
        // Grok is web-aware — a natural Signal scout (interprets public posts/links).
        "model_grok": ModelCapabilities(
            laneTags: [.code, .copy, .signal],
            capabilityTags: [.code, .planner],
            strengthRank: 70),
        "model_composer": ModelCapabilities(
            laneTags: [.code],
            capabilityTags: [.code, .fast],
            strengthRank: 60),
        "model_cursor_composer_25": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .fast],
            strengthRank: 85),
        "model_cursor_grok_45": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner],
            strengthRank: 83),
        "model_cursor_auto": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .fast],
            strengthRank: 88),
        "model_cursor_composer_25_fast": ModelCapabilities(
            laneTags: [.code],
            capabilityTags: [.code, .fast],
            strengthRank: 50),
        "model_opencode_qwen3_coder_next": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review],
            strengthRank: 70),
        "model_opencode_glm_5_2": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review],
            strengthRank: 75)
    ]

    public static var builtIns: [ModelDefinition] {
        // Antigravity encodes effort IN the model name, and variant availability is
        // per-model (3.1 Pro has no Medium → route med to High; the Claude/GPT-OSS
        // routes expose a single variant). Recognized from live `agy` switcher.
        let flashVariants: [EffortLevel: String] = [
            .low: "Gemini 3.5 Flash (Low)", .med: "Gemini 3.5 Flash (Medium)", .high: "Gemini 3.5 Flash (High)"]
        let proVariants: [EffortLevel: String] = [
            .low: "Gemini 3.1 Pro (Low)", .med: "Gemini 3.1 Pro (High)", .high: "Gemini 3.1 Pro (High)"]
        let cursorGrokVariants: [EffortLevel: String] = [
            .low: "cursor-grok-4.5-low", .med: "cursor-grok-4.5-medium", .high: "cursor-grok-4.5-high"]
        func fixed(_ s: String) -> [EffortLevel: String] { [.low: s, .med: s, .high: s] }
        return [
            // Claude Code — effort via the `--effort` flag (see DefaultConfig manifest).
            def("model_opus", "Opus 4.8", "opus", "claude_code", .both, defaultEnabled: true),
            def("model_sonnet", "Sonnet 4.6", "sonnet", "claude_code", .answerer, defaultEnabled: true),
            def("model_fable", "Fable 5", "fable", "claude_code", .answerer, defaultEnabled: false),
            // Codex — recognized from `codex debug models` (visibility == list).
            def("model_chatgpt", "ChatGPT 5.5", "gpt-5.5", "codex", .answerer, defaultEnabled: true),
            def("model_chatgpt_54", "ChatGPT 5.4", "gpt-5.4", "codex", .answerer, defaultEnabled: false),
            def("model_chatgpt_54_mini", "ChatGPT 5.4 mini", "gpt-5.4-mini", "codex", .answerer, defaultEnabled: false),
            def("model_codex_spark", "Codex Spark", "gpt-5.3-codex-spark", "codex", .answerer, defaultEnabled: false),
            // Grok — recognized from `grok models`; effort via `--reasoning-effort`.
            def("model_grok", "Grok 4.5", "grok-4.5", "grok", .answerer, defaultEnabled: true),
            def("model_composer", "Grok Composer 2.5 Fast", "grok-composer-2.5-fast", "grok", .answerer, defaultEnabled: false),
            // Cursor Agent — Auto is the default; regular Composer 2.5 stays on-bench;
            // Fast is explicit opt-in (6× cost). Cursor Grok 4.5 encodes effort in the
            // model id (`agent --list-models`).
            def("model_cursor_auto", "Auto", "auto", "cursor_agent", .answerer, defaultEnabled: true),
            def("model_cursor_composer_25", "Composer 2.5", "composer-2.5", "cursor_agent", .answerer, defaultEnabled: true),
            def("model_cursor_grok_45", "Cursor Grok 4.5", "cursor-grok-4.5-high", "cursor_agent", .answerer, defaultEnabled: true, effortVariants: cursorGrokVariants),
            def("model_cursor_composer_25_fast", "Composer 2.5 Fast", "composer-2.5-fast", "cursor_agent", .answerer, defaultEnabled: false),
            // Antigravity — a multi-model router; effort is encoded in the model name.
            def("model_gemini", "Gemini 3.5 Flash", "Gemini 3.5 Flash (Medium)", "antigravity", .answerer, defaultEnabled: true, effortVariants: flashVariants),
            def("model_gemini_pro", "Gemini 3.1 Pro", "Gemini 3.1 Pro (High)", "antigravity", .answerer, defaultEnabled: false, effortVariants: proVariants),
            def("model_agy_sonnet", "Claude Sonnet 4.6", "Claude Sonnet 4.6 (Thinking)", "antigravity", .answerer, defaultEnabled: false, effortVariants: fixed("Claude Sonnet 4.6 (Thinking)")),
            def("model_agy_opus", "Claude Opus 4.6", "Claude Opus 4.6 (Thinking)", "antigravity", .both, defaultEnabled: false, effortVariants: fixed("Claude Opus 4.6 (Thinking)")),
            def("model_agy_gptoss", "GPT-OSS 120B", "GPT-OSS 120B (Medium)", "antigravity", .answerer, defaultEnabled: false, effortVariants: fixed("GPT-OSS 120B (Medium)")),
            // OpenCode — BYOK provider/model routing (off-Bench by default).
            def("model_opencode_qwen3_coder_next", "Qwen3 Coder Next", "featherless/Qwen/Qwen3-Coder-Next", "opencode", .answerer, defaultEnabled: false),
            def("model_opencode_glm_5_2", "GLM 5.2", "featherless/zai-org/GLM-5.2", "opencode", .answerer, defaultEnabled: false),
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
        // Cursor smoke always targets regular Composer 2.5 — never Auto or Fast.
        if driverId == "cursor_agent",
           let regular = defs.first(where: { $0.id == "model_cursor_composer_25" }) {
            return regular.modelLabel
        }
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
        if let def = get(modelId) {
            // A recognized/custom model with no explicit tags inherits its CLI's
            // representative capabilities so it's usable in its lane out of the box.
            var caps = fallbackCapabilities(driverId: def.driverId)
            // A lighter variant (mini / spark) ranks just below the flagship so
            // `.strongestReady` still prefers the flagship when both are ready.
            if isLighterVariant(def) { caps.strengthRank = max(0, caps.strengthRank - 15) }
            return caps
        }
        return ModelCapabilities()
    }

    /// A faster/cheaper sibling (e.g. "mini", "spark") that should not outrank the
    /// driver's flagship in strongest-ready selection.
    private static func isLighterVariant(_ def: ModelDefinition) -> Bool {
        let hay = (def.displayName + " " + def.modelLabel).lowercased()
        return hay.contains("mini") || hay.contains("spark")
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
        defaultEnabled: Bool, effortVariants: [EffortLevel: String]? = nil
    ) -> ModelDefinition {
        ModelDefinition(
            id: id, displayName: name, modelLabel: label, driverId: driver, role: role,
            origin: .builtIn, defaultEnabled: defaultEnabled,
            capabilities: builtInCapabilities[id] ?? ModelCapabilities(),
            effortVariants: effortVariants)
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
                    enabled: enabled[def.id] ?? def.defaultEnabled,
                    effortVariants: def.effortVariants)
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
        // Inherit the RICHEST built-in's capabilities (most tags), not the
        // alphabetically-first — so adding a capability-less model to a driver never
        // strips inheritance for that driver's custom models.
        list(driverId: driverId)
            .filter { $0.origin == .builtIn }
            .max { $0.capabilities.capabilityTags.count < $1.capabilities.capabilityTags.count }?
            .capabilities ?? ModelCapabilities()
    }
}

enum ModelCatalogPaths {
    static var config: URL { AllnighterSupportRoot.config }
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
