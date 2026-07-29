import Foundation
import AllnighterCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Assembles a reduce/review stage's prompt from explicit `InputSelector`s over
/// the current run. Centralized so every post-panel stage composes inputs the
/// same way (and so `reuseKey` can hash exactly what a stage consumed).
public enum StageInputBuilder {
    public static func assemble(
        instructions: String,
        selectors: [InputSelector],
        run: TeamRun,
        models: [Model],
        extraReviews: [StageOutput] = []
    ) -> String {
        var sections: [String] = [instructions]
        for selector in selectors {
            switch selector {
            case .founderPrompt:
                sections.append("# Original prompt\n\n\(run.prompt)")
            case .answers:
                sections.append(SynthesisPromptBuilder.answersSection(run: run, models: models))
            case .planAnalysis:
                if let analysis = run.analysis, let json = encode(analysis) {
                    sections.append("# Plan analysis (structured)\n\n```json\n\(json)\n```")
                }
            case .draftPlan:
                if let plan = run.plan { sections.append("# Draft plan\n\n\(plan)") }
            case .reviews:
                let reviews = run.stages.filter { $0.purpose == .review && $0.status == .done }
                for r in reviews { if let md = r.payload?.markdown { sections.append("# Review: \(r.promptProfileId ?? r.id)\n\n\(md)") } }
                for r in extraReviews { if let md = r.payload?.markdown { sections.append("# Review: \(r.promptProfileId ?? r.id)\n\n\(md)") } }
            case .finalSpec:
                if let final = run.latestStage(.finalSpec), let md = final.payload?.markdown {
                    sections.append("# Final spec\n\n\(md)")
                }
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        (try? CoreJSON.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Content address for a stage output, so an unchanged stage is reused instead of
/// re-run (RB0 "reuse over re-run"). Hashes the profile + resolved input bytes +
/// worker/model, so editing one lens or re-running the finalizer doesn't re-run
/// the panel. An explicit "rerun" bypasses this (force-fresh).
public enum ReuseKey {
    public static func compute(
        promptProfileId: String?,
        customInstruction: String?,
        profileVersion: Int,
        resolvedInput: String,
        workerId: String,
        modelLabel: String
    ) -> String {
        let material = [
            promptProfileId ?? "",
            customInstruction ?? "",
            String(profileVersion),
            workerId,
            modelLabel,
            resolvedInput
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Runs one reduce/review stage: invoke a worker over an assembled prompt and
/// wrap the result into a `StageOutput`. The shared primitive RB2 (review fanout),
/// RB3 (final spec), and RB5 (return review) reuse.
public struct ReduceRunner: Sendable {
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

    /// Run a reduce that produces a Markdown payload (review / final spec / etc.).
    /// `makePayload` maps the raw worker output into the typed `StagePayload`.
    public func runMarkdown(
        purpose: StagePurpose,
        model: Model,
        manifest: DriverManifest,
        prompt: String,
        promptProfileId: String,
        reuseKey: String? = nil,
        makePayload: @Sendable (String) -> StagePayload
    ) async -> StageOutput {
        let started = now()
        let outcome = await workerRunner.collect(WorkerInvocation(model: model, manifest: manifest, prompt: prompt))
        let finished = now()
        if outcome.hasOutput, let out = outcome.output {
            return StageOutput(
                id: idFactory(), purpose: purpose, producedByAgentId: model.id,
                promptProfileId: promptProfileId, status: .done, payload: makePayload(out),
                reuseKey: reuseKey, startedAt: started, finishedAt: finished
            )
        }
        return StageOutput(
            id: idFactory(), purpose: purpose, producedByAgentId: model.id,
            promptProfileId: promptProfileId, status: outcome.status == .timedOut ? .timedOut : .failed,
            reuseKey: reuseKey, errorReason: outcome.errorReason ?? "no output",
            startedAt: started, finishedAt: finished
        )
    }
}
