import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class EvalHarnessTests: XCTestCase {

    private func evalCase() -> EvalCase {
        EvalCase(
            id: "case1",
            prompt: "Design a run store.",
            rubric: Rubric(criteria: [
                RubricCriterion(id: "correct", description: "Is it correct?", weight: 2),
                RubricCriterion(id: "verbose", description: "Penalize verbosity.", weight: -1)
            ], passMark: 1.0)
        )
    }

    private func judge() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    func testScoresArtifactAgainstRubric() async {
        // Judge returns: correct 1.0, verbose 0.0 -> total = 2*1 + (-1)*0 = 2 >= 1 pass.
        let output = "```json\n[{\"criterionId\":\"correct\",\"score\":1.0},{\"criterionId\":\"verbose\",\"score\":0.0}]\n```"
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: output, exitCode: 0)])
        let harness = EvalHarness(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let score = await harness.score(
            artifact: "A clean actor-based store.", mode: "combined",
            evalCase: evalCase(), judge: judge(), manifest: manifest,
            config: EvalConfig(planWriterModelId: "model_opus", passes: 1)
        )
        XCTAssertEqual(score.totalWeighted, 2.0, accuracy: 0.001)
        XCTAssertTrue(score.pass)
        XCTAssertEqual(score.mode, "combined")
    }

    func testNegativeWeightPenalizes() {
        // Direct compute: correct 0.5 (*2=1.0), verbose 1.0 (*-1=-1.0) -> 0.0 < 1 fail.
        let score = EvalScore.compute(
            caseId: "case1", mode: "solo", rubric: evalCase().rubric,
            scores: [.init(criterionId: "correct", score: 0.5), .init(criterionId: "verbose", score: 1.0)],
            planWriterModelId: "model_opus"
        )
        XCTAssertEqual(score.totalWeighted, 0.0, accuracy: 0.001)
        XCTAssertFalse(score.pass)
    }

    func testCompareModesReturnsScorePerMode() async {
        let output = "```json\n[{\"criterionId\":\"correct\",\"score\":1.0},{\"criterionId\":\"verbose\",\"score\":0.0}]\n```"
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: output, exitCode: 0)])
        let harness = EvalHarness(workerRunner: DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(mock)))
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")

        let scores = await harness.compareModes(
            artifactsByMode: ["solo": "a", "combined": "b", "separate": "c"],
            evalCase: evalCase(), judge: judge(), manifest: manifest,
            config: EvalConfig(planWriterModelId: "model_opus", passes: 1)
        )
        XCTAssertEqual(Set(scores.map(\.mode)), ["solo", "combined", "separate"])
    }

    func testRubricFromAcceptanceCriteria() {
        let rubric = Rubric.fromAcceptanceCriteria(["Compiles", "Tests pass", "No regressions"])
        XCTAssertEqual(rubric.criteria.count, 3)
        XCTAssertEqual(rubric.passMark, 3 * 0.7, accuracy: 0.001)
    }
}
