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
    public var effort: EffortLevel
    public var answerWorkers: [Worker]
    public var reviewWorkers: [Worker]
    public var planWriter: Worker?
    public var disabledRows: [DisabledRow]
    public var warnings: [String]
    public var isRunnable: Bool
    public var blockReason: String?

    /// Answer + review + plan-writer, in execution order.
    public var allWorkers: [Worker] {
        answerWorkers + reviewWorkers + (planWriter.map { [$0] } ?? [])
    }

    public init(
        teamPresetId: String, teamDisplayName: String, lane: WorkLane,
        outputKind: TeamOutputKind, effort: EffortLevel,
        answerWorkers: [Worker] = [], reviewWorkers: [Worker] = [], planWriter: Worker? = nil,
        disabledRows: [DisabledRow] = [], warnings: [String] = [],
        isRunnable: Bool = false, blockReason: String? = nil
    ) {
        self.teamPresetId = teamPresetId; self.teamDisplayName = teamDisplayName
        self.lane = lane; self.outputKind = outputKind; self.effort = effort
        self.answerWorkers = answerWorkers; self.reviewWorkers = reviewWorkers
        self.planWriter = planWriter; self.disabledRows = disabledRows
        self.warnings = warnings; self.isRunnable = isRunnable; self.blockReason = blockReason
    }
}

/// Pure, deterministic team resolution: a lane team + effort + ready bench →
/// a concrete run snapshot (Fanout_Team_Catalog §Team Resolution). Never runs
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
            outputKind: team.outputKind, effort: effort
        )

        // Rule 1: lane must match (reject before running).
        guard team.lane == requestLane else {
            result.blockReason = "team \(team.id) is a \(team.lane.rawValue) team but the request lane is \(requestLane.rawValue)"
            return result
        }

        // Rules 3–4: activate rows by minEffort, split answer/review (declared order).
        let active = team.activeRows(at: effort)
        let answerRows = active.filter { $0.purpose == .answer }
        let reviewRows = active.filter { $0.purpose == .review }

        // instanceIndex is global per model across all stages so ids stay distinct
        // and self-fusion reads as `model#0, model#1, …`.
        var nextIndex: [String: Int] = [:]
        var warnings: [String] = []
        var disabled: [DisabledRow] = []
        var requiredBlock: String?

        func resolveRows(_ rows: [TeamWorkerSpec], stage: WorkerStage) -> [Worker] {
            var workers: [Worker] = []
            for row in rows {
                let chosen = selectModel(
                    preferredModelId: row.preferredModelId,
                    allowedModelIds: row.allowedModelIds,
                    requiredTags: row.requiredCapabilityTags,
                    fallback: row.fallbackPolicy,
                    lane: team.lane, ready: readyModels, capabilities: capabilities
                )
                let skillName = skill(row.skillId)?.displayName ?? row.skillId
                let skillVersion = skill(row.skillId)?.version ?? 1
                guard let model = chosen else {
                    let reason = "no ready model matches \(row.fallbackPolicy.rawValue)"
                        + (row.preferredModelId.map { " (preferred \($0) unavailable)" } ?? "")
                    disabled.append(DisabledRow(rowId: row.id, skillId: row.skillId, skillName: skillName, required: row.required, reason: reason))
                    if row.required {
                        requiredBlock = requiredBlock ?? "required worker \(skillName) could not resolve: \(reason)"
                    } else {
                        warnings.append("Optional worker \(skillName) disabled: \(reason).")
                    }
                    continue
                }
                if let preferred = row.preferredModelId, preferred != model.id {
                    warnings.append("\(skillName): preferred \(preferred) unavailable; resolved to \(model.displayName).")
                }
                for _ in 0..<max(1, row.count) {
                    let index = nextIndex[model.id, default: 0]
                    nextIndex[model.id] = index + 1
                    workers.append(Worker(
                        id: Worker.makeID(modelId: model.id, instanceIndex: index),
                        modelId: model.id, instanceIndex: index,
                        skillId: row.skillId, skillName: skillName, skillVersion: skillVersion,
                        purpose: stage
                    ))
                }
            }
            return workers
        }

        let answerWorkers = resolveRows(answerRows, stage: .answer)
        let reviewWorkers = resolveRows(reviewRows, stage: .review)

        // Rule 9: synthetic plan/output writer from synthesisPolicyByEffort.
        var planWriter: Worker?
        if let policy = team.synthesisPolicy(at: effort) {
            if let model = selectModel(
                preferredModelId: policy.modelPolicy.preferredModelId,
                allowedModelIds: [],
                requiredTags: policy.modelPolicy.requiredCapabilityTags,
                fallback: policy.modelPolicy.fallbackPolicy,
                lane: team.lane, ready: readyModels, capabilities: capabilities
            ) {
                let writerSkill = skill(policy.planWriterSkillId)
                let index = nextIndex[model.id, default: 0]
                nextIndex[model.id] = index + 1
                planWriter = Worker(
                    id: Worker.makeID(modelId: model.id, instanceIndex: index),
                    modelId: model.id, instanceIndex: index,
                    skillId: policy.planWriterSkillId,
                    skillName: writerSkill?.displayName ?? policy.planWriterSkillId,
                    skillVersion: writerSkill?.version ?? 1, purpose: .plan
                )
            }
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
}
