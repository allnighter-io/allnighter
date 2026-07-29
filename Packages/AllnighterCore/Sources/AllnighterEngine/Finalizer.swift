import Foundation
import AllnighterCore

/// RB3: the first-principles finalizer. A reduce over the prompt + raw seat
/// answers + structured `PlanAnalysis` + draft plan + advisory reviews,
/// producing a decisive, executable `final_spec` with structured decisions
/// (adopt/partial/reject/defer; contradiction resolutions; insight rulings).
/// Runs even with zero reviews (`reviewBoardRan = false`). Reviews are advisory:
/// the finalizer never mutates the draft plan.
public struct Finalizer: Sendable {
    public static let decisionsDelimiter = "===DECISIONS==="

    private let workerRunner: any WorkerInvoking
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(
        workerRunner: any WorkerInvoking,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workerRunner = workerRunner
        self.idFactory = idFactory
        self.now = now
    }

    private struct Decisions: Decodable {
        var reviewDecisions: [ReviewDecision]?
        var contradictionDecisions: [ContradictionDecision]?
        var insightDecisions: [InsightDecision]?
    }

    public func finalize(
        run: TeamRun,
        finalizer: Model,
        manifest: DriverManifest,
        models: [Model],
        profile: PromptProfile,
        selectors: [InputSelector] = [.founderPrompt, .answers, .planAnalysis, .draftPlan, .reviews]
    ) async -> StageOutput {
        let reviewBoardRan = run.stages.contains { $0.purpose == .review && $0.status == .done }
        let prompt = StageInputBuilder.assemble(instructions: profile.template, selectors: selectors, run: run, models: models)
        let started = now()
        let outcome = await workerRunner.collect(WorkerInvocation(model: finalizer, manifest: manifest, prompt: prompt))
        let finished = now()

        guard outcome.hasOutput, let raw = outcome.output else {
            return StageOutput(
                id: idFactory(), purpose: .finalSpec, producedByAgentId: finalizer.id,
                promptProfileId: profile.id, status: outcome.status == .timedOut ? .timedOut : .failed,
                errorReason: outcome.errorReason ?? "no output", startedAt: started, finishedAt: finished
            )
        }

        let (specMarkdown, decisions, structured) = parse(raw)
        let payload = FinalSpecPayload(
            markdown: specMarkdown,
            reviewDecisions: decisions?.reviewDecisions ?? [],
            contradictionDecisions: decisions?.contradictionDecisions ?? [],
            insightDecisions: decisions?.insightDecisions ?? [],
            reviewBoardRan: reviewBoardRan,
            decisionsStructured: structured,
            hasProofCommands: detectProofCommands(specMarkdown)
        )
        return StageOutput(
            id: idFactory(), purpose: .finalSpec, producedByAgentId: finalizer.id,
            promptProfileId: profile.id, status: .done, payload: .finalSpec(payload),
            startedAt: started, finishedAt: finished
        )
    }

    private func parse(_ raw: String) -> (spec: String, decisions: Decisions?, structured: Bool) {
        guard let range = raw.range(of: Self.decisionsDelimiter) else {
            return (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil, false)
        }
        let spec = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(raw[range.upperBound...])
        guard let json = PlanOutputParser.extractJSONObject(from: tail),
              let decisions = try? CoreJSON.decode(Decisions.self, from: Data(json.utf8)) else {
            return (spec, nil, false)
        }
        let any = !(decisions.reviewDecisions ?? []).isEmpty
            || !(decisions.contradictionDecisions ?? []).isEmpty
            || !(decisions.insightDecisions ?? []).isEmpty
        return (spec, decisions, any)
    }

    /// "Proof commands present" = a fenced code block appears under a Works Test /
    /// proof heading.
    func detectProofCommands(_ spec: String) -> Bool {
        let lower = spec.lowercased()
        guard let headingRange = lower.range(of: "works test") ?? lower.range(of: "proof") else { return false }
        let after = spec[headingRange.upperBound...]
        return after.contains("```")
    }
}
