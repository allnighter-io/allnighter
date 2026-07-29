import Foundation

/// A versioned, editable prompt template used by a stage. Generalizes Phase 06's
/// judge instruction presets: a review lens, a synthesis instruction, and a
/// finalizer instruction are all prompt profiles distinguished by `purpose`.
public struct PromptProfile: Codable, Sendable, Equatable, Identifiable {
    public enum Purpose: String, Codable, Sendable, CaseIterable {
        case planAnalysis = "plan_analysis"
        case planWriter = "plan_writer"
        case reviewLens = "review_lens"
        case finalSpec = "final_spec"
    }
    public var id: String
    public var displayName: String
    public var purpose: Purpose
    public var profileVersion: Int
    public var template: String
    public var builtIn: Bool

    public init(id: String, displayName: String, purpose: Purpose, profileVersion: Int = 1, template: String, builtIn: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.purpose = purpose
        self.profileVersion = profileVersion
        self.template = template
        self.builtIn = builtIn
    }
}

/// What a stage consumes. A **closed** enum (no free-form graph).
public enum InputSelector: String, Codable, Sendable, CaseIterable {
    case founderPrompt = "founder_prompt"
    case workerAnswers = "worker_answers"
    case planAnalysis = "plan_analysis"
    case draftPlan = "draft_plan"
    case reviews
    case finalSpec = "final_spec"
}

/// Structured rule telling the final-spec stage how to treat reviews.
public struct FinalizerPolicy: Codable, Sendable, Equatable {
    public enum ReviewWeight: String, Codable, Sendable { case advisory }
    public enum ConflictResolution: String, Codable, Sendable { case firstPrinciples = "first_principles" }
    public var reviewWeight: ReviewWeight
    public var conflictResolution: ConflictResolution
    public var requiredSections: [String]

    public init(
        reviewWeight: ReviewWeight = .advisory,
        conflictResolution: ConflictResolution = .firstPrinciples,
        requiredSections: [String] = FinalizerPolicy.defaultSections
    ) {
        self.reviewWeight = reviewWeight
        self.conflictResolution = conflictResolution
        self.requiredSections = requiredSections
    }

    public static let defaultSections = [
        "Final Spec", "Scope", "Non-goals", "Architecture and state ownership",
        "UX / user-facing behavior, when relevant", "Acceptance criteria",
        "Works Test and proof wall", "Decisions on panel contradictions",
        "Decisions on unique insights", "Decisions on review feedback",
        "Risks and open questions"
    ]
}

/// A (profile -> worker) assignment for one stage, with its own timeout so a slow
/// lens can't kill the others. Reduces/reviews run a fresh worker invocation —
/// not a worker.
public struct StageBinding: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var promptProfileId: String
    public var workerId: String
    public var preferFastWorker: Bool
    public var timeoutSeconds: Int
    public var enabled: Bool
    public var finalizerPolicy: FinalizerPolicy?

    public init(
        id: String, promptProfileId: String, workerId: String,
        preferFastWorker: Bool = false, timeoutSeconds: Int = 180,
        enabled: Bool = true, finalizerPolicy: FinalizerPolicy? = nil
    ) {
        self.id = id
        self.promptProfileId = promptProfileId
        self.workerId = workerId
        self.preferFastWorker = preferFastWorker
        self.timeoutSeconds = timeoutSeconds
        self.enabled = enabled
        self.finalizerPolicy = finalizerPolicy
    }
}

/// One ordered fanout or reduce unit in the fixed v1 chain.
public struct WorkflowStage: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case fanout, reduce }
    public var id: String
    public var kind: Kind
    public var displayName: String
    public var purpose: StagePurpose
    public var inputSelectors: [InputSelector]
    public var bindings: [StageBinding]
    public var optional: Bool
    public var wallTimeoutSeconds: Int?

    public init(
        id: String, kind: Kind, displayName: String, purpose: StagePurpose,
        inputSelectors: [InputSelector], bindings: [StageBinding],
        optional: Bool = true, wallTimeoutSeconds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.purpose = purpose
        self.inputSelectors = inputSelectors
        self.bindings = bindings
        self.optional = optional
        self.wallTimeoutSeconds = wallTimeoutSeconds
    }
}

/// A named binding of workers, synthesis config, and the optional review/
/// final-spec stages. Extends `TeamPreset` (seats + synthesis) with `stages`.
/// The only valid v1 stage order:
/// panel_fanout -> analysis -> plan -> review_fanout? -> final_spec?
public struct WorkflowPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var description: String
    public var workerSpecs: [ModelSpec]
    public var synthesis: SynthesisConfig
    public var stages: [WorkflowStage]
    public var executionWorkerId: String?
    public var isDefault: Bool
    public var builtIn: Bool

    public init(
        id: String, displayName: String, description: String = "",
        workerSpecs: [ModelSpec], synthesis: SynthesisConfig,
        stages: [WorkflowStage] = [], executionWorkerId: String? = nil,
        isDefault: Bool = false, builtIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.workerSpecs = workerSpecs
        self.synthesis = synthesis
        self.stages = stages
        self.executionWorkerId = executionWorkerId
        self.isDefault = isDefault
        self.builtIn = builtIn
    }

    /// The panel preset embedded in this workflow (seats + synthesis).
    public var panelPreset: PanelPreset {
        PanelPreset(id: id, displayName: displayName, workerSpecs: workerSpecs, synthesis: synthesis, builtIn: builtIn)
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case reviewWithoutPlan
        case finalSpecWithoutPlan
        case unknownStageOrder(String)
        public var description: String {
            switch self {
            case .reviewWithoutPlan: return "a review stage requires the plan stage before it"
            case .finalSpecWithoutPlan: return "a final-spec stage requires the plan stage before it"
            case .unknownStageOrder(let s): return "invalid stage order: \(s)"
            }
        }
    }

    /// Validates the fixed v1 order. Panel + analysis + plan are implicit (driven
    /// by seats/synthesis); `stages` may add review(s) then at most one final_spec.
    public func validate() throws {
        var seenReview = false, seenFinal = false
        for stage in stages {
            switch stage.purpose {
            case .analysis, .plan, .board:
                throw ValidationError.unknownStageOrder("\(stage.purpose.rawValue) is not a configurable workflow stage")
            case .review:
                if seenFinal { throw ValidationError.unknownStageOrder("review after final spec") }
                seenReview = true
            case .finalSpec:
                if seenFinal { throw ValidationError.unknownStageOrder("multiple final-spec stages") }
                seenFinal = true
            }
        }
        _ = seenReview
    }
}
