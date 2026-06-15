import Foundation
import AllnighterCore

/// Offline discipline gate: scores an artifact (a master plan / final spec) against
/// a hidden weighted rubric using a judge worker, and compares modes
/// (solo / combined / separate / review_board) so a synthesis change is **proven**
/// before it becomes a default. A dev/founder tool — never auto-grades a user run.
///
/// Contamination guard is structural: the eval corpus is loaded from a dedicated
/// path (`EvalCorpus`) that the panel/reduce prompt builders never read, and eval
/// runs are written outside `Runs/` (see `AllnighterPaths.evals`).
public struct EvalHarness: Sendable {
    private let workerRunner: WorkerRunner

    public init(workerRunner: WorkerRunner) {
        self.workerRunner = workerRunner
    }

    /// Score `artifact` against `evalCase.rubric`, averaging `config.passes` judge
    /// passes. The judge sees the rubric + artifact (NOT the corpus file).
    public func score(
        artifact: String,
        mode: String,
        evalCase: EvalCase,
        judge: Worker,
        manifest: DriverManifest,
        config: EvalConfig
    ) async -> EvalScore {
        var passTotals: [String: [Double]] = [:]
        for _ in 0..<config.passes {
            let prompt = scoringPrompt(rubric: evalCase.rubric, artifact: artifact)
            let outcome = await workerRunner.invoke(worker: judge, manifest: manifest, prompt: prompt)
            guard outcome.hasOutput, let raw = outcome.output, let scores = parseScores(raw) else { continue }
            for s in scores { passTotals[s.criterionId, default: []].append(s.score) }
        }
        // Average each criterion across passes; missing => 0.
        let perCriterion = evalCase.rubric.criteria.map { crit -> EvalScore.CriterionScore in
            let samples = passTotals[crit.id] ?? []
            let avg = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
            return EvalScore.CriterionScore(criterionId: crit.id, score: avg)
        }
        return EvalScore.compute(caseId: evalCase.id, mode: mode, rubric: evalCase.rubric, scores: perCriterion, judgeWorkerId: judge.id)
    }

    /// Score the same case's artifacts across modes for a side-by-side comparison.
    public func compareModes(
        artifactsByMode: [String: String],
        evalCase: EvalCase,
        judge: Worker,
        manifest: DriverManifest,
        config: EvalConfig
    ) async -> [EvalScore] {
        var results: [EvalScore] = []
        for (mode, artifact) in artifactsByMode.sorted(by: { $0.key < $1.key }) {
            results.append(await score(artifact: artifact, mode: mode, evalCase: evalCase, judge: judge, manifest: manifest, config: config))
        }
        return results
    }

    private func scoringPrompt(rubric: Rubric, artifact: String) -> String {
        let criteria = rubric.criteria.map { "- \($0.id): \($0.description) (weight \($0.weight))" }.joined(separator: "\n")
        return """
        You are a strict evaluator. Score the artifact below against each rubric \
        criterion from 0.0 (not met) to 1.0 (fully met). Negative-weight criteria \
        penalize when present, so score how strongly the bad property appears. \
        Output ONLY a single fenced ```json array:
        [{ "criterionId": "...", "score": 0.0, "note": "..." }]

        # Rubric
        \(criteria)

        # Artifact
        \(artifact)
        """
    }

    func parseScores(_ raw: String) -> [EvalScore.CriterionScore]? {
        guard let json = JudgeOutputParser.extractJSONArray(from: raw) else { return nil }
        return try? CoreJSON.decode([EvalScore.CriterionScore].self, from: Data(json.utf8))
    }
}
