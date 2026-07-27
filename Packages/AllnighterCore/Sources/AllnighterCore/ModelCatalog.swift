import Foundation

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
        "model_chatgpt_sol", // ChatGPT 5.6 Sol via Cursor — paid Cursor quota
    ]

    /// Same underlying model on another driver. Diversity must not seat both
    /// as "distinct" workers (Codex Sol + Cursor Sol is one Sol, not two).
    public static let automaticSubstituteAliases: [String: String] = [
        "model_chatgpt_sol": "model_chatgpt",
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
             "model_agy_opus", "model_agy_sonnet":
            return "claude"
        case "model_chatgpt", "model_chatgpt_sol", "model_chatgpt_terra",
             "model_chatgpt_54", "model_chatgpt_54_mini", "model_codex_spark":
            return "gpt"
        case "model_agy_gptoss":
            return "gpt_oss"
        case "model_grok", "model_composer", "model_cursor_grok_45":
            return "grok"
        case "model_kimi_k3", "model_kimi_k27":
            return "kimi"
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
        default:
            return "driver:\(driverId)"
        }
    }

    // MARK: - Built-in capability metadata

    public static let builtInCapabilities: [String: ModelCapabilities] = [
        // Flagship-only seats (synthesis / Auto default pool).
        // Fable is often unavailable/reserved (Lead-only worker reservation elsewhere),
        // but when it IS available it should be design-eligible too.
        "model_fable": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .design, .copy, .localContext],
            strengthRank: 100),
        "model_chatgpt_sol": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .design, .copy, .localContext],
            strengthRank: 99),
        // ChatGPT 5.6 Sol via Codex — same underlying model as model_chatgpt_sol (Cursor),
        // so it carries Sol's capability profile. Opus remains a strong judgment seat.
        // Codex also generates mockup images (generated-image harvest), so it carries
        // `.image` alongside its Sol design-reasoning profile.
        "model_chatgpt": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .design, .image, .copy, .localContext],
            strengthRank: 99),
        // ChatGPT 5.6 Terra via Codex — the medium-tier ChatGPT seat. It is a
        // distinct model from Sol, so it remains eligible to substitute other
        // Balanced-tier models rather than being excluded as a duplicate seat.
        "model_chatgpt_terra": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .design, .copy, .localContext],
            strengthRank: 86),
        // ChatGPT 5.4 (Codex, off-Bench by default) — a capable non-Sol ChatGPT.
        // Copy-capable per founder so Copy teams have depth beyond the Sol/flagship seats.
        "model_chatgpt_54": ModelCapabilities(
            laneTags: [.code, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .copy],
            strengthRank: 85),
        "model_opus": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .copy, .localContext],
            strengthRank: 90),
        // High + mid value seats — high quality, low price (staff mid work freely).
        // Kimi and both Grok routes outrank Sonnet for worker substitution.
        "model_cursor_grok_45": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .copy],
            strengthRank: 89),
        // Kimi K3 is a great designer (founder note) — design reasoning/critique/
        // direction, NOT image generation.
        "model_kimi_k3": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .design],
            strengthRank: 88),
        // Kimi K2.7 Code — prior-generation coding seat; below K3, still mid/high.
        "model_kimi_k27": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .design],
            strengthRank: 86),
        // Grok is web-aware — a natural Signal scout (interprets public posts/links) —
        // and also generates mockup images (generated-image harvest), so it carries
        // both `.design` (lane) and `.image` (capability) for design work.
        "model_grok": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .copy, .image],
            strengthRank: 87),
        // Sonnet is a strong review-posture Claude model — carries `.security`
        // (CN-S06) so it is a preferred fill for Security Review seats alongside
        // Fable/Opus/Sol. Fable and Opus already carry `.security`.
        "model_sonnet": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .fast],
            strengthRank: 84),
        "model_cursor_composer_25": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .fast],
            strengthRank: 80),
        "model_cursor_auto": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .fast],
            strengthRank: 78),
        // Antigravity Opus 4.6 — fallback-only; never outrank Claude/Cursor/Codex flagships.
        "model_agy_opus": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .copy, .localContext],
            strengthRank: 75),
        "model_gemini_pro": ModelCapabilities(
            laneTags: [.design, .code, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .design, .image, .copy],
            strengthRank: 76),
        "model_gemini": ModelCapabilities(
            laneTags: [.design, .code, .copy, .signal],
            capabilityTags: [.code, .design, .image, .copy, .fast],
            strengthRank: 75),
        "model_agy_sonnet": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .security, .copy, .localContext],
            strengthRank: 74),
        "model_agy_gptoss": ModelCapabilities(
            laneTags: [.code, .design, .copy, .signal],
            capabilityTags: [.code, .planner, .review, .copy],
            strengthRank: 70),
        "model_composer": ModelCapabilities(
            laneTags: [.code],
            capabilityTags: [.code, .fast],
            strengthRank: 60),
        "model_cursor_composer_25_fast": ModelCapabilities(
            laneTags: [.code],
            capabilityTags: [.code, .fast],
            strengthRank: 50),
        "model_chatgpt_54_mini": ModelCapabilities(
            laneTags: [.code, .copy, .signal],
            capabilityTags: [.code, .fast],
            strengthRank: 40),
        "model_codex_spark": ModelCapabilities(
            laneTags: [.code],
            capabilityTags: [.code, .fast],
            strengthRank: 40)
    ]

    /// Floor rank for any model without a `builtInCapabilities` entry (customs /
    /// unevaluated). Seating Law — unrated models never inherit a donor flagship rank.
    public static let unratedModelRank = 40

    /// Caliber band from strengthRank (Flagship ≥95 / High 85–94 / Mid 70–84 / floor).
    /// Owned next to the rank table — never duplicated in the resolver.
    public static func caliberBand(_ rank: Int) -> Int {
        rank >= 95 ? 3 : rank >= 85 ? 2 : rank >= 70 ? 1 : 0
    }

    public static var builtIns: [ModelDefinition] {
        // Antigravity encodes effort IN the model name, and variant availability is
        // per-model (3.1 Pro has no Medium → route med to High; the Claude/GPT-OSS
        // routes expose a single variant). Recognized from live `agy` switcher.
        let flashVariants: [EffortLevel: String] = [
            .low: "Gemini 3.6 Flash (Low)", .med: "Gemini 3.6 Flash (Medium)", .high: "Gemini 3.6 Flash (High)"]
        let proVariants: [EffortLevel: String] = [
            .low: "Gemini 3.1 Pro (Low)", .med: "Gemini 3.1 Pro (High)", .high: "Gemini 3.1 Pro (High)"]
        let cursorGrokVariants: [EffortLevel: String] = [
            .low: "cursor-grok-4.5-low", .med: "cursor-grok-4.5-medium", .high: "cursor-grok-4.5-high"]
        // ChatGPT 5.6 Sol — Cursor Agent labels (`agent --list-models`). Codex CLI
        // was down when this seat was staffed; Sol rides Cursor, not Codex.
        let chatgptSolVariants: [EffortLevel: String] = [
            .low: "gpt-5.6-sol-low", .med: "gpt-5.6-sol-medium", .high: "gpt-5.6-sol-high"]
        func fixed(_ s: String) -> [EffortLevel: String] { [.low: s, .med: s, .high: s] }
        return [
            // Claude Code — effort via the `--effort` flag (see DefaultConfig manifest).
            // Fable 5 is the Claude-side flagship; Sonnet 5 is the default Claude seat;
            // Opus 5 is the high judgment seat (`opus` → Opus 5; not flagship-only).
            def("model_fable", "Fable 5", "fable", "claude_code", .both, defaultEnabled: true),
            def("model_opus", "Opus 5", "opus", "claude_code", .both, defaultEnabled: true),
            def("model_sonnet", "Sonnet 5", "claude-sonnet-5", "claude_code", .answerer, defaultEnabled: true),
            // Codex — ChatGPT 5.6 Sol. Verified callable on codex-cli 0.144.5 (2026-07-18):
            // `codex exec -m gpt-5.6-sol` + reasoning effort via the manifest's `-c
            // model_reasoning_effort` flag → exit 0, real answer. The prior `gpt-5.6` label
            // was rejected 400 ("not supported when using Codex with a ChatGPT account"),
            // and `gpt-5.6-sol` itself needs codex >= 0.144.x ("requires a newer version of
            // Codex"). Sol is the default ChatGPT seat via Codex.
            def("model_chatgpt", "ChatGPT 5.6 Sol (Codex)", "gpt-5.6-sol", "codex", .both, defaultEnabled: true),
            // Terra is the Codex medium seat. It belongs to the Balanced
            // substitution roster, so a ready Terra can cover another medium model.
            def("model_chatgpt_terra", "ChatGPT 5.6 Terra (Codex)", "gpt-5.6-terra", "codex", .both, defaultEnabled: true),
            def("model_chatgpt_54", "ChatGPT 5.4", "gpt-5.4", "codex", .answerer, defaultEnabled: false),
            def("model_chatgpt_54_mini", "ChatGPT 5.4 mini", "gpt-5.4-mini", "codex", .answerer, defaultEnabled: false),
            def("model_codex_spark", "Codex Spark", "gpt-5.3-codex-spark", "codex", .answerer, defaultEnabled: false),
            // Grok — high quality / low price → high + mid work. Effort via `--reasoning-effort`.
            def("model_grok", "Grok 4.5", "grok-4.5", "grok", .answerer, defaultEnabled: true),
            def("model_kimi_k3", "Kimi K3", "kimi-code/k3", "kimi", .both, defaultEnabled: true),
            def("model_kimi_k27", "Kimi K2.7 Code", "kimi-code/kimi-for-coding", "kimi", .both, defaultEnabled: true),
            def("model_composer", "Grok Composer 2.5 Fast", "grok-composer-2.5-fast", "grok", .answerer, defaultEnabled: false),
            // Cursor Agent — Auto is the default; Composer 2.5 at most once in rotations;
            // Cursor Grok 4.5 is high/mid; ChatGPT 5.6 Sol is the Cursor-side flagship.
            def("model_cursor_auto", "Auto", "auto", "cursor_agent", .answerer, defaultEnabled: true),
            def("model_cursor_composer_25", "Composer 2.5", "composer-2.5", "cursor_agent", .answerer, defaultEnabled: true),
            def("model_cursor_grok_45", "Cursor Grok 4.5", "cursor-grok-4.5-high", "cursor_agent", .answerer, defaultEnabled: true, effortVariants: cursorGrokVariants),
            // Cursor Sol is NEVER on-Bench by default and NEVER an automatic
            // substitute — it burns paid Cursor quota. Codex Sol (`model_chatgpt`)
            // is the only default Sol route; Cursor Sol is manual opt-in only.
            def("model_chatgpt_sol", "ChatGPT 5.6 Sol (Cursor)", "gpt-5.6-sol-high", "cursor_agent", .both, defaultEnabled: false, effortVariants: chatgptSolVariants),
            def("model_cursor_composer_25_fast", "Composer 2.5 Fast", "composer-2.5-fast", "cursor_agent", .answerer, defaultEnabled: false),
            // Antigravity — a multi-model router; effort is encoded in the model name.
            def("model_gemini", "Gemini 3.6 Flash", "Gemini 3.6 Flash (Medium)", "antigravity", .answerer, defaultEnabled: true, effortVariants: flashVariants),
            def("model_gemini_pro", "Gemini 3.1 Pro", "Gemini 3.1 Pro (High)", "antigravity", .answerer, defaultEnabled: false, effortVariants: proVariants),
            def("model_agy_sonnet", "Claude Sonnet 4.6", "Claude Sonnet 4.6 (Thinking)", "antigravity", .answerer, defaultEnabled: false, effortVariants: fixed("Claude Sonnet 4.6 (Thinking)")),
            def("model_agy_opus", "Claude Opus 4.6", "Claude Opus 4.6 (Thinking)", "antigravity", .both, defaultEnabled: false, effortVariants: fixed("Claude Opus 4.6 (Thinking)")),
            def("model_agy_gptoss", "GPT-OSS 120B", "GPT-OSS 120B (Medium)", "antigravity", .answerer, defaultEnabled: false, effortVariants: fixed("GPT-OSS 120B (Medium)")),
            // OpenCode ships NO built-in models (founder ruling 2026-07-24: <1% of users
            // run opencode with these models, so they were removed from the defaults). The
            // opencode DRIVER stays registered so users can add their own models via
            // `alln model add` (BYOK provider/model routing).
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
        if let caps = builtInCapabilities[modelId] { return caps }
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
