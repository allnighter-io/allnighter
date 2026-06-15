import Foundation
import AllnighterCore

/// Built-in judge instruction profiles. Phase 06 splits synthesis into two
/// reduces: `judge_analysis` produces the structured `JudgeAnalysis`; `judge_plan`
/// writes the master plan grounded in it. Editable/overridable by the user; the
/// canonical built-ins live in `SynthesisInstructionStore`.
public enum SynthesisInstructions {
    public static let analysisID = "judge_analysis_v1"
    public static let planID = "judge_plan_v1"

    /// Back-compat: callers that asked for "the default" get the plan profile id.
    public static let defaultID = planID

    /// Sentinel that separates the JSON analysis block from the plan in the
    /// `combined` judge output.
    public static let planDelimiter = "===PLAN==="

    public static let analysisText = """
    You are the council's judge. Below is one prompt and the independent answers \
    several seats (AI model runs) gave to it, each labeled with its seat id. \
    Analyze them. Output ONLY a single fenced ```json code block conforming exactly \
    to this schema (no prose before or after):

    {
      "consensus":      [{ "statement": "...", "sourceSeatIds": ["..."], "strength": "strong|moderate|weak" }],
      "contradictions": [{ "topic": "...", "positions": [{ "seatId": "...", "summary": "..." }], "recommendedResolution": "..." }],
      "partialCoverage":[{ "seatId": "...", "addressed": ["..."], "silentOn": ["..."] }],
      "uniqueInsights": [{ "statement": "...", "sourceSeatIds": ["..."], "strength": "strong|moderate|weak" }],
      "blindSpots":     ["angles NO seat addressed"],
      "failedSeats":    [{ "seatId": "...", "reason": "..." }],
      "confidenceNote": "optional calibration note"
    }

    Attribute every point to the seat ids that raised it. Do not average away \
    disagreement — record genuine contradictions and recommend a resolution.
    """

    public static let planText = """
    You are the council's writer. You are given the original prompt, the independent \
    seat answers, and the judge's structured analysis. Produce a single decisive \
    Master Plan in Markdown using EXACTLY these sections:

    ## Consensus
    ## Conflicts
    ## Unique insights
    ## Blind spots & gaps
    ## Risks & unknowns
    ## The Plan
    ## Open questions

    Ground every recommendation in the analysis and the source answers (attribute \
    when useful). Decide; do not average. Resolve each contradiction explicitly. \
    Output only the Master Plan in Markdown.
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

/// Splits a `combined` judge response into a `JudgeAnalysis` and the plan
/// Markdown. Tolerant + honest: each half is recovered independently so a good
/// plan is never lost because the analysis JSON failed (and vice-versa).
public enum JudgeOutputParser {
    public struct Result {
        public var analysis: JudgeAnalysis?
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
    public static func parseAnalysis(_ raw: String) -> (JudgeAnalysis?, String?) {
        decodeAnalysis(from: raw)
    }

    private static func decodeAnalysis(from text: String) -> (JudgeAnalysis?, String?) {
        guard let json = extractJSONObject(from: text) else {
            return (nil, "no JSON analysis block found")
        }
        do {
            let analysis = try CoreJSON.decode(JudgeAnalysis.self, from: Data(json.utf8))
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
        guard let start = text.firstIndex(of: "{") else { return nil }
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
                else if ch == "{" { depth += 1 }
                else if ch == "}" {
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

/// Assembles the prompts handed to the judge: seat answers labeled by seat id +
/// display name, an honest note about seats that did not answer, and (for the
/// plan reduce) the structured analysis.
public enum SynthesisPromptBuilder {
    public static func seatLabel(_ seat: PanelSeat, worker: Worker?, sharesWorker: Bool) -> String {
        let workerName = worker?.displayName ?? seat.workerId
        return "\(seat.displayName(workerName: workerName, sharesWorker: sharesWorker)) [seat \(seat.id)]"
    }

    private static func sharesWorker(_ seat: PanelSeat, in seats: [PanelSeat]) -> Bool {
        seats.filter { $0.workerId == seat.workerId }.count > 1
    }

    static func answersSection(run: CouncilRun, workers: [Worker]) -> String {
        let workerByID = Dictionary(workers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lines: [String] = ["# Independent answers from the panel"]
        for seat in run.panel {
            guard let member = run.member(seatId: seat.id), member.hasAnswer else { continue }
            let label = seatLabel(seat, worker: workerByID[seat.workerId], sharesWorker: sharesWorker(seat, in: run.panel))
            lines.append("## \(label)\n\n\(member.output ?? "")")
        }
        let missing = run.panel.compactMap { seat -> String? in
            guard let member = run.member(seatId: seat.id), !member.hasAnswer else { return nil }
            let label = seatLabel(seat, worker: workerByID[seat.workerId], sharesWorker: sharesWorker(seat, in: run.panel))
            return "- \(label): \(member.errorReason ?? member.status.rawValue)"
        }
        if !missing.isEmpty {
            lines.append("# Panel completeness\nThese seats did not return an answer; account for their absence:\n" + missing.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }

    public static func analysisPrompt(run: CouncilRun, workers: [Worker], instructions: String) -> String {
        [instructions, "# Original prompt", run.prompt, answersSection(run: run, workers: workers)]
            .joined(separator: "\n\n")
    }

    public static func planPrompt(run: CouncilRun, workers: [Worker], analysis: JudgeAnalysis, instructions: String) -> String {
        let analysisJSON = (try? CoreJSON.encode(analysis)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [
            instructions,
            "# Original prompt", run.prompt,
            "# Judge analysis (structured)", "```json\n\(analysisJSON)\n```",
            answersSection(run: run, workers: workers)
        ].joined(separator: "\n\n")
    }

    public static func combinedPrompt(run: CouncilRun, workers: [Worker], analysisInstructions: String, planInstructions: String) -> String {
        let combined = SynthesisInstructions.combinedInstructions(analysis: analysisInstructions, plan: planInstructions)
        return [combined, "# Original prompt", run.prompt, answersSection(run: run, workers: workers)]
            .joined(separator: "\n\n")
    }
}

/// Runs the synthesis reduces (analysis → plan) and returns the resulting stage
/// outputs. `combined` is one judge call split into two stages; `separate` is two
/// calls. Reuses `WorkerRunner` (the judge is a worker, not a panel seat).
public struct Synthesizer: Sendable {
    private let workerRunner: WorkerRunner
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(
        workerRunner: WorkerRunner,
        idFactory: @escaping @Sendable () -> String = { UUID().uuidString },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workerRunner = workerRunner
        self.idFactory = idFactory
        self.now = now
    }

    public func synthesize(
        run: CouncilRun,
        judge: Worker,
        manifest: DriverManifest,
        workers: [Worker],
        config: SynthesisConfig,
        analysisInstructions: String = SynthesisInstructions.analysisText,
        planInstructions: String = SynthesisInstructions.planText
    ) async -> [StageOutput] {
        switch config.analysisDepth {
        case .combined:
            return await synthesizeCombined(run: run, judge: judge, manifest: manifest, workers: workers, config: config, analysisInstructions: analysisInstructions, planInstructions: planInstructions)
        case .separate:
            return await synthesizeSeparate(run: run, judge: judge, manifest: manifest, workers: workers, config: config, analysisInstructions: analysisInstructions, planInstructions: planInstructions)
        }
    }

    private func synthesizeCombined(
        run: CouncilRun, judge: Worker, manifest: DriverManifest, workers: [Worker],
        config: SynthesisConfig, analysisInstructions: String, planInstructions: String
    ) async -> [StageOutput] {
        let prompt = SynthesisPromptBuilder.combinedPrompt(run: run, workers: workers, analysisInstructions: analysisInstructions, planInstructions: planInstructions)
        let startedAt = now()
        let outcome = await workerRunner.invoke(worker: judge, manifest: manifest, prompt: prompt)
        let finishedAt = now()

        guard outcome.hasOutput, let raw = outcome.output else {
            return [
                failedStage(.analysis, judge: judge, profileId: config.analysisProfileId, reason: outcome.errorReason ?? "judge produced no output", startedAt: startedAt, finishedAt: finishedAt),
                failedStage(.plan, judge: judge, profileId: config.planProfileId, reason: outcome.errorReason ?? "judge produced no output", startedAt: startedAt, finishedAt: finishedAt)
            ]
        }

        let parsed = JudgeOutputParser.parseCombined(raw)
        let analysisStage = analysisStage(from: parsed.analysis, error: parsed.analysisError, raw: raw, judge: judge, profileId: config.analysisProfileId, startedAt: startedAt, finishedAt: finishedAt)
        let planStage = planStage(markdown: parsed.planMarkdown, judge: judge, profileId: config.planProfileId, startedAt: startedAt, finishedAt: finishedAt)
        return [analysisStage, planStage]
    }

    private func synthesizeSeparate(
        run: CouncilRun, judge: Worker, manifest: DriverManifest, workers: [Worker],
        config: SynthesisConfig, analysisInstructions: String, planInstructions: String
    ) async -> [StageOutput] {
        // Stage 1: analysis.
        let aPrompt = SynthesisPromptBuilder.analysisPrompt(run: run, workers: workers, instructions: analysisInstructions)
        let aStart = now()
        let aOutcome = await workerRunner.invoke(worker: judge, manifest: manifest, prompt: aPrompt)
        let aFinish = now()
        let (analysis, analysisError): (JudgeAnalysis?, String?) = aOutcome.hasOutput
            ? JudgeOutputParser.parseAnalysis(aOutcome.output ?? "")
            : (nil, aOutcome.errorReason ?? "judge produced no output")
        let analysisStage = analysisStage(from: analysis, error: analysisError, raw: aOutcome.output ?? "", judge: judge, profileId: config.analysisProfileId, startedAt: aStart, finishedAt: aFinish)

        // Stage 2: plan, grounded in whatever analysis we have.
        let groundingAnalysis = analysis ?? JudgeAnalysis()
        let pPrompt = SynthesisPromptBuilder.planPrompt(run: run, workers: workers, analysis: groundingAnalysis, instructions: planInstructions)
        let pStart = now()
        let pOutcome = await workerRunner.invoke(worker: judge, manifest: manifest, prompt: pPrompt)
        let pFinish = now()
        let planStage = pOutcome.hasOutput
            ? planStage(markdown: pOutcome.output, judge: judge, profileId: config.planProfileId, startedAt: pStart, finishedAt: pFinish)
            : failedStage(.plan, judge: judge, profileId: config.planProfileId, reason: pOutcome.errorReason ?? "judge produced no output", startedAt: pStart, finishedAt: pFinish)
        return [analysisStage, planStage]
    }

    // MARK: - Stage builders

    private func analysisStage(from analysis: JudgeAnalysis?, error: String?, raw: String, judge: Worker, profileId: String, startedAt: Date, finishedAt: Date) -> StageOutput {
        if let analysis {
            return StageOutput(
                id: idFactory(), purpose: .analysis, producedByWorkerId: judge.id,
                promptProfileId: profileId, status: .done, payload: .analysis(analysis),
                startedAt: startedAt, finishedAt: finishedAt
            )
        }
        return StageOutput(
            id: idFactory(), purpose: .analysis, producedByWorkerId: judge.id,
            promptProfileId: profileId, status: .failed,
            errorReason: (error ?? "analysis parse failed") + " — raw: " + raw.prefix(2000),
            startedAt: startedAt, finishedAt: finishedAt
        )
    }

    private func planStage(markdown: String?, judge: Worker, profileId: String, startedAt: Date, finishedAt: Date) -> StageOutput {
        if let markdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return StageOutput(
                id: idFactory(), purpose: .plan, producedByWorkerId: judge.id,
                promptProfileId: profileId, status: .done, payload: .plan(markdown: markdown),
                startedAt: startedAt, finishedAt: finishedAt
            )
        }
        return failedStage(.plan, judge: judge, profileId: profileId, reason: "plan was empty or missing", startedAt: startedAt, finishedAt: finishedAt)
    }

    private func failedStage(_ purpose: StagePurpose, judge: Worker, profileId: String, reason: String, startedAt: Date, finishedAt: Date) -> StageOutput {
        StageOutput(
            id: idFactory(), purpose: purpose, producedByWorkerId: judge.id,
            promptProfileId: profileId, status: .failed, errorReason: reason,
            startedAt: startedAt, finishedAt: finishedAt
        )
    }
}
