import Foundation

/// The stage a resolved worker runs in. The optional `scout` runs FIRST and
/// distills the raw source (e.g. an X-capable model grabbing a post) into context
/// the rest of the team reads. Answer workers then run blind in parallel; review
/// workers run after answers and may see them; `plan` is the synthetic plan/output
/// writer that runs last. (Catalog answer/review rows map to `answer`/`review`; the
/// scout is a separate `TeamPreset.scout` spec; `plan` is only the synthetic writer.)
public enum WorkerStage: String, Codable, Sendable, CaseIterable {
    case scout
    case answer
    case review
    case plan
}

/// One runtime worker assignment: a model wearing a skill for this team run.
/// The same model may appear multiple times with different skills or instance
/// indices (self-fusion).
public struct Worker: Codable, Sendable, Equatable, Identifiable {
    /// Stable worker id, e.g. `model_opus#0`, `model_opus#1`.
    public var id: String
    /// Bench model that runs this worker.
    public var modelId: String
    /// 0-based index among workers sharing a `modelId`.
    public var instanceIndex: Int
    /// Optional skill id. Drives a prompt prefix.
    public var skillId: String?
    /// Snapshot of the resolved skill's display name at run start, so history
    /// stays readable after a skill update (catalog runs set this).
    public var skillName: String?
    /// Exact prompt payload assembled for this worker (skill template + context).
    /// Populated on catalog runs; omitted from the default public TeamRunJSON.
    public var resolvedWorkerPromptSnapshot: String?
    /// Stage this worker runs in: answer (blind), review (after answers), or plan
    /// (the synthetic output writer). `nil` on legacy runs → treated as answer.
    public var purpose: WorkerStage?
    /// Display override, e.g. `Opus (A)`.
    public var label: String?
    /// The model the team row ASKED for, when the resolver substituted a different ready
    /// model for it (preferred unavailable + lane-capable fallback). `nil` when the worker
    /// runs its preferred model. Lets the UI say "substituted from X" instead of silently
    /// showing a different model than the team was configured with.
    public var substitutedFromModelId: String?
    /// SEAT-S3 — why the resolver seated this model (dry-run + audit). Optional so
    /// legacy runs and non-catalog paths decode unchanged.
    public var seatingReason: String?

    public init(
        id: String,
        modelId: String,
        instanceIndex: Int,
        skillId: String? = nil,
        skillName: String? = nil,
        resolvedWorkerPromptSnapshot: String? = nil,
        purpose: WorkerStage? = nil,
        label: String? = nil,
        substitutedFromModelId: String? = nil,
        seatingReason: String? = nil
    ) {
        self.id = id
        self.modelId = modelId
        self.instanceIndex = instanceIndex
        self.skillId = skillId
        self.skillName = skillName
        self.resolvedWorkerPromptSnapshot = resolvedWorkerPromptSnapshot
        self.purpose = purpose
        self.label = label
        self.substitutedFromModelId = substitutedFromModelId
        self.seatingReason = seatingReason
    }

    /// Canonical worker id for a model + instance index.
    public static func makeID(modelId: String, instanceIndex: Int) -> String {
        "\(modelId)#\(instanceIndex)"
    }

    /// Display name: explicit label, else model name + A/B/C when duplicated.
    public func displayName(modelName: String, sharesModel: Bool) -> String {
        if let label { return label }
        guard sharesModel else { return modelName }
        let suffix = String(UnicodeScalar(65 + (instanceIndex % 26))!)
        return "\(modelName) (\(suffix))"
    }
}

/// A preset's request for workers. Expanded into concrete `Worker`s at run start.
public struct WorkerSpec: Codable, Sendable, Equatable {
    public var modelId: String
    public var count: Int
    public var skillId: String?

    public init(modelId: String, count: Int = 1, skillId: String? = nil) {
        self.modelId = modelId
        self.count = count
        self.skillId = skillId
    }

    public func expand(startingIndex start: Int) -> [Worker] {
        (0..<max(1, count)).map { offset in
            let index = start + offset
            return Worker(
                id: Worker.makeID(modelId: modelId, instanceIndex: index),
                modelId: modelId,
                instanceIndex: index,
                skillId: skillId
            )
        }
    }
}

public extension Array where Element == WorkerSpec {
    func expandedWorkers() -> [Worker] {
        var nextIndex: [String: Int] = [:]
        var workers: [Worker] = []
        for spec in self {
            let start = nextIndex[spec.modelId, default: 0]
            let expanded = spec.expand(startingIndex: start)
            workers.append(contentsOf: expanded)
            nextIndex[spec.modelId] = start + expanded.count
        }
        return workers
    }
}
