import Foundation

/// The handoff artifact created before direct executor dispatch (RB4). Carries
/// everything the executing agent needs to start and to know when it is done —
/// plus the structured analysis decisions, so the executor inherits the
/// pressure-testing context instead of re-litigating it. Forward-compatible with
/// managed lane execution (Phase 12) without changing its core shape.
public struct ImplementationBrief: Codable, Sendable, Equatable {
    /// `designImage` (Design2) carries a chosen design image — the executor restyles
    /// the existing code to match it (our ICP redesigns; it is not build-from-scratch).
    public enum SourceArtifact: String, Codable, Sendable {
        case finalSpec = "final_spec", masterPlan = "master_plan", designImage = "design_image"
    }

    public var sourceRunId: String
    public var sourceArtifact: SourceArtifact
    public var executionWorkerId: String
    public var workingDirectory: String
    public var prompt: String
    /// The final spec or master plan Markdown (the design intent for a design build).
    public var spec: String
    /// Consensus + resolved contradictions from the judge analysis.
    public var judgmentSummary: String
    /// Structured decisions, present only when built from a final spec.
    public var decisions: FinalSpecPayload?
    /// Absolute path to the chosen design image the agent should match (Design2).
    public var designImagePath: String?
    /// Absolute path to the original "before" screenshot, when redesigning (Design2).
    public var beforeScreenshotPath: String?
    public var boundaryLabel: String

    public init(
        sourceRunId: String,
        sourceArtifact: SourceArtifact,
        executionWorkerId: String,
        workingDirectory: String,
        prompt: String,
        spec: String,
        judgmentSummary: String,
        decisions: FinalSpecPayload? = nil,
        designImagePath: String? = nil,
        beforeScreenshotPath: String? = nil,
        boundaryLabel: String = ImplementationBrief.defaultBoundary
    ) {
        self.sourceRunId = sourceRunId
        self.sourceArtifact = sourceArtifact
        self.executionWorkerId = executionWorkerId
        self.workingDirectory = workingDirectory
        self.prompt = prompt
        self.spec = spec
        self.judgmentSummary = judgmentSummary
        self.decisions = decisions
        self.designImagePath = designImagePath
        self.beforeScreenshotPath = beforeScreenshotPath
        self.boundaryLabel = boundaryLabel
    }

    /// True when built from a master plan (no final spec) — less reviewed.
    public var isLessReviewed: Bool { sourceArtifact == .masterPlan }

    /// True when this brief hands a chosen design image to a coding agent (Design2).
    public var isDesignBuild: Bool { sourceArtifact == .designImage }

    public static let defaultBoundary = """
    Direct dispatch will run the selected worker in the chosen working directory. \
    Allnighter is not creating a worktree or managing commits. File edits and git \
    behavior are controlled by the selected CLI and this prompt.
    """
}
