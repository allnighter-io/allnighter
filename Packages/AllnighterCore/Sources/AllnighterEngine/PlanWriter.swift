import Foundation
import AllnighterCore

/// Built-in plan-writer instruction profiles. Phase 06 splits synthesis into two
/// reduces: `plan_analysis` produces the structured `PlanAnalysis`; `plan_writer`
/// writes the plan grounded in it. Editable/overridable by the user; the
/// canonical built-ins live in `SynthesisInstructionStore`.
public enum SynthesisInstructions {
    public static let analysisID = "plan_analysis_v1"
    public static let planID = "plan_writer_v1"

    /// Back-compat: callers that asked for "the default" get the plan profile id.
    public static let defaultID = planID

    /// Sentinel that separates the JSON analysis block from the plan in the
    /// `combined` plan-writer output.
    public static let planDelimiter = "===PLAN==="

    public static let analysisText = """
    You are the team's plan writer. Below is one prompt and the independent answers \
    several workers (AI model runs) gave to it, each labeled with its worker id. \
    Analyze them. Output ONLY a single fenced ```json code block conforming exactly \
    to this schema (no prose before or after):

    {
      "consensus":      [{ "statement": "...", "sourceAgentIds": ["..."], "strength": "strong|moderate|weak" }],
      "contradictions": [{ "topic": "...", "positions": [{ "workerId": "...", "summary": "..." }], "recommendedResolution": "..." }],
      "partialCoverage":[{ "agentId": "...", "addressed": ["..."], "silentOn": ["..."] }],
      "uniqueInsights": [{ "statement": "...", "sourceAgentIds": ["..."], "strength": "strong|moderate|weak" }],
      "blindSpots":     ["angles NO worker addressed"],
      "failedWorkers":    [{ "workerId": "...", "reason": "..." }],
      "confidenceNote": "optional calibration note"
    }

    Attribute every point to the worker ids that raised it. Do not average away \
    disagreement — record genuine contradictions and recommend a resolution.
    """

    public static let planText = """
    You are the team's plan writer. You are given the original prompt, the independent \
    worker answers, and the structured analysis. Produce a single decisive \
    Plan in Markdown using EXACTLY these sections:

    ## Consensus
    ## Conflicts
    ## Unique insights
    ## Blind spots & gaps
    ## Risks & unknowns
    ## The Plan
    ## Open questions

    Ground every recommendation in the analysis and the source answers (attribute \
    when useful). Decide; do not average. Resolve each contradiction explicitly. \
    Output only the Plan in Markdown.
    """

    /// The combined prompt prefix: emit the JSON analysis, then the delimiter,
    /// then the plan.
    public static func combinedInstructions(analysis: String, plan: String) -> String {
        """
        \(analysis)

        Then, on a new line, output the exact sentinel `\(planDelimiter)` followed by:

        \(plan)
        """
    }
}

/// Splits a `combined` planWriter response into a `PlanAnalysis` and the plan
/// Markdown. Tolerant + honest: each half is recovered independently so a good
/// plan is never lost because the analysis JSON failed (and vice-versa).
public enum PlanOutputParser {
    public struct Result {
        public var analysis: PlanAnalysis?
        public var analysisError: String?
        public var planMarkdown: String?
    }

    public static func parseCombined(_ raw: String) -> Result {
        let parts = split(raw, on: SynthesisInstructions.planDelimiter)
        let analysisChunk = parts.before
        let planChunk = parts.after

        var result = Result()

        // Analysis: prefer the chunk before the delimiter; fall back to whole text.
        let (analysis, analysisError) = decodeAnalysis(from: analysisChunk ?? raw)
        result.analysis = analysis
        result.analysisError = analysisError

        // Plan: the chunk after the delimiter; if absent, no plan.
        if let planChunk {
            let trimmed = planChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            result.planMarkdown = trimmed.isEmpty ? nil : trimmed
        }
        return result
    }

    /// Parse an analysis-only response (separate path).
    public static func parseAnalysis(_ raw: String) -> (PlanAnalysis?, String?) {
        decodeAnalysis(from: raw)
    }

    private static func decodeAnalysis(from text: String) -> (PlanAnalysis?, String?) {
        guard let json = extractJSONObject(from: text) else {
            return (nil, "no JSON analysis block found")
        }
        do {
            let analysis = try CoreJSON.decode(PlanAnalysis.self, from: Data(json.utf8))
            return (analysis, nil)
        } catch {
            return (nil, "analysis JSON did not match schema: \(error)")
        }
    }

    /// Extracts a JSON object: a ```json fenced block if present, else the first
    /// balanced `{ ... }` span.
    static func extractJSONObject(from text: String) -> String? {
        if let fenced = fencedBlock(in: text) { return fenced }
        return balancedObject(in: text)
    }

    /// Extracts a JSON array `[ ... ]` (fenced block first, else first balanced span).
    public static func extractJSONArray(from text: String) -> String? {
        let inner: String
        if let openRange = text.range(of: "```") {
            var rest = String(text[openRange.upperBound...])
            if rest.lowercased().hasPrefix("json") { rest = String(rest.dropFirst(4)) }
            if let close = rest.range(of: "```") { inner = String(rest[..<close.lowerBound]) } else { inner = text }
        } else {
            inner = text
        }
        return balancedSpan(in: inner, open: "[", close: "]")
    }

    private static func fencedBlock(in text: String) -> String? {
        // Look for ```json ... ``` (or ``` ... ```) containing an object.
        let scalars = Array(text)
        guard let openRange = text.range(of: "```") else { return nil }
        var rest = String(text[openRange.upperBound...])
        if rest.lowercased().hasPrefix("json") { rest = String(rest.dropFirst(4)) }
        guard let close = rest.range(of: "```") else { return nil }
        _ = scalars
        let inner = String(rest[..<close.lowerBound])
        return balancedObject(in: inner) ?? inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func balancedObject(in text: String) -> String? {
        balancedSpan(in: text, open: "{", close: "}")
    }

    /// First balanced `open…close` span, respecting JSON string escaping.
    static func balancedSpan(in text: String, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == open { depth += 1 }
                else if ch == close {
                    depth -= 1
                    if depth == 0 { return String(text[start...idx]) }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func split(_ text: String, on delimiter: String) -> (before: String?, after: String?) {
        guard let range = text.range(of: delimiter) else { return (nil, nil) }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }
}

/// Assembles prompts for the plan writer: worker answers labeled by worker id.
public enum SynthesisPromptBuilder {
    public static func workerLabel(_ assignment: Agent, model: Model?, sharesModel: Bool) -> String {
        let modelName = model?.displayName ?? assignment.modelId
        let workerTag = model.map { " [model \($0.id)]" } ?? ""
        return "\(assignment.displayName(modelName: modelName, sharesModel: sharesModel))\(workerTag)"
    }

    private static func sharesModel(_ assignment: Agent, in teamWorkers: [Agent]) -> Bool {
        teamWorkers.filter { $0.modelId == assignment.modelId }.count > 1
    }

    static func answersSection(run: TeamRun, models: [Model]) -> String {
        let modelByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        var lines: [String] = ["# Independent answers from the team"]
        for assignment in run.workers {
            guard let answer = run.workerAnswer(workerId: assignment.id), answer.hasAnswer else { continue }
            let label = workerLabel(assignment, model: modelByID[assignment.modelId], sharesModel: sharesModel(assignment, in: run.workers))
            lines.append("## \(label)\n\n\(answer.output ?? "")")
        }
        let missing = run.workers.compactMap { assignment -> String? in
            guard let answer = run.workerAnswer(workerId: assignment.id), !answer.hasAnswer else { return nil }
            let label = workerLabel(assignment, model: modelByID[assignment.modelId], sharesModel: sharesModel(assignment, in: run.workers))
            return "- \(label): \(answer.result.errorReason ?? answer.result.status.rawValue)"
        }
        if !missing.isEmpty {
            lines.append("# Team completeness\nThese workers did not return an answer; account for their absence:\n" + missing.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }

    public static func analysisPrompt(run: TeamRun, models: [Model], instructions: String) -> String {
        [instructions, "# Original prompt", run.prompt, answersSection(run: run, models: models)]
            .joined(separator: "\n\n")
    }

    public static func planPrompt(run: TeamRun, models: [Model], analysis: PlanAnalysis, instructions: String) -> String {
        let analysisJSON = (try? CoreJSON.encode(analysis)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [
            instructions,
            "# Original prompt", run.prompt,
            "# Plan analysis (structured)", "```json\n\(analysisJSON)\n```",
            answersSection(run: run, models: models)
        ].joined(separator: "\n\n")
    }

    public static func combinedPrompt(run: TeamRun, models: [Model], analysisInstructions: String, planInstructions: String) -> String {
        let combined = SynthesisInstructions.combinedInstructions(analysis: analysisInstructions, plan: planInstructions)
        return [combined, "# Original prompt", run.prompt, answersSection(run: run, models: models)]
            .joined(separator: "\n\n")
    }
}

/// Runs the synthesis reduces (analysis → plan) and returns the resulting stage
/// outputs. `combined` is one plan-writer call split into two stages; `separate`
/// is two calls. Reuses the composed `WorkerInvoking` stack — the plan writer is
/// itself a worker.
public struct PlanWriter: Sendable {
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

    public func synthesize(
        run: TeamRun,
        planWriter: Model,
        manifest: DriverManifest,
        models: [Model],
        config: SynthesisConfig,
        analysisInstructions: String = SynthesisInstructions.analysisText,
        planInstructions: String = SynthesisInstructions.planText
    ) async -> [StageOutput] {
        switch config.analysisDepth {
        case .combined:
            return await synthesizeCombined(run: run, planWriter: planWriter, manifest: manifest, models: models, config: config, analysisInstructions: analysisInstructions, planInstructions: planInstructions)
        case .separate:
            return await synthesizeSeparate(run: run, planWriter: planWriter, manifest: manifest, models: models, config: config, analysisInstructions: analysisInstructions, planInstructions: planInstructions)
        }
    }

    private func synthesizeCombined(
        run: TeamRun, planWriter: Model, manifest: DriverManifest, models: [Model],
        config: SynthesisConfig, analysisInstructions: String, planInstructions: String
    ) async -> [StageOutput] {
        let prompt = SynthesisPromptBuilder.combinedPrompt(run: run, models: models, analysisInstructions: analysisInstructions, planInstructions: planInstructions)
        let startedAt = now()
        let outcome = await workerRunner.collect(WorkerInvocation(model: planWriter, manifest: manifest, prompt: prompt))
        let finishedAt = now()

        guard outcome.hasOutput, let raw = outcome.output else {
            return [
                failedStage(.analysis, planWriter: planWriter, profileId: config.analysisProfileId, reason: outcome.errorReason ?? "plan writer produced no output", startedAt: startedAt, finishedAt: finishedAt),
                failedStage(.plan, planWriter: planWriter, profileId: config.planProfileId, reason: outcome.errorReason ?? "plan writer produced no output", startedAt: startedAt, finishedAt: finishedAt)
            ]
        }

        let parsed = PlanOutputParser.parseCombined(raw)
        let analysisStage = analysisStage(from: parsed.analysis, error: parsed.analysisError, raw: raw, planWriter: planWriter, profileId: config.analysisProfileId, startedAt: startedAt, finishedAt: finishedAt)
        let planStage = planStage(markdown: parsed.planMarkdown, planWriter: planWriter, profileId: config.planProfileId, startedAt: startedAt, finishedAt: finishedAt)
        return [analysisStage, planStage]
    }

    private func synthesizeSeparate(
        run: TeamRun, planWriter: Model, manifest: DriverManifest, models: [Model],
        config: SynthesisConfig, analysisInstructions: String, planInstructions: String
    ) async -> [StageOutput] {
        // Stage 1: analysis.
        let aPrompt = SynthesisPromptBuilder.analysisPrompt(run: run, models: models, instructions: analysisInstructions)
        let aStart = now()
        let aOutcome = await workerRunner.collect(WorkerInvocation(model: planWriter, manifest: manifest, prompt: aPrompt))
        let aFinish = now()
        let (analysis, analysisError): (PlanAnalysis?, String?) = aOutcome.hasOutput
            ? PlanOutputParser.parseAnalysis(aOutcome.output ?? "")
            : (nil, aOutcome.errorReason ?? "plan writer produced no output")
        let analysisStage = analysisStage(from: analysis, error: analysisError, raw: aOutcome.output ?? "", planWriter: planWriter, profileId: config.analysisProfileId, startedAt: aStart, finishedAt: aFinish)

        // Stage 2: plan, grounded in whatever analysis we have.
        let groundingAnalysis = analysis ?? PlanAnalysis()
        let pPrompt = SynthesisPromptBuilder.planPrompt(run: run, models: models, analysis: groundingAnalysis, instructions: planInstructions)
        let pStart = now()
        let pOutcome = await workerRunner.collect(WorkerInvocation(model: planWriter, manifest: manifest, prompt: pPrompt))
        let pFinish = now()
        let planStage = pOutcome.hasOutput
            ? planStage(markdown: pOutcome.output, planWriter: planWriter, profileId: config.planProfileId, startedAt: pStart, finishedAt: pFinish)
            : failedStage(.plan, planWriter: planWriter, profileId: config.planProfileId, reason: pOutcome.errorReason ?? "plan writer produced no output", startedAt: pStart, finishedAt: pFinish)
        return [analysisStage, planStage]
    }

    // MARK: - Stage builders

    private func analysisStage(from analysis: PlanAnalysis?, error: String?, raw: String, planWriter: Model, profileId: String, startedAt: Date, finishedAt: Date) -> StageOutput {
        if let analysis {
            return StageOutput(
                id: idFactory(), purpose: .analysis, producedByAgentId: planWriter.id,
                promptProfileId: profileId, status: .done, payload: .analysis(analysis),
                startedAt: startedAt, finishedAt: finishedAt
            )
        }
        return StageOutput(
            id: idFactory(), purpose: .analysis, producedByAgentId: planWriter.id,
            promptProfileId: profileId, status: .failed,
            errorReason: (error ?? "analysis parse failed") + " — raw: " + raw.prefix(2000),
            startedAt: startedAt, finishedAt: finishedAt
        )
    }

    private func planStage(markdown: String?, planWriter: Model, profileId: String, startedAt: Date, finishedAt: Date) -> StageOutput {
        if let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return StageOutput(
                id: idFactory(), purpose: .plan, producedByAgentId: planWriter.id,
                promptProfileId: profileId, status: .done, payload: .plan(markdown: markdown),
                startedAt: startedAt, finishedAt: finishedAt
            )
        }
        return failedStage(.plan, planWriter: planWriter, profileId: profileId, reason: "plan was empty or missing", startedAt: startedAt, finishedAt: finishedAt)
    }

    private func failedStage(_ purpose: StagePurpose, planWriter: Model, profileId: String, reason: String, startedAt: Date, finishedAt: Date) -> StageOutput {
        StageOutput(
            id: idFactory(), purpose: purpose, producedByAgentId: planWriter.id,
            promptProfileId: profileId, status: .failed, errorReason: reason,
            startedAt: startedAt, finishedAt: finishedAt
        )
    }
}
