import Foundation

/// How the synthesizer turns the panel into a master plan. `combined` is one
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
    public var judgeWorkerId: String?
    /// Built-in `judge_analysis` instruction profile id.
    public var analysisProfileId: String
    /// Built-in `judge_plan` instruction profile id.
    public var planProfileId: String

    public init(
        analysisDepth: AnalysisDepth = .combined,
        judgeWorkerId: String? = nil,
        analysisProfileId: String,
        planProfileId: String
    ) {
        self.analysisDepth = analysisDepth
        self.judgeWorkerId = judgeWorkerId
        self.analysisProfileId = analysisProfileId
        self.planProfileId = planProfileId
    }
}

/// A saved, named panel configuration so the daily ritual is one click: which
/// seats answer (a worker may fill several — self-fusion), and how synthesis is
/// run. Each field is explicit (no hardcoded "Opus always synthesizes").
public struct PanelPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    /// Seat requests, expanded into `PanelSeat`s at run start.
    public var seats: [PanelSeatSpec]
    public var synthesis: SynthesisConfig
    /// True for the app-bundled defaults the user did not author.
    public var builtIn: Bool

    public init(
        id: String,
        displayName: String,
        seats: [PanelSeatSpec],
        synthesis: SynthesisConfig,
        builtIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.seats = seats
        self.synthesis = synthesis
        self.builtIn = builtIn
    }

    /// Distinct worker ids referenced by the seats, in first-seen order.
    public var workerIds: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for spec in seats where seen.insert(spec.workerId).inserted {
            ordered.append(spec.workerId)
        }
        return ordered
    }

    /// Builds the founder's six-worker default preset (one seat per worker).
    public static func builtInDefault(
        id: String = "preset_six_default",
        displayName: String = "Founder's Six",
        panel: [Worker],
        analysisProfileId: String,
        planProfileId: String,
        synthesizerWorkerId: String? = nil
    ) -> PanelPreset {
        let judge = synthesizerWorkerId ?? panel.first(where: \.canSynthesize)?.id ?? panel.first?.id
        return PanelPreset(
            id: id,
            displayName: displayName,
            seats: panel.map { PanelSeatSpec(workerId: $0.id) },
            synthesis: SynthesisConfig(
                analysisDepth: .combined,
                judgeWorkerId: judge,
                analysisProfileId: analysisProfileId,
                planProfileId: planProfileId
            ),
            builtIn: true
        )
    }
}
