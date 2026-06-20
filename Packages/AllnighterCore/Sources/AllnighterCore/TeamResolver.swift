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
    public var scoutWorker: Worker?
    public var answerWorkers: [Worker]
    public var reviewWorkers: [Worker]
    public var planWriter: Worker?
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
    public var allWorkers: [Worker] {
        (scoutWorker.map { [$0] } ?? []) + answerWorkers + reviewWorkers + (planWriter.map { [$0] } ?? [])
    }

    public init(
        teamPresetId: String, teamDisplayName: String, lane: WorkLane,
        outputKind: TeamOutputKind, mutating: Bool = false,
        effort: EffortLevel,
        scoutWorker: Worker? = nil,
        answerWorkers: [Worker] = [], reviewWorkers: [Worker] = [], planWriter: Worker? = nil,
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
        let active = team.workerSpecs
        let answerRows = active.filter { $0.purpose == .answer }
        let reviewRows = active.filter { $0.purpose == .review }

        // The Lead (synthesizer) resolves to the strongest ready model; reserve its
        // model so worker rows prefer cheaper models and the strongest is kept for
        // the Lead (cost policy: rarely spend the expensive model on a worker).
        let lead = team.lead
        let reservedLeadModelId = selectModel(
            preferredModelId: lead.preferredModelId, allowedModelIds: [],
            requiredTags: lead.requiredCapabilityTags, fallback: lead.fallbackPolicy,
            lane: team.lane, ready: readyModels, capabilities: capabilities
        )?.id

        // instanceIndex is global per model across all stages so ids stay distinct
        // and self-fusion reads as `model#0, model#1, …`.
        var nextIndex: [String: Int] = [:]
        var warnings: [String] = []
        var disabled: [DisabledRow] = []
        var requiredBlock: String?

        func makeWorker(_ model: Model, row: TeamWorkerSpec, skillName: String, stage: WorkerStage) -> Worker {
            let index = nextIndex[model.id, default: 0]
            nextIndex[model.id] = index + 1
            return Worker(
                id: Worker.makeID(modelId: model.id, instanceIndex: index),
                modelId: model.id, instanceIndex: index,
                skillId: row.skillId, skillName: skillName, purpose: stage)
        }

        func disable(_ row: TeamWorkerSpec, _ skillName: String, _ reason: String) {
            disabled.append(DisabledRow(rowId: row.id, skillId: row.skillId, skillName: skillName, required: row.required, reason: reason))
            if row.required {
                requiredBlock = requiredBlock ?? "required worker \(skillName) could not resolve: \(reason)"
            } else {
                warnings.append("Optional worker \(skillName) disabled: \(reason).")
            }
        }

        func resolveRows(_ rows: [TeamWorkerSpec], stage: WorkerStage) -> [Worker] {
            var workers: [Worker] = []
            for row in rows {
                let skillName = skill(row.skillId)?.displayName ?? row.skillId
                let want = max(1, row.count)

                // Triangulated row: spread `count` workers across distinct CLI drivers
                // so the signal is read by several different minds (never one).
                if row.triangulate {
                    let models = selectTriangle(
                        count: want, preferenceIds: row.triangulatePreferenceIds,
                        requiredTags: row.requiredCapabilityTags, lane: team.lane,
                        ready: readyModels, reserveModelId: reservedLeadModelId,
                        capabilities: capabilities)
                    guard !models.isEmpty else {
                        disable(row, skillName, "no ready model in lane \(team.lane.rawValue) for triangulation")
                        continue
                    }
                    if models.count < want {
                        warnings.append("\(skillName): triangulation degraded — \(models.count) distinct source(s) ready, wanted \(want).")
                    }
                    for model in models { workers.append(makeWorker(model, row: row, skillName: skillName, stage: stage)) }
                    continue
                }

                guard let model = selectModel(
                    preferredModelId: row.preferredModelId, allowedModelIds: row.allowedModelIds,
                    requiredTags: row.requiredCapabilityTags, fallback: row.fallbackPolicy,
                    lane: team.lane, ready: readyModels, capabilities: capabilities
                ) else {
                    let reason = "no ready model matches \(row.fallbackPolicy.rawValue)"
                        + (row.preferredModelId.map { " (preferred \($0) unavailable)" } ?? "")
                    disable(row, skillName, reason)
                    continue
                }
                if let preferred = row.preferredModelId, preferred != model.id {
                    warnings.append("\(skillName): preferred \(preferred) unavailable; resolved to \(model.displayName).")
                }
                for _ in 0..<want { workers.append(makeWorker(model, row: row, skillName: skillName, stage: stage)) }
            }
            return workers
        }

        let answerWorkers = resolveRows(answerRows, stage: .answer)
        let reviewWorkers = resolveRows(reviewRows, stage: .review)

        // Stage 0 scout (optional): distills the source for the crew. Resolved like a
        // single non-triangulate row; prefers its declared model (e.g. Grok for X).
        var scoutWorker: Worker?
        if let scoutSpec = team.scout {
            let scoutSkillName = skill(scoutSpec.skillId)?.displayName ?? scoutSpec.skillId
            if let model = selectModel(
                preferredModelId: scoutSpec.preferredModelId, allowedModelIds: scoutSpec.allowedModelIds,
                requiredTags: scoutSpec.requiredCapabilityTags, fallback: scoutSpec.fallbackPolicy,
                lane: team.lane, ready: readyModels, capabilities: capabilities
            ) {
                if let pref = scoutSpec.preferredModelId, pref != model.id {
                    warnings.append("\(scoutSkillName): preferred scout \(pref) unavailable; resolved to \(model.displayName).")
                }
                scoutWorker = makeWorker(model, row: scoutSpec, skillName: scoutSkillName, stage: .scout)
            } else {
                disable(scoutSpec, scoutSkillName, "no ready model for scout in lane \(team.lane.rawValue)")
            }
        }

        // Rule 9: the mandatory Team Lead (synthesizer) — exactly one worker, from
        // `team.lead` (effort-independent). Resolves its model by name like a row.
        result.dissentPolicy = lead.dissentPolicy
        var planWriter: Worker?
        if let model = selectModel(
            preferredModelId: lead.preferredModelId,
            allowedModelIds: [],
            requiredTags: lead.requiredCapabilityTags,
            fallback: lead.fallbackPolicy,
            lane: team.lane, ready: readyModels, capabilities: capabilities
        ) {
            let leadSkill = skill(lead.skillId)
            let index = nextIndex[model.id, default: 0]
            nextIndex[model.id] = index + 1
            planWriter = Worker(
                id: Worker.makeID(modelId: model.id, instanceIndex: index),
                modelId: model.id, instanceIndex: index,
                skillId: lead.skillId,
                skillName: leadSkill?.displayName ?? lead.skillId,
                purpose: .plan
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

    /// Choose a model for one row: try the preferred (if ready+allowed), else apply
    /// the fallback policy with capability/lane filtering, then strongest-by-rank
    /// with stable id tie-break.
    static func selectModel(
        preferredModelId: String?,
        allowedModelIds: [String],
        requiredTags: [ModelCapabilityTag],
        fallback: ModelFallbackPolicy,
        lane: WorkLane,
        ready: [Model],
        capabilities: (String) -> ModelCapabilities
    ) -> Model? {
        let byId = Dictionary(ready.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func allowed(_ m: Model) -> Bool { allowedModelIds.isEmpty || allowedModelIds.contains(m.id) }
        func hasTags(_ m: Model) -> Bool {
            let tags = capabilities(m.id).capabilityTags
            return requiredTags.allSatisfy { tags.contains($0) }
        }
        func laneOK(_ m: Model) -> Bool { capabilities(m.id).laneTags.contains(lane) }
        // Strongest by rank; ties break by stable (lexicographic) model id.
        func strongest(_ models: [Model]) -> Model? {
            models.sorted { a, b in
                let ra = capabilities(a.id).strengthRank, rb = capabilities(b.id).strengthRank
                return ra != rb ? ra > rb : a.id < b.id
            }.first
        }

        // Preferred wins outright when it is ready and allowed (explicit author pick).
        if let pref = preferredModelId, let m = byId[pref], allowed(m) { return m }

        let pool = ready.filter(allowed)
        switch fallback {
        case .exactOnly:
            // Only the explicitly allowed/preferred set; no capability broadening.
            return strongest(pool)
        case .sameSource:
            let source = preferredModelId.flatMap { byId[$0]?.driverId }
            let sameSource = pool.filter { $0.driverId == source }.filter(hasTags)
            return strongest(sameSource) ?? strongest(pool.filter(hasTags))
        case .laneCapable:
            return strongest(pool.filter(laneOK).filter(hasTags))
        case .anyReady, .strongestReady:
            return strongest(pool.filter(hasTags))
        }
    }

    /// Pick up to `count` ready models on **distinct CLI drivers** for triangulation.
    /// Preferred ids (ready + lane-capable) are taken first in order; remaining slots
    /// fill cheapest-first (lowest strength rank) so strong models are saved for the
    /// Lead. `reserveModelId` (the Lead's model) is dropped from the pool when
    /// alternatives exist. Returns distinct-driver models only — fewer than `count`
    /// when too few drivers are ready (the caller warns; never pads with duplicates).
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
            return ra != rb ? ra < rb : a.id < b.id
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
