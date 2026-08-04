import Foundation
import AllnighterCore

/// In-memory edit state for one team. Pure of UI; `commit()` writes roster only.
/// Skill bodies commit separately via `WorkerSkillCommit` on Agent Done.
struct TeamDraft: Equatable {
    let base: TeamPreset
    var name: String
    var rows: [Row]
    var lead: Row
    var scout: Row?
    var allowSubstitutions: Bool
    var mutating: Bool

    /// One worker's roster row (skill + model). Skill catalog writes happen on Agent Done.
    struct Row: Identifiable, Equatable {
        let id: String
        var skillId: String
        var modelId: String?
        var purpose: TeamAgentPurpose
    }

    /// Seed from a base team. The name stays the base team's real name — selecting a
    /// built-in must NOT preemptively rename it to "(custom)"; that only happens at
    /// Save (see `commit()`). A row keeps its pinned model; an UNPINNED row stays nil
    /// = **Auto** (the resolver picks a ready model at run time) — we never coerce it
    /// to a concrete model the user didn't choose. Row ids mirror the spec ids so
    /// commit() can carry forward per-row facts (triangulation, count).
    init(base: TeamPreset) {
        self.base = base
        self.name = base.displayName
        self.allowSubstitutions = true
        self.mutating = base.mutating
        self.rows = base.agentSpecs.map { spec in
            Row(id: spec.id, skillId: spec.skillId, modelId: spec.preferredModelId, purpose: spec.purpose)
        }
        // The Team Lead. Its Row.purpose is unused (the Lead is the synthesizer,
        // not an answer/review worker); commit() writes a TeamLeadSpec.
        self.lead = Row(id: "lead", skillId: base.lead.skillId,
                        modelId: base.lead.preferredModelId, purpose: .answer)
        // Stage-0 scout (Signal): pinned model (Grok), shown above the workers.
        self.scout = base.scout.map { s in
            Row(id: s.id, skillId: s.skillId, modelId: s.preferredModelId, purpose: s.purpose)
        }
    }

    /// A role is complete when it has a skill id. nil model = Auto.
    static func rowComplete(_ r: Row) -> Bool {
        !r.skillId.isEmpty
    }

    /// Save is allowed only when every role — and the Lead — is complete.
    var isSavable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !rows.isEmpty &&
        (!mutating || rows.count == 1) &&
        rows.allSatisfy(Self.rowComplete) &&
        // A mutating team has no separate lead — the single agent is the source.
        (mutating || Self.rowComplete(lead))
    }

    /// Persist roster facts only (skill ids + model picks). Skill bodies are committed
    /// on Agent Done via `WorkerSkillCommit`, not here.
    @discardableResult
    func commit() throws -> TeamID {
        if mutating {
            let bench = Dictionary(ModelCatalog.list().map { ($0.id, $0.driverId) },
                                   uniquingKeysWith: { a, _ in a })
            let sources = Set(rows.compactMap { $0.modelId.flatMap { bench[$0] } })
            if sources.count > 1 {
                throw CatalogError.teamInvalid("Execution teams run on one CLI. Pick one source for all agents.")
            }
        }
        let fallback: ModelFallbackPolicy = allowSubstitutions ? .laneCapable : .exactOnly
        let saveName = name
        var duplicatedTeamId: TeamID?

        let effectiveRows = mutating ? Array(rows.prefix(1)) : rows
        let specs: [TeamAgentSpec] = try effectiveRows.map { row in
            guard !row.skillId.isEmpty else {
                throw CatalogError.teamInvalid("every agent needs a skill")
            }
            let original = base.agentSpecs.first { $0.id == row.id }
            return TeamAgentSpec(
                id: row.id, skillId: row.skillId,
                purpose: row.purpose, preferredModelId: row.modelId,
                fallbackModelIds: original?.fallbackModelIds,
                allowedModelIds: original?.allowedModelIds ?? [],
                requiredCapabilityTags: original?.requiredCapabilityTags ?? [],
                count: original?.count ?? 1, fallbackPolicy: fallback,
                required: original?.required ?? true,
                triangulate: original?.triangulate ?? false,
                triangulatePreferenceIds: original?.triangulatePreferenceIds ?? []
            )
        }
        let leadSpec: TeamLeadSpec
        if mutating, let only = specs.first {
            leadSpec = TeamLeadSpec(
                skillId: only.skillId,
                preferredModelId: only.preferredModelId,
                fallbackModelIds: only.fallbackModelIds,
                requiredCapabilityTags: only.requiredCapabilityTags,
                fallbackPolicy: fallback,
                dissentPolicy: base.lead.dissentPolicy
            )
        } else {
            guard !lead.skillId.isEmpty else {
                throw CatalogError.teamInvalid("the team lead needs a skill")
            }
            leadSpec = TeamLeadSpec(
                skillId: lead.skillId,
                preferredModelId: lead.modelId,
                fallbackModelIds: base.lead.fallbackModelIds,
                requiredCapabilityTags: base.lead.requiredCapabilityTags,
                fallbackPolicy: fallback,
                dissentPolicy: base.lead.dissentPolicy
            )
        }

        var team: TeamPreset
        if base.builtIn {
            team = base
        } else if let existing = TeamCatalog.get(base.id) {
            team = existing
        } else {
            let newId = TeamCatalog.freshCustomId(lane: base.lane, displayName: saveName)
            team = base.duplicated(newId: newId, newName: saveName)
            duplicatedTeamId = team.id
        }
        team.displayName = saveName
        team.agentSpecs = specs
        team.lead = leadSpec
        if let s = scout {
            let original = base.scout
            team.scout = TeamAgentSpec(
                id: s.id, skillId: s.skillId, purpose: .answer,
                preferredModelId: s.modelId,
                fallbackModelIds: original?.fallbackModelIds,
                allowedModelIds: original?.allowedModelIds ?? [],
                requiredCapabilityTags: original?.requiredCapabilityTags ?? [],
                count: original?.count ?? 1,
                fallbackPolicy: original?.fallbackPolicy ?? .laneCapable,
                required: original?.required ?? true,
                triangulate: original?.triangulate ?? false,
                triangulatePreferenceIds: original?.triangulatePreferenceIds ?? [])
        } else {
            team.scout = nil
        }
        team.mutating = mutating
        if mutating {
            team.executionSourceId = try Self.resolvedExecutionSourceId(from: specs, lead: leadSpec)
        } else {
            team.executionSourceId = nil
        }
        do {
            try TeamCatalog.validateExecutionSourceGate(team)
            try TeamCatalog.saveCustom(team)
            return team.id
        } catch {
            if let duplicatedTeamId { try? TeamCatalog.deleteCustom(duplicatedTeamId) }
            throw error
        }
    }

    private static func resolvedExecutionSourceId(from specs: [TeamAgentSpec], lead: TeamLeadSpec) throws -> String? {
        let bench = Dictionary(ModelCatalog.list().map { ($0.id, $0.driverId) }, uniquingKeysWith: { a, _ in a })
        var sources = Set<String>()
        for row in specs {
            if let mid = row.preferredModelId, let source = bench[mid] { sources.insert(source) }
        }
        if let mid = lead.preferredModelId, let source = bench[mid] { sources.insert(source) }
        guard sources.count <= 1 else { return nil }
        return sources.first
    }
}
