import Foundation
import AgentOSCLI

/// Core-owned, deterministic model catalog: built-in/custom definitions, Bench
/// roster overlay, and capability metadata for resolver fallback.
public enum ModelCatalog {
    // MARK: - Automatic substitution law

    /// Paid / reseller routes that must never be chosen by automatic
    /// substitution, diversity fill, or Lead fallback — even when "ready."
    /// They remain usable only when the row/Lead **explicitly** prefers them
    /// (or lists them in `fallbackModelIds`) after the user opted in.
    /// Ready ≠ automatic substitute.
    public static let neverAutomaticSubstituteIds: Set<String> = [
        "model_cursor_gpt_sol", // GPT-5.6 Sol via Cursor — paid Cursor quota
    ]

    /// Same underlying model on another driver. Diversity must not seat both
    /// as "distinct" workers (Codex Sol + Cursor Sol is one Sol, not two).
    public static let automaticSubstituteAliases: [String: String] = [
        "model_cursor_gpt_sol": "model_gpt_sol",
    ]

    /// True when this model may be picked by broad automatic policies
    /// (`.strongestReady` / `.anyReady` / `.laneCapable` fills, need-row
    /// diversity). Explicit preferred / ordered fallback ids still win.
    public static func allowsAutomaticSubstitution(_ modelId: String) -> Bool {
        !neverAutomaticSubstituteIds.contains(modelId)
    }

    /// Expand a claimed model id to every id that counts as the same seat for
    /// cross-row diversity (aliases both directions).
    public static func diversityExclusionIds(for modelId: String) -> Set<String> {
        var ids: Set<String> = [modelId]
        if let canonical = automaticSubstituteAliases[modelId] {
            ids.insert(canonical)
        }
        for (alias, canonical) in automaticSubstituteAliases where canonical == modelId || ids.contains(canonical) {
            ids.insert(alias)
            ids.insert(canonical)
        }
        return ids
    }

    /// Underlying reasoning family for cross-source diversity. Built-in ids use
    /// the switch; customs/unknowns use `hostFamily(driverId:)` so a custom
    /// Claude Haiku counts as `claude`, not as its own id.
    /// Pass `driverId` from the ready `Model` when the id may not be on disk yet.
    public static func modelFamily(_ modelId: String, driverId: String? = nil) -> String {
        switch modelId {
        case "model_fable", "model_opus", "model_sonnet",
             "model_agy_opus", "model_agy_sonnet",
             "model_cursor_fable", "model_cursor_opus", "model_cursor_sonnet":
            return "claude"
        case "model_gpt_sol", "model_cursor_gpt_sol", "model_gpt_terra", "model_gpt_luna",
             "model_gpt_54", "model_gpt_54_mini", "model_gpt_spark":
            return "gpt"
        case "model_agy_gptoss":
            return "gpt_oss"
        case "model_grok", "model_grok_composer_25_fast", "model_cursor_grok_45":
            return "grok"
        case "model_kimi_k3", "model_kimi_k27":
            return "kimi"
        case "model_muse_spark_12", "model_muse_spark_12_contributor":
            return "muse"
        case "model_gemini", "model_gemini_pro":
            return "gemini"
        case "model_cursor_auto", "model_cursor_composer_25", "model_cursor_composer_25_fast":
            return "cursor_native"
        default:
            if let def = get(modelId) {
                return hostFamily(driverId: def.driverId)
            }
            if let driverId {
                return hostFamily(driverId: driverId)
            }
            return modelId
        }
    }

    /// Family for an unknown/custom model id from its CLI driver.
    public static func hostFamily(driverId: String) -> String {
        switch driverId {
        case "claude_code": return "claude"
        case "codex": return "gpt"
        case "grok": return "grok"
        case "kimi": return "kimi"
        case "muse": return "muse"
        default:
            return "driver:\(driverId)"
        }
    }

    // MARK: - Bundled catalog authority

    private static let bundledAuthority: (catalog: LoadedCatalog, overlay: CatalogOverlay) = {
        do {
            return (try CatalogLoader.bundled(), try CatalogOverlayLoader.bundled())
        } catch {
            preconditionFailure("ModelCatalog bundled authority failed: \(error)")
        }
    }()

    /// Bench policy + caliber for built-in ids. Derived from `catalog_overlay.json`.
    public static var builtInCapabilities: [String: ModelCapabilities] {
        Dictionary(uniqueKeysWithValues: builtIns.map { ($0.id, $0.capabilities) })
    }

    /// Built-in model definitions merged from AgentOS catalog + Allnighter overlay.
    public static var builtIns: [ModelDefinition] {
        do {
            return try CatalogMerge.builtInDefinitions(
                catalog: bundledAuthority.catalog,
                overlay: bundledAuthority.overlay
            )
        } catch {
            preconditionFailure("ModelCatalog built-in merge failed: \(error)")
        }
    }

    public static func bundledRegistry() -> DriverRegistry {
        bundledAuthority.catalog.driverRegistry()
    }

    /// Floor rank for any model without overlay `caliber` (customs / unevaluated).
    public static let unratedModelRank = 40

    /// Caliber band from strengthRank (Elite ≥95 / Strong 85–94 / Capable 70–84 / floor).
    public static func caliberBand(_ rank: Int) -> Int {
        rank >= 95 ? 3 : rank >= 85 ? 2 : rank >= 70 ? 1 : 0
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

    /// Bench default reasoning effort for a built-in seat (overlay policy only).
    public static func benchDefaultEffort(for modelId: ModelID) -> EffortLevel? {
        builtIns.first { $0.id == modelId }?.defaultEffort
    }

    public static func resolvedModels(registry: DriverRegistry) -> [Model] {
        try? reconcileRosterWithCatalog()
        return materialize(mergedDefinitions(), registry: registry)
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
        diags.append(contentsOf: CatalogMerge.unknownOverlayDiagnostics(
            overlay: bundledAuthority.overlay,
            catalog: bundledAuthority.catalog
        ))
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
            diags.append(contentsOf: CatalogMerge.hiddenRosterDiagnostics(
                overlay: bundledAuthority.overlay,
                roster: roster
            ))
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
        guard let def = get(id) else { throw ModelCatalogError.notFound(id) }
        if enabled, def.origin == .custom,
           let status = def.modelSmokeStatus, status != ModelSmokeStatus.recognized.rawValue {
            throw ModelCatalogError.invalid(
                "custom model is not smoke-verified; run: alln models verify \(id)")
        }
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
            // Unrated law: never persist a donor flagship profile. Tags/rank come
            // from `capabilities()` at read time (driver tags + unratedModelRank).
            capabilities: ModelCapabilities(),
            createdAt: now,
            updatedAt: now,
            modelSmokeStatus: "unverified"
        )
        try saveCustom(def)
        // Custom models stay off the Bench until smoke-verified (`alln models verify`); do not setEnabled(true) here.
        try ensureRosterExists()
        try setEnabled(newId, false)
        return def
    }

    /// Runs AgentOS model smoke for a custom catalog entry and persists status/detail.
    /// Does not auto-enable — caller runs `alln models enable` after `.recognized`.
    ///
    /// `probeRecords` comes from `SetupStore().load().records` (Engine); Core cannot
    /// depend on SetupStore. nil loads the default `cli_setup.json` under the support root.
    @discardableResult
    public static func verifyModelSmoke(
        id: ModelID,
        registry: DriverRegistry,
        invoker: (any WorkerInvoking)? = nil,
        probeRecords: [ToolProbeRecord]? = nil
    ) async throws -> ModelSmokeResult {
        guard let def = get(id) else { throw ModelCatalogError.notFound(id) }
        guard def.origin == .custom else {
            throw ModelCatalogError.invalid("only custom models can be smoke-verified")
        }
        guard var manifest = registry.manifest(id: def.driverId) else {
            throw ModelCatalogError.driverMissing(def.driverId)
        }
        guard manifest.invoke != nil else {
            throw ModelCatalogError.invalid("driver '\(def.driverId)' has no invoke path")
        }
        let records = probeRecords ?? loadDefaultProbeRecords()
        guard let absolutePath = resolvedBinaryPath(driverId: def.driverId, records: records) else {
            throw ModelCatalogError.invalid("CLI not detected/ready")
        }
        var invoke = manifest.invoke!
        invoke.command = absolutePath
        manifest.invoke = invoke

        #if os(macOS) || os(Linux)
        let runner: any WorkerInvoking = invoker ?? DefaultWorkerRunner()
        #else
        guard let invoker else {
            throw ModelCatalogError.invalid("No worker invoker.")
        }
        let runner = invoker
        #endif

        let smoke = await ModelSmokeVerifier(invoker: runner).verify(
            manifest: manifest, label: def.modelLabel)
        var updated = def
        updated.modelSmokeStatus = smoke.status.rawValue
        updated.modelSmokeDetail = smoke.detail
        try updateCustom(updated)
        return smoke
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

    /// Capabilities for a model id. Built-ins use the table. Everything else is
    /// **unrated**: driver tags only, `unratedModelRank` — persisted donor ranks
    /// on custom JSON are ignored (Seating Law).
    public static func capabilities(_ modelId: String) -> ModelCapabilities {
        if let caps = builtIns.first(where: { $0.id == modelId })?.capabilities { return caps }
        if let def = get(modelId) {
            var caps = fallbackCapabilities(driverId: def.driverId)
            caps.strengthRank = unratedModelRank
            return caps
        }
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
        let ids = definitions.filter(\.defaultEnabled).map(\.id)
        return ModelRosterState(
            enabledModelIds: ids,
            catalogSeenModelIds: definitions.map(\.id))
    }

    /// Built-ins that shipped default-on before roster newcomer tracking existed.
    private static let legacyDefaultOnBackfillIds: Set<ModelID> = ["model_kimi_k27"]

    /// Default-on built-ins added after the roster was first saved get enabled once;
    /// models the user turned off stay off (they remain in `catalogSeenModelIds`).
    private static func reconcileRosterWithCatalog() throws {
        let definitions = mergedDefinitions()
        let builtIns = definitions.filter { $0.origin == .builtIn }
        let catalogIds = Set(builtIns.map(\.id))
        var roster = rosterPersistence().load() ?? defaultRosterState(definitions: definitions)
        var changed = false

        if roster.catalogSeenModelIds == nil {
            roster.catalogSeenModelIds = Array(catalogIds)
            // Legacy backfill only for pre-tracking rosters that still have seats on
            // the bench. An explicitly empty enabled list is a cleared bench — do not
            // force-enable newcomers onto it (empty-bench front door must stay empty
            // and surface AgentFrontDoor counsel, not a silent bare one-seat reseed).
            if !roster.enabledModelIds.isEmpty {
                for id in legacyDefaultOnBackfillIds where catalogIds.contains(id) {
                    guard let def = builtIns.first(where: { $0.id == id }),
                          def.defaultEnabled,
                          !roster.enabledModelIds.contains(id) else { continue }
                    roster.enabledModelIds.append(id)
                    changed = true
                }
            }
            try rosterPersistence().save(roster)
            return
        }

        let seen = Set(roster.catalogSeenModelIds ?? [])
        let newcomers = catalogIds.subtracting(seen).sorted()
        guard !newcomers.isEmpty else { return }
        for id in newcomers {
            guard let def = builtIns.first(where: { $0.id == id }),
                  def.defaultEnabled,
                  !roster.enabledModelIds.contains(id) else { continue }
            roster.enabledModelIds.append(id)
            changed = true
        }
        roster.catalogSeenModelIds = Array(catalogIds)
        if changed || !newcomers.isEmpty {
            try rosterPersistence().save(roster)
        }
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

    /// Absolute binary for `ready` / `installedNotProbed` probe rows (direct/shim).
    private static func resolvedBinaryPath(
        driverId: String, records: [ToolProbeRecord]
    ) -> String? {
        guard let record = records.first(where: { $0.driverId == driverId }) else { return nil }
        switch record.status {
        case .ready, .installedNotProbed:
            return record.invocation?.resolvedPath
        default:
            return nil
        }
    }

    /// Mirrors `SetupStore.State.records` without importing AllnighterEngine.
    private static func loadDefaultProbeRecords() -> [ToolProbeRecord] {
        struct SetupState: Codable { var records: [ToolProbeRecord] }
        let url = AllnighterSupportRoot.config.appendingPathComponent("cli_setup.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? CoreJSON.decode(SetupState.self, from: data) else {
            return []
        }
        return state.records
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
