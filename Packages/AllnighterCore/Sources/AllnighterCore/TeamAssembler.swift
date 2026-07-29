import Foundation

/// Assembles the Bench and default Team from the sources detection found `ready`
/// — the truth layer behind the future "Assemble your team" first-run flow
/// (docs/phases/setup/01 §8). Pure and headless: detection decides readiness,
/// this decides the lineup. Never infers readiness; only `ready` sources qualify.
public enum TeamAssembler {
    /// The assembled first-run team, persisted beside the detection cache.
    public struct Assembled: Codable, Sendable, Equatable {
        /// Models whose source is ready — the Bench.
        public var benchModelIds: [String]
        /// The default Team: one worker per ready model.
        public var workerSpecs: [ModelSpec]
        /// A truthful plan writer chosen from ready eligible models (nil if none).
        public var planWriterModelId: String?
        public var assembledAt: Date?

        public init(benchModelIds: [String] = [], workerSpecs: [ModelSpec] = [], planWriterModelId: String? = nil, assembledAt: Date? = nil) {
            self.benchModelIds = benchModelIds
            self.workerSpecs = workerSpecs
            self.planWriterModelId = planWriterModelId
            self.assembledAt = assembledAt
        }

        public var isEmpty: Bool { benchModelIds.isEmpty }
    }

    /// Assemble from the bench models and the set of driver ids whose source is
    /// `ready` (derive `readyDriverIds` from `ToolProbeRecord`s that `.isSmokeReady`).
    public static func assemble(models: [Model], readyDriverIds: Set<String>, now: Date) -> Assembled {
        let ready = models.filter { $0.enabled && readyDriverIds.contains($0.driverId) }
        // Plan writer: strongest eligible model (role planWriter/both) by catalog
        // strengthRank so Claude Opus 5 beats Antigravity Opus 4.6 even when the
        // array lists agy first. Fall back to the first ready model truthfully.
        let planWriter = strongestPlanWriter(in: ready) ?? ready.first
        return Assembled(
            benchModelIds: ready.map(\.id),
            workerSpecs: ready.map { ModelSpec(modelId: $0.id) },
            planWriterModelId: planWriter?.id,
            assembledAt: now
        )
    }

    /// Highest `strengthRank` among plan-writer-capable models; stable id tie-break.
    public static func strongestPlanWriter(in models: [Model]) -> Model? {
        models.filter(\.canWritePlan).sorted { a, b in
            let ra = ModelCatalog.capabilities(a.id).strengthRank
            let rb = ModelCatalog.capabilities(b.id).strengthRank
            return ra != rb ? ra > rb : a.id < b.id
        }.first
    }

    /// Convenience: derive ready driver ids from probe records.
    public static func readyDriverIds(from records: [ToolProbeRecord]) -> Set<String> {
        Set(records.filter { $0.status.isSmokeReady }.map(\.driverId))
    }
}
