import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Stage 0 scout: the scout runs FIRST and its distilled output is injected into
/// every downstream worker's prompt so the crew reasons over the same source.
final class SignalScoutCoordinatorTests: XCTestCase {

    private func coordinator(_ scripts: [String: MockCommandRunner.Script]) -> CatalogRunCoordinator {
        let runner = DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(MockCommandRunner(scripts: scripts)))
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "grok", command: "grok"),
            TestSupport.headlessManifest(id: "antigravity", command: "gemini"),
            TestSupport.headlessManifest(id: "claude_code", command: "claude")
        ])
        return CatalogRunCoordinator(workerRunner: runner, registry: registry, idFactory: { UUID().uuidString })
    }

    func testScoutRunsFirstAndIsInjectedDownstream() async {
        let distilled = "SCOUT_DISTILLED_SOURCE_XYZ"
        let coord = coordinator([
            "grok": .init(stdout: distilled, exitCode: 0),
            "gemini": .init(stdout: "interpretation", exitCode: 0),
            "claude": .init(stdout: "# Insight\n\nthe move", exitCode: 0)
        ])
        let scout = Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
                           skillId: "signal_source_reader", skillName: "Source Reader", purpose: .scout)
        let interp = Worker(id: "model_gemini#0", modelId: "model_gemini", instanceIndex: 0,
                            skillId: "signal_project_fit", skillName: "Project Fit", purpose: .answer)
        let lead = Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
                          skillId: "insight_writer", skillName: "Insight Writer", purpose: .plan)
        let resolved = ResolvedTeamRun(
            teamPresetId: "signal_post_to_project", teamDisplayName: "Signal", lane: .signal,
            outputKind: .insight, effort: .med,
            scoutWorker: scout, answerWorkers: [interp], planWriter: lead, isRunnable: true)
        let models = [
            TestSupport.worker("model_grok", driverId: "grok"),
            TestSupport.worker("model_gemini", driverId: "antigravity"),
            TestSupport.worker("model_opus", driverId: "claude_code", role: .both)
        ]

        let run = await coord.run(resolved: resolved, prompt: "what does this mean for us?", models: models, runId: "r_scout")

        // The scout produced the distilled source.
        let scoutAnswer = run.workerAnswers.first { $0.memberId == "model_grok#0" }
        XCTAssertEqual(scoutAnswer?.output, distilled)

        // The interpreter's assembled prompt contains the scout's distilled source.
        let interpSnapshot = run.workers.first { $0.id == "model_gemini#0" }?.resolvedWorkerPromptSnapshot
        XCTAssertNotNil(interpSnapshot)
        XCTAssertTrue(interpSnapshot?.contains(distilled) == true,
                      "interpreter must reason over the scout-distilled source")

        // The run completed with a synthesized insight stage.
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(run.stages.contains { $0.purpose == .plan && $0.status == .done })
    }

    func testNoScoutLeavesPromptUnchanged() async {
        let coord = coordinator([
            "gemini": .init(stdout: "interp", exitCode: 0),
            "claude": .init(stdout: "# Insight", exitCode: 0)
        ])
        let interp = Worker(id: "model_gemini#0", modelId: "model_gemini", instanceIndex: 0,
                            skillId: "signal_project_fit", skillName: "Project Fit", purpose: .answer)
        let lead = Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
                          skillId: "insight_writer", skillName: "Insight Writer", purpose: .plan)
        let resolved = ResolvedTeamRun(
            teamPresetId: "t", teamDisplayName: "Signal", lane: .signal, outputKind: .insight,
            effort: .med, scoutWorker: nil, answerWorkers: [interp], planWriter: lead, isRunnable: true)
        let models = [
            TestSupport.worker("model_gemini", driverId: "antigravity"),
            TestSupport.worker("model_opus", driverId: "claude_code", role: .both)
        ]

        let run = await coord.run(resolved: resolved, prompt: "PLAIN_PROMPT", models: models, runId: "r_noscout")
        let snap = run.workers.first { $0.id == "model_gemini#0" }?.resolvedWorkerPromptSnapshot
        XCTAssertTrue(snap?.contains("PLAIN_PROMPT") == true)
        XCTAssertFalse(snap?.contains("# Source (distilled") == true, "no scout → no injected source section")
    }
}
