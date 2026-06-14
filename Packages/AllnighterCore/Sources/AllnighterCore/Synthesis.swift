import Foundation

/// The synthesis step: one synthesizer worker (default Opus 4.8) reads the
/// original prompt + all labeled member answers and produces the master plan.
public struct Synthesis: Codable, Sendable, Equatable {
    public var synthesizerWorkerId: String
    /// Preset id (e.g. `default_master_plan_v1`) or inline instruction text.
    public var instructions: String
    public var masterPlanMarkdown: String?
    public var status: SynthesisStatus
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        synthesizerWorkerId: String,
        instructions: String,
        masterPlanMarkdown: String? = nil,
        status: SynthesisStatus = .pending,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.synthesizerWorkerId = synthesizerWorkerId
        self.instructions = instructions
        self.masterPlanMarkdown = masterPlanMarkdown
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
