import Foundation
import AllnighterCore

/// Extracts the acceptance-criteria bullets from a final spec's Markdown (the
/// "## Acceptance criteria" section), for RB5 outcome scoring.
public enum AcceptanceCriteria {
    public static func extract(from spec: String) -> [String] {
        let lines = spec.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inSection = false
        var items: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                inSection = trimmed.lowercased().contains("acceptance criteria")
                continue
            }
            guard inSection else { continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                items.append(String(trimmed.dropFirst(2)))
            }
        }
        return items
    }
}

/// RB5: advisory evaluation of an execution return against the final spec.
/// Proof execution is OFF by default (the review reads the transcript; the app
/// reveals proof commands for the user to run). Produces a `.returnReview`
/// `StageOutput` with a routing recommendation.
public struct ReturnReviewer: Sendable {
    private let workerRunner: WorkerRunner
    private let idFactory: @Sendable () -> String
    private let now: @Sendable () -> Date

    public init(workerRunner: WorkerRunner, idFactory: @escaping @Sendable () -> String = { UUID().uuidString }, now: @escaping @Sendable () -> Date = Date.init) {
        self.workerRunner = workerRunner
        self.idFactory = idFactory
        self.now = now
    }

    private struct Parsed: Decodable { var action: String?; var reasoning: String? }

    public func review(
        run: CouncilRun,
        executionReturn: ExecutionReturn,
        reviewer: Worker,
        manifest: DriverManifest,
        profile: PromptProfile
    ) async -> StageOutput {
        let spec = run.latestStage(.finalSpec)?.payload?.markdown ?? run.masterPlan ?? ""
        let prompt = """
        \(profile.template)

        # Spec
        \(spec)

        # Executor return (worker \(executionReturn.executionWorkerId), status \(executionReturn.status.rawValue))
        \(executionReturn.transcriptExcerpt ?? "(no transcript)")

        Evaluate: did the result meet each acceptance criterion? Which proof commands \
        should be run? What is missing or wrong? Then output the exact sentinel \
        ===ROUTING=== on its own line followed by a fenced ```json block:
        { "action": "rerun|remix|pick", "reasoning": "..." }
        """
        let started = now()
        let outcome = await workerRunner.invoke(worker: reviewer, manifest: manifest, prompt: prompt)
        let finished = now()
        guard outcome.hasOutput, let raw = outcome.output else {
            return StageOutput(id: idFactory(), purpose: .returnReview, producedByWorkerId: reviewer.id,
                               promptProfileId: profile.id, status: outcome.status == .timedOut ? .timedOut : .failed,
                               errorReason: outcome.errorReason ?? "no output", startedAt: started, finishedAt: finished)
        }
        let (markdown, rec) = parse(raw, fallbackFailed: executionReturn.status != .done)
        return StageOutput(id: idFactory(), purpose: .returnReview, producedByWorkerId: reviewer.id,
                           promptProfileId: profile.id, status: .done,
                           payload: .returnReview(ReturnReviewPayload(markdown: markdown, recommendation: rec)),
                           startedAt: started, finishedAt: finished)
    }

    private func parse(_ raw: String, fallbackFailed: Bool) -> (String, RoutingRecommendation?) {
        let delimiter = "===ROUTING==="
        guard let range = raw.range(of: delimiter) else {
            return (raw.trimmingCharacters(in: .whitespacesAndNewlines),
                    fallbackFailed ? RoutingRecommendation(action: .rerun, reasoning: "Execution did not complete cleanly.") : nil)
        }
        let body = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(raw[range.upperBound...])
        guard let json = JudgeOutputParser.extractJSONObject(from: tail),
              let parsed = try? CoreJSON.decode(Parsed.self, from: Data(json.utf8)),
              let actionRaw = parsed.action, let action = RoutingAction(rawValue: actionRaw) else {
            return (body, fallbackFailed ? RoutingRecommendation(action: .rerun, reasoning: "Execution did not complete cleanly.") : nil)
        }
        return (body, RoutingRecommendation(action: action, reasoning: parsed.reasoning ?? ""))
    }
}

/// RB5: aggregates per-worker performance over local run history. On-demand; no
/// upload, no persisted snapshot.
public enum ScorecardBuilder {
    public static func build(from runs: [CouncilRun]) -> [WorkerScorecard] {
        struct Acc { var runs = Set<String>(); var answered = 0; var seated = 0; var judged = 0; var judgeUsable = 0; var dispatched = 0; var dispatchOK = 0; var latencies: [Int] = [] }
        var acc: [String: Acc] = [:]

        for run in runs {
            for member in run.members {
                acc[member.workerId, default: Acc()].runs.insert(run.id)
                acc[member.workerId, default: Acc()].seated += 1
                if member.hasAnswer { acc[member.workerId, default: Acc()].answered += 1 }
                if let ms = member.durationMs { acc[member.workerId, default: Acc()].latencies.append(ms) }
            }
            for stage in run.stages where stage.purpose == .plan {
                if let w = stage.producedByWorkerId {
                    acc[w, default: Acc()].judged += 1
                    if stage.status == .done { acc[w, default: Acc()].judgeUsable += 1 }
                }
            }
            for stage in run.stages where stage.purpose == .dispatch {
                if let ret = stage.payload?.executionReturn {
                    acc[ret.executionWorkerId, default: Acc()].dispatched += 1
                    if ret.status == .done { acc[ret.executionWorkerId, default: Acc()].dispatchOK += 1 }
                }
            }
        }

        return acc.map { (workerId, a) in
            func rate(_ n: Int, _ d: Int) -> Double { d == 0 ? 0 : Double(n) / Double(d) }
            let median: Int? = a.latencies.isEmpty ? nil : a.latencies.sorted()[a.latencies.count / 2]
            return WorkerScorecard(
                workerId: workerId, sampleSize: a.runs.count,
                panelAnswerRate: rate(a.answered, a.seated),
                judgeSuccessRate: rate(a.judgeUsable, a.judged),
                executionSuccessRate: rate(a.dispatchOK, a.dispatched),
                medianLatencyMs: median
            )
        }.sorted { $0.workerId < $1.workerId }
    }
}
