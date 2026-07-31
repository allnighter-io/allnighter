import Foundation

/// One worker row that could not resolve, kept honest in the run snapshot.
public struct DisabledRow: Sendable, Equatable {
    public var rowId: String
    public var skillId: String
    public var skillName: String
    public var required: Bool
    public var reason: String
    public init(rowId: String, skillId: String, skillName: String, required: Bool, reason: String) {
        self.rowId = rowId; self.skillId = skillId; self.skillName = skillName
        self.required = required; self.reason = reason
    }
}

/// The concrete run snapshot the resolver produces from a team + effort + bench.
/// Answer workers run blind; review workers run after them; the synthetic plan
/// writer runs last. A run is `isRunnable` only when at least one answer worker
/// resolved and the plan writer resolved.
public struct ResolvedTeamRun: Sendable, Equatable {
    public var teamPresetId: String
    public var teamDisplayName: String
    public var lane: WorkLane
    public var outputKind: TeamOutputKind
    public var mutating: Bool
    public var effort: EffortLevel
    /// Optional Stage-0 scout that runs first and distills the source for the crew.
    public var scoutWorker: Agent?
    public var answerWorkers: [Agent]
    public var reviewWorkers: [Agent]
    public var planWriter: Agent?
    /// How the output writer treats disagreement (from the synthesis policy).
    public var dissentPolicy: DissentPolicy
    public var disabledRows: [DisabledRow]
    public var warnings: [String]
    public var isRunnable: Bool
    public var blockReason: String?
    /// Distinct `driverId` values among resolved workers (sorted). Populated by
    /// `TeamSourceFacts.enrich` after resolution.
    public var resolvedSourceIds: [String] = []
    /// When exactly one source participates, the execution owner for mutating runs.
    public var executionSourceId: String? = nil

    /// Scout + answer + review + plan-writer, in execution order.
    public var allWorkers: [Agent] {
        (scoutWorker.map { [$0] } ?? []) + answerWorkers + reviewWorkers + (planWriter.map { [$0] } ?? [])
    }

    public init(
        teamPresetId: String, teamDisplayName: String, lane: WorkLane,
        outputKind: TeamOutputKind, mutating: Bool = false,
        effort: EffortLevel,
        scoutWorker: Agent? = nil,
        answerWorkers: [Agent] = [], reviewWorkers: [Agent] = [], planWriter: Agent? = nil,
        dissentPolicy: DissentPolicy = .preserveDissent,
        disabledRows: [DisabledRow] = [], warnings: [String] = [],
        isRunnable: Bool = false, blockReason: String? = nil,
        resolvedSourceIds: [String] = [], executionSourceId: String? = nil
    ) {
        self.teamPresetId = teamPresetId; self.teamDisplayName = teamDisplayName
        self.lane = lane; self.outputKind = outputKind
        self.mutating = mutating; self.effort = effort
        self.scoutWorker = scoutWorker
        self.answerWorkers = answerWorkers; self.reviewWorkers = reviewWorkers
        self.planWriter = planWriter; self.dissentPolicy = dissentPolicy
        self.disabledRows = disabledRows
        self.warnings = warnings; self.isRunnable = isRunnable; self.blockReason = blockReason
        self.resolvedSourceIds = resolvedSourceIds; self.executionSourceId = executionSourceId
    }
}

/// Pure, deterministic team resolution: a lane team + effort + ready bench →
/// a concrete run snapshot (Team_Catalog §Team Resolution). Never runs
/// anything and never infers a lane. Capability/skill lookups are injectable for
/// tests; defaults come from `ModelCatalog`/`SkillCatalog`.
public enum TeamResolver {

    public static func resolve(
        team: TeamPreset,
        requestLane: WorkLane,
        requestEffort: EffortLevel?,
        readyModels: [Model],
        capabilities: (String) -> ModelCapabilities = ModelCatalog.capabilities,
        skill: (String) -> Skill? = SkillCatalog.skill
    ) -> ResolvedTeamRun {
        let effort = requestEffort ?? team.defaultEffort
        var result = ResolvedTeamRun(
            teamPresetId: team.id, teamDisplayName: team.displayName, lane: team.lane,
            outputKind: team.outputKind, mutating: team.mutating, effort: effort
        )

        // Rule 1: lane must match (reject before running).
        guard team.lane == requestLane else {
            result.blockReason = "team \(team.id) is a \(team.lane.rawValue) team but the request lane is \(requestLane.rawValue)"
            return result
        }

        // Rules 3-4: all worker rows are active (no effort gate); split answer/review (declared order).
        let active = team.agentSpecs
        let answerRows = active.filter { $0.purpose == .answer }
        let reviewRows = active.filter { $0.purpose == .review }

        // Resolve the Lead first. Agent rows avoid the model that actually won
        // Lead resolution when alternatives exist; this also works when the Lead
        // came from an ordered cross-source fallback chain.
        let lead = team.lead
        let resolvedLeadModelId = selectModel(
            preferredModelId: lead.preferredModelId,
            fallbackModelIds: lead.fallbackModelIds ?? [], allowedModelIds: [],
            requiredTags: lead.requiredCapabilityTags, fallback: lead.fallbackPolicy,
            lane: team.lane, ready: readyModels, capabilities: capabilities
        )?.model.id
        let reservedWorkerModelId = resolvedLeadModelId

        // Family + driver diversity (Seating Law): seeded by Lead, grown by every
        // resolved row / scout / triangle pick. Prefer unused family then unused
        // driver within a caliber band — never a hard filter.
        var familyUsed: Set<String> = []
        var driversUsed: Set<String> = []
        if let resolvedLeadModelId {
            let leadDriver = readyModels.first(where: { $0.id == resolvedLeadModelId })?.driverId
                ?? ModelCatalog.get(resolvedLeadModelId)?.driverId
            familyUsed.insert(ModelCatalog.modelFamily(resolvedLeadModelId, driverId: leadDriver))
            if let leadDriver { driversUsed.insert(leadDriver) }
        }

        // instanceIndex is global per model across all stages so ids stay distinct
        // and self-fusion reads as `model#0, model#1, …`.
        var nextIndex: [String: Int] = [:]
        var warnings: [String] = []
        var disabled: [DisabledRow] = []
        var requiredBlock: String?

        // Cross-row id diversity: capability-only rows skip already-claimed models
        // when a best-band alternative remains (band-aware filter in selectModel).
        var diversityUsed: Set<String> = []

        func makeWorker(
            _ model: Model, row: TeamAgentSpec, skillName: String, stage: AgentStage,
            seatingReason: String? = nil
        ) -> Agent {
            let index = nextIndex[model.id, default: 0]
            nextIndex[model.id] = index + 1
            let substitutedFrom = row.preferredModelId.flatMap { $0 != model.id ? $0 : nil }
            return Agent(
                id: Agent.makeID(modelId: model.id, instanceIndex: index),
                modelId: model.id, instanceIndex: index,
                skillId: row.skillId, skillName: skillName, purpose: stage,
                substitutedFromModelId: substitutedFrom,
                seatingReason: seatingReason,
                agentId: row.id)
        }

        func disable(_ row: TeamAgentSpec, _ skillName: String, _ reason: String) {
            disabled.append(DisabledRow(rowId: row.id, skillId: row.skillId, skillName: skillName, required: row.required, reason: reason))
            if row.required {
                requiredBlock = requiredBlock ?? "required worker \(skillName) could not resolve: \(reason)"
            } else {
                warnings.append("Optional worker \(skillName) disabled: \(reason).")
            }
        }

        func noteReuse(_ model: Model, skillName: String) {
            let family = ModelCatalog.modelFamily(model.id, driverId: model.driverId)
            if familyUsed.contains(family) {
                warnings.append("\(skillName): reusing family \(family) (no unused-family candidate in band).")
            }
        }

        func claim(_ model: Model, capabilityOnly: Bool) {
            if capabilityOnly {
                diversityUsed.formUnion(ModelCatalog.diversityExclusionIds(for: model.id))
            }
            familyUsed.insert(ModelCatalog.modelFamily(model.id, driverId: model.driverId))
            driversUsed.insert(model.driverId)
        }

        // Stage 0 scout runs before the crew and seeds diversity sets.
        var scoutWorker: Agent?
        if let scoutSpec = team.scout {
            let scoutSkillName = skill(scoutSpec.skillId)?.displayName ?? scoutSpec.skillId
            if let model = selectModel(
                preferredModelId: scoutSpec.preferredModelId,
                fallbackModelIds: scoutSpec.fallbackModelIds ?? [], allowedModelIds: scoutSpec.allowedModelIds,
                requiredTags: scoutSpec.requiredCapabilityTags, fallback: scoutSpec.fallbackPolicy,
                lane: team.lane, ready: readyModels, capabilities: capabilities,
                avoidFamilies: familyUsed, avoidDrivers: driversUsed
            ) {
                if let pref = scoutSpec.preferredModelId, pref != model.model.id {
                    warnings.append("\(scoutSkillName): preferred scout \(pref) unavailable; resolved to \(model.model.displayName).")
                }
                scoutWorker = makeWorker(
                    model.model, row: scoutSpec, skillName: scoutSkillName, stage: .scout,
                    seatingReason: model.reason)
                claim(model.model, capabilityOnly: scoutSpec.preferredModelId == nil)
            } else {
                disable(scoutSpec, scoutSkillName, "no ready model for scout in lane \(team.lane.rawValue)")
            }
        }

        func resolveRows(_ rows: [TeamAgentSpec], stage: AgentStage) -> [Agent] {
            var workers: [Agent] = []
            for row in rows {
                let skillName = skill(row.skillId)?.displayName ?? row.skillId
                let want = max(1, row.count)

                if row.triangulate {
                    let models = selectTriangle(
                        count: want, preferenceIds: row.triangulatePreferenceIds,
                        requiredTags: row.requiredCapabilityTags, lane: team.lane,
                        ready: readyModels, reserveModelId: resolvedLeadModelId,
                        capabilities: capabilities)
                    guard !models.isEmpty else {
                        disable(row, skillName, "no ready model in lane \(team.lane.rawValue) for triangulation")
                        continue
                    }
                    if models.count < want {
                        warnings.append("\(skillName): triangulation degraded — \(models.count) distinct source(s) ready, wanted \(want).")
                    }
                    for model in models {
                        noteReuse(model, skillName: skillName)
                        claim(model, capabilityOnly: true)
                        workers.append(makeWorker(model, row: row, skillName: skillName, stage: stage))
                    }
                    continue
                }

                let excludeForDiversity = row.preferredModelId == nil ? diversityUsed : []
                guard let model = selectModel(
                    preferredModelId: row.preferredModelId,
                    fallbackModelIds: row.fallbackModelIds ?? [], allowedModelIds: row.allowedModelIds,
                    requiredTags: row.requiredCapabilityTags, fallback: row.fallbackPolicy,
                    lane: team.lane, ready: readyModels, capabilities: capabilities,
                    reserveModelId: reservedWorkerModelId, excludeModelIds: excludeForDiversity,
                    preferredTags: row.preferredCapabilityTags,
                    avoidFamilies: familyUsed, avoidDrivers: driversUsed
                ) else {
                    let reason = "no ready model matches \(row.fallbackPolicy.rawValue)"
                        + (row.preferredModelId.map { " (preferred \($0) unavailable)" } ?? "")
                    disable(row, skillName, reason)
                    continue
                }
                if let preferred = row.preferredModelId, preferred != model.model.id {
                    warnings.append("\(skillName): preferred \(preferred) unavailable; resolved to \(model.model.displayName).")
                }
                if row.preferredModelId == nil {
                    noteReuse(model.model, skillName: skillName)
                }
                claim(model.model, capabilityOnly: row.preferredModelId == nil)
                for _ in 0..<want {
                    workers.append(makeWorker(
                        model.model, row: row, skillName: skillName, stage: stage,
                        seatingReason: model.reason))
                }
            }
            return workers
        }

        let answerWorkers = resolveRows(answerRows, stage: .answer)
        let reviewWorkers = resolveRows(reviewRows, stage: .review)

        // Rule 9: the mandatory Team Lead (synthesizer) — exactly one worker, from
        // `team.lead` (effort-independent). Resolves its model by name like a row.
        result.dissentPolicy = lead.dissentPolicy
        var planWriter: Agent?
        if let pick = selectModel(
            preferredModelId: lead.preferredModelId,
            fallbackModelIds: lead.fallbackModelIds ?? [],
            allowedModelIds: [],
            requiredTags: lead.requiredCapabilityTags,
            fallback: lead.fallbackPolicy,
            lane: team.lane, ready: readyModels, capabilities: capabilities
        ) {
            let leadSkill = skill(lead.skillId)
            let index = nextIndex[pick.model.id, default: 0]
            nextIndex[pick.model.id] = index + 1
            // `lead` is a `TeamLeadSpec`, not a `TeamAgentSpec` roster row — it has
            // no `id`, so the plan writer has no roster seat to inherit. Leave
            // `agentId` nil rather than inventing one.
            planWriter = Agent(
                id: Agent.makeID(modelId: pick.model.id, instanceIndex: index),
                modelId: pick.model.id, instanceIndex: index,
                skillId: lead.skillId,
                skillName: leadSkill?.displayName ?? lead.skillId,
                purpose: .plan,
                seatingReason: pick.reason
            )
        }

        // Self-fusion / admission warnings (honest, never an estimate).
        let allModelIds = (answerWorkers + reviewWorkers + (planWriter.map { [$0] } ?? [])).map(\.modelId)
        if Set(allModelIds).count == 1, allModelIds.count > 1, let only = allModelIds.first {
            let name = readyModels.first { $0.id == only }?.displayName ?? only
            warnings.insert("Only one ready model. Running \(allModelIds.count) workers on \(name).", at: 0)
            warnings.append("Same-source workers may queue under admission for \(name).")
        }

        // Runnable gate (rules 7, 10): a required row blocks; need ≥1 answer worker
        // and a resolved plan writer.
        result.scoutWorker = scoutWorker
        result.answerWorkers = answerWorkers
        result.reviewWorkers = reviewWorkers
        result.planWriter = planWriter
        result.disabledRows = disabled
        result.warnings = warnings

        if let requiredBlock {
            result.blockReason = requiredBlock
        } else if answerWorkers.isEmpty {
            result.blockReason = "no answer worker resolved for \(team.displayName) at \(effort.rawValue) effort"
        } else if planWriter == nil {
            result.blockReason = "plan/output writer could not resolve for \(team.displayName)"
        }
        result.isRunnable = result.blockReason == nil
        TeamSourceFacts.enrich(&result, models: readyModels)
        return result
    }

    // MARK: - Model selection

    /// Resolved model plus seating audit reason for dry-run projection.
    struct SeatingPick: Sendable, Equatable {
        var model: Model
        var reason: String
    }

    /// Derive the seating reason before `claim` updates diversity sets.
    /// Do not emit `reserveSkipped` just because the Lead model was held out —
    /// a Flagship Lead would win every later seat if re-added, so that label
    /// lies on multi-seat teams. Keep the token in the doc for a future
    /// precise counterfactual; capability fills use family / floor reasons.
    static func seatingReason(
        for model: Model,
        pickedViaPreferred: Bool,
        avoidFamilies: Set<String>,
        capabilities: (String) -> ModelCapabilities
    ) -> String {
        if pickedViaPreferred { return "preferred" }
        let family = ModelCatalog.modelFamily(model.id, driverId: model.driverId)
        if avoidFamilies.contains(family) { return "reuseFamily" }
        if capabilities(model.id).strengthRank == ModelCatalog.unratedModelRank { return "unratedFloor" }
        return "band+unusedFamily"
    }

    /// Choose a model for one row: try the preferred, then the declared ordered
    /// cross-source substitutes, then the broad fallback policy. Rank is the final
    /// catch-all for custom models and benches outside the built-in chain.
    /// `excludeModelIds` is the cross-row diversity set (Law 3) — models already
    /// claimed by earlier capability-only rows in this team's resolution pass are
    /// skipped when a distinct capable alternative remains, and reused (never
    /// blocked) once the capable pool is exhausted.
    ///
    /// **Automatic substitution law:** Ready ≠ automatic substitute.
    /// `ModelCatalog.neverAutomaticSubstituteIds` (e.g. Cursor Sol) are never
    /// chosen by broad policies — only by explicit preferred / ordered fallback.
    /// Broad fills also stay on the preferred model's home driver when one was
    /// declared (Claude→Claude, Codex→Codex, Cursor→Cursor, …).
    static func selectModel(
        preferredModelId: String?,
        fallbackModelIds: [String] = [],
        allowedModelIds: [String],
        requiredTags: [ModelCapabilityTag],
        fallback: ModelFallbackPolicy,
        lane: WorkLane,
        ready: [Model],
        capabilities: (String) -> ModelCapabilities,
        reserveModelId: String? = nil,
        excludeModelIds: Set<String> = [],
        preferredTags: [ModelCapabilityTag] = [],
        avoidFamilies: Set<String> = [],
        avoidDrivers: Set<String> = []
    ) -> SeatingPick? {
        // Snapshot once — no CatalogFileIO inside the sort comparator.
        var capsCache: [String: ModelCapabilities] = [:]
        func caps(_ id: String) -> ModelCapabilities {
            if let c = capsCache[id] { return c }
            let c = capabilities(id)
            capsCache[id] = c
            return c
        }
        let byId = Dictionary(ready.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func allowed(_ m: Model) -> Bool { allowedModelIds.isEmpty || allowedModelIds.contains(m.id) }
        func hasTags(_ m: Model) -> Bool {
            let tags = caps(m.id).capabilityTags
            return requiredTags.allSatisfy { tags.contains($0) }
        }
        func hasPreferred(_ m: Model) -> Bool {
            let tags = caps(m.id).capabilityTags
            return preferredTags.allSatisfy { tags.contains($0) }
        }
        func laneOK(_ m: Model) -> Bool { caps(m.id).laneTags.contains(lane) }
        func autoOK(_ m: Model) -> Bool { ModelCatalog.allowsAutomaticSubstitution(m.id) }
        // Seating Law sort: band → preferred tags → unused family → unused driver → rank → id.
        // Sonnet often absent on a full bench after Lead claimed claude — intended.
        func strongest(_ models: [Model]) -> Model? {
            models.sorted { a, b in
                let ra = caps(a.id).strengthRank, rb = caps(b.id).strengthRank
                let ba = ModelCatalog.caliberBand(ra), bb = ModelCatalog.caliberBand(rb)
                if ba != bb { return ba > bb }
                let pa = hasPreferred(a), pb = hasPreferred(b)
                if pa != pb { return pa && !pb }
                let fa = ModelCatalog.modelFamily(a.id, driverId: a.driverId)
                let fb = ModelCatalog.modelFamily(b.id, driverId: b.driverId)
                let usedA = avoidFamilies.contains(fa), usedB = avoidFamilies.contains(fb)
                if usedA != usedB { return !usedA && usedB }
                let da = avoidDrivers.contains(a.driverId), db = avoidDrivers.contains(b.driverId)
                if da != db { return !da && db }
                if ra != rb { return ra > rb }
                return a.id < b.id
            }.first
        }

        func wrap(_ model: Model, pickedViaPreferred: Bool) -> SeatingPick {
            SeatingPick(
                model: model,
                reason: seatingReason(
                    for: model,
                    pickedViaPreferred: pickedViaPreferred,
                    avoidFamilies: avoidFamilies,
                    capabilities: capabilities
                )
            )
        }

        var pool = ready.filter(allowed)
        if fallback == .exactOnly {
            if let preferredModelId,
               let model = pool.first(where: { $0.id == preferredModelId }) {
                return wrap(model, pickedViaPreferred: true)
            }
            guard !allowedModelIds.isEmpty else { return nil }
            guard let model = strongest(pool.filter(hasTags).filter(autoOK)) else { return nil }
            return wrap(model, pickedViaPreferred: false)
        }
        let homeDriver = preferredModelId.flatMap { id in
            byId[id]?.driverId ?? ModelCatalog.get(id)?.driverId
        }
        func homeOK(_ m: Model) -> Bool {
            guard let homeDriver else { return true }
            return m.driverId == homeDriver
        }
        if let reserved = reserveModelId,
           pool.contains(where: { $0.id != reserved && hasTags($0) && autoOK($0) && homeOK($0) }) {
            pool.removeAll { $0.id == reserved }
        }
        // Band-aware exclusion: bestBand is the best caliber still available among
        // *unclaimed* candidates. If every capable model is already claimed, fall
        // back to the absolute best band and keep the unfiltered pool (reuse).
        // Computing bestBand on the full pool would lock Flagship reuse forever
        // and never reach High unused families (breaks Spec Review Min W1).
        let expandedExclude = excludeModelIds.reduce(into: Set<String>()) { acc, id in
            acc.formUnion(ModelCatalog.diversityExclusionIds(for: id))
        }
        if !expandedExclude.isEmpty {
            let eligible = pool.filter { hasTags($0) && autoOK($0) }
            let unclaimed = eligible.filter { !expandedExclude.contains($0.id) }
            let bandSource = unclaimed.isEmpty ? eligible : unclaimed
            let bestBand = bandSource.map { ModelCatalog.caliberBand(caps($0.id).strengthRank) }.max()
            let filtered = pool.filter { !expandedExclude.contains($0.id) }
            if let bestBand,
               filtered.contains(where: {
                   hasTags($0) && autoOK($0) && ModelCatalog.caliberBand(caps($0.id).strengthRank) == bestBand
               }) {
                pool = filtered
            }
        }
        if let pref = preferredModelId,
           let model = pool.first(where: { $0.id == pref }) {
            return wrap(model, pickedViaPreferred: true)
        }
        for id in fallbackModelIds {
            if let model = pool.first(where: { $0.id == id && hasTags($0) }) {
                return wrap(model, pickedViaPreferred: false)
            }
        }
        let autoPool = pool.filter(hasTags).filter(autoOK)
        let picked: Model?
        switch fallback {
        case .exactOnly:
            picked = nil
        case .sameSource:
            picked = strongest(autoPool.filter(homeOK))
        case .laneCapable:
            if homeDriver != nil {
                picked = strongest(autoPool.filter(laneOK).filter(homeOK))
                    ?? strongest(autoPool.filter(laneOK))
            } else {
                picked = strongest(autoPool.filter(laneOK))
            }
        case .anyReady, .strongestReady:
            // Prefer same-driver only when preferred has a known home CLI.
            // Do not fall through to the full autoPool — that silently seats a
            // different-driver model. Cross-driver seating requires an explicit
            // ordered fallbackModelIds list (checked above).
            if homeDriver != nil {
                picked = strongest(autoPool.filter(homeOK))
            } else {
                picked = strongest(autoPool)
            }
        }
        guard let picked else { return nil }
        return wrap(picked, pickedViaPreferred: false)
    }

    /// Pick up to `count` ready models on **distinct CLI drivers** for triangulation.
    /// Preferred ids (ready + lane-capable) are taken first in order; remaining slots
    /// fill strongest-first (Law 3: "the shared resolver fills it from the ready
    /// bench, strongest-first within caliber") so flagship-tier models are recruited
    /// as workers when ready, never benched — the Lead's own model is reserved
    /// separately below. `reserveModelId` (the Lead's model) is dropped from the
    /// pool when alternatives exist. Returns distinct-driver models only — fewer
    /// than `count` when too few drivers are ready (the caller warns; never pads
    /// with duplicates).
    static func selectTriangle(
        count: Int,
        preferenceIds: [String],
        requiredTags: [ModelCapabilityTag],
        lane: WorkLane,
        ready: [Model],
        reserveModelId: String?,
        capabilities: (String) -> ModelCapabilities
    ) -> [Model] {
        func hasTags(_ m: Model) -> Bool {
            let tags = capabilities(m.id).capabilityTags
            return requiredTags.allSatisfy { tags.contains($0) }
        }
        func laneOK(_ m: Model) -> Bool { capabilities(m.id).laneTags.contains(lane) }

        var pool = ready.filter(laneOK).filter(hasTags)
            .filter { ModelCatalog.allowsAutomaticSubstitution($0.id) }
        // Reserve the Lead's model for the Lead — but only if alternatives remain
        // (a one-model bench must still produce a worker).
        if let r = reserveModelId, pool.contains(where: { $0.id != r }) {
            pool.removeAll { $0.id == r }
        }
        guard !pool.isEmpty else { return [] }

        // Ordered candidates: preferred ids first (in declared order), then the rest
        // cheapest-first (ascending strength rank, stable id tie-break).
        var ordered: [Model] = []
        var seen = Set<String>()
        for pid in preferenceIds {
            if let m = pool.first(where: { $0.id == pid }), seen.insert(m.id).inserted {
                ordered.append(m)
            }
        }
        let rest = pool.filter { !seen.contains($0.id) }.sorted { a, b in
            let ra = capabilities(a.id).strengthRank, rb = capabilities(b.id).strengthRank
            return ra != rb ? ra > rb : a.id < b.id
        }
        ordered.append(contentsOf: rest)

        // One model per distinct driver, in order, up to `count`.
        var chosen: [Model] = []
        var usedDrivers = Set<String>()
        for m in ordered where chosen.count < count {
            if usedDrivers.insert(m.driverId).inserted { chosen.append(m) }
        }
        return chosen
    }
}
