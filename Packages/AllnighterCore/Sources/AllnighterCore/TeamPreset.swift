import Foundation

/// How the plan writer turns the panel into a plan. `combined` is one
/// judge call emitting structured analysis + plan; `separate` is two reduces
/// (analysis then plan) for more rigor. Either way the run carries both an
/// analysis and a plan `StageOutput` — call-count is the only difference.
public enum AnalysisDepth: String, Codable, Sendable, CaseIterable {
    case combined
    case separate
}

/// The synthesis configuration carried by a preset (and later `WorkflowPreset`).
public struct SynthesisConfig: Codable, Sendable, Equatable {
    public var analysisDepth: AnalysisDepth
    /// The worker that judges; nil = first enabled worker that can synthesize.
    public var planWriterModelId: String?
    /// Built-in `plan_analysis` instruction profile id.
    public var analysisProfileId: String
    /// Built-in `plan_writer` instruction profile id.
    public var planProfileId: String

    public init(
        analysisDepth: AnalysisDepth = .combined,
        planWriterModelId: String? = nil,
        analysisProfileId: String,
        planProfileId: String
    ) {
        self.analysisDepth = analysisDepth
        self.planWriterModelId = planWriterModelId
        self.analysisProfileId = analysisProfileId
        self.planProfileId = planProfileId
    }
}

/// A saved, named panel configuration so the daily ritual is one click: which
/// seats answer (a worker may fill several — self-fusion), and how synthesis is
/// run. Each field is explicit (no hardcoded "Opus always synthesizes").
public struct TeamPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// Worker requests, expanded into `Worker`s at run start.
    public var workerSpecs: [WorkerSpec]
    public var synthesis: SynthesisConfig
    /// True for the app-bundled defaults the user did not author.
    public var builtIn: Bool

    public init(
        id: String,
        displayName: String,
        workerSpecs: [WorkerSpec],
        synthesis: SynthesisConfig,
        builtIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.workerSpecs = workerSpecs
        self.synthesis = synthesis
        self.builtIn = builtIn
    }

    /// Distinct worker ids referenced by the seats, in first-seen order.
    public var workerIds: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for spec in workerSpecs where seen.insert(spec.modelId).inserted {
            ordered.append(spec.modelId)
        }
        return ordered
    }

    /// Builds the founder's six-worker default preset (one seat per worker).
    public static func builtInDefault(
        id: String = "preset_six_default",
        displayName: String = "Founder's Six",
        models: [Model],
        analysisProfileId: String,
        planProfileId: String,
        planWriterModelId: String? = nil
    ) -> TeamPreset {
        let planWriter = planWriterModelId ?? models.first(where: \.canWritePlan)?.id ?? models.first?.id
        return TeamPreset(
            id: id,
            displayName: displayName,
            workerSpecs: models.map { WorkerSpec(modelId: $0.id) },
            synthesis: SynthesisConfig(
                analysisDepth: .combined,
                planWriterModelId: planWriter,
                analysisProfileId: analysisProfileId,
                planProfileId: planProfileId
            ),
            builtIn: true
        )
    }
}
