import Foundation
import AllnighterCore

/// One resolved review-lens binding ready to run: the lens profile, the worker it
/// was routed to (budget routing happens before this), and its input selectors.
public struct ResolvedLens: Sendable {
    public let lensId: String
    public let profile: PromptProfile
    public let model: Model
    public let manifest: DriverManifest
    public let inputSelectors: [InputSelector]

    public init(lensId: String, profile: PromptProfile, model: Model, manifest: DriverManifest, inputSelectors: [InputSelector]) {
        self.lensId = lensId
        self.profile = profile
        self.model = model
        self.manifest = manifest
        self.inputSelectors = inputSelectors
    }
}

/// RB2: run advisory review lenses against a draft plan in parallel, each producing
/// a `.review` `StageOutput`. Advisory only — never mutates the plan. Partial by
/// design: a failed/timed-out lens does not block the others. Reuses
/// `ReduceRunner` + `StageInputBuilder` (the draft/analysis are reused inputs).
public struct ReviewCoordinator: Sendable {
    private let reduceRunner: ReduceRunner

    public init(reduceRunner: ReduceRunner) {
        self.reduceRunner = reduceRunner
    }

    /// Default input selectors for a lens. `dissent_preserver` also gets the raw
    /// seat answers so it can recover what the synthesis flattened.
    public static func defaultSelectors(forLens lensId: String) -> [InputSelector] {
        var selectors: [InputSelector] = [.founderPrompt, .planAnalysis, .draftPlan]
        if lensId == "dissent_preserver" || lensId == "coverage_audit" {
            selectors.append(.answers)
        }
        return selectors
    }

    public func review(run: TeamRun, models: [Model], lenses: [ResolvedLens]) async -> [StageOutput] {
        let runner = reduceRunner
        let results = await withTaskGroup(of: (Int, StageOutput).self) { group in
            for (index, lens) in lenses.enumerated() {
                group.addTask {
                    let prompt = StageInputBuilder.assemble(
                        instructions: lens.profile.template, selectors: lens.inputSelectors,
                        run: run, models: models
                    )
                    let stage = await runner.runMarkdown(
                        purpose: .review, model: lens.model, manifest: lens.manifest,
                        prompt: prompt, promptProfileId: lens.lensId
                    ) { .review(ReviewResult(lensId: lens.lensId, markdown: $0)) }
                    return (index, stage)
                }
            }
            var collected: [(Int, StageOutput)] = []
            for await item in group { collected.append(item) }
            return collected
        }
        // Preserve lens order (TaskGroup completion order is nondeterministic).
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
