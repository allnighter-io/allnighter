import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Run-path delivery law (single worker AND team): when the user attaches an image, a
/// vision-capable worker receives the real image PATH block, while a non-vision worker
/// receives the explicit "you can't see it" notice — so it never fabricates having seen
/// the screenshot. This is the kill test for "if the teams don't see the problem they
/// can't help": every seat's resolved prompt is asserted.
final class TeamRunAttachmentDeliveryTests: XCTestCase {

    private func delivery(
        path: String = ".allnighter/attachments/thread_t/a1.png"
    ) -> IncludedAttachmentDelivery {
        IncludedAttachmentDelivery(
            attachmentId: "a1", sequence: 0,
            canonicalPath: "/canonical/a1.png",
            deliveredPathUsed: path,
            storedSha256: "deadbeef")
    }

    func testTeamWorkersGetVisionAndNonVisionDeliveries() async {
        let runner = WorkerRunner(commandRunner: MockCommandRunner(scripts: [
            "claude": .init(stdout: "vision answer", exitCode: 0),
            "grok": .init(stdout: "blind answer", exitCode: 0),
            "gemini": .init(stdout: "# Plan", exitCode: 0)   // plan writer
        ]))
        let registry = DriverRegistry([
            TestSupport.visionManifest(id: "claude_code", command: "claude"),  // reads images
            TestSupport.headlessManifest(id: "grok", command: "grok"),          // blind
            TestSupport.headlessManifest(id: "antigravity", command: "gemini")
        ])
        let coord = CatalogRunCoordinator(workerRunner: runner, registry: registry, idFactory: { UUID().uuidString })

        let visionW = Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, skillId: nil, purpose: .answer)
        let blindW = Worker(id: "model_grok#0", modelId: "model_grok", instanceIndex: 0, skillId: nil, purpose: .answer)
        let writer = Worker(id: "model_gemini#0", modelId: "model_gemini", instanceIndex: 0, skillId: "insight_writer", purpose: .plan)
        let resolved = ResolvedTeamRun(
            teamPresetId: "t", teamDisplayName: "Bug Hunt", lane: .code, outputKind: .plan,
            effort: .med, scoutWorker: nil, answerWorkers: [visionW, blindW], planWriter: writer, isRunnable: true)
        let models = [
            TestSupport.worker("model_opus", driverId: "claude_code"),
            TestSupport.worker("model_grok", driverId: "grok"),
            TestSupport.worker("model_gemini", driverId: "antigravity", role: .both)
        ]

        let run = await coord.run(
            resolved: resolved, prompt: "the button is broken", models: models,
            runId: "r1", deliveries: [delivery()])

        let visionSnap = run.workers.first { $0.id == "model_opus#0" }?.resolvedWorkerPromptSnapshot
        XCTAssertTrue(visionSnap?.contains("Attached images") == true,
                      "vision worker must get the image path block")
        XCTAssertTrue(visionSnap?.contains(".allnighter/attachments/thread_t/a1.png") == true,
                      "vision worker must get the real delivered path")

        let blindSnap = run.workers.first { $0.id == "model_grok#0" }?.resolvedWorkerPromptSnapshot
        XCTAssertTrue(blindSnap?.contains("does not support image viewing") == true,
                      "non-vision worker must get the explicit cannot-see notice")
        XCTAssertFalse(blindSnap?.contains("Attached images (use these paths)") == true,
                       "non-vision worker must NOT get a path block it can't use")
    }

    func testNoDeliveriesLeavesPromptsUnchanged() async {
        let runner = WorkerRunner(commandRunner: MockCommandRunner(scripts: [
            "claude": .init(stdout: "answer", exitCode: 0),
            "gemini": .init(stdout: "# Plan", exitCode: 0)
        ]))
        let registry = DriverRegistry([
            TestSupport.visionManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "antigravity", command: "gemini")
        ])
        let coord = CatalogRunCoordinator(workerRunner: runner, registry: registry, idFactory: { UUID().uuidString })
        let answerW = Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, skillId: nil, purpose: .answer)
        let writer = Worker(id: "model_gemini#0", modelId: "model_gemini", instanceIndex: 0, skillId: "insight_writer", purpose: .plan)
        let resolved = ResolvedTeamRun(
            teamPresetId: "t", teamDisplayName: "T", lane: .code, outputKind: .plan,
            effort: .med, scoutWorker: nil, answerWorkers: [answerW], planWriter: writer, isRunnable: true)
        let models = [
            TestSupport.worker("model_opus", driverId: "claude_code"),
            TestSupport.worker("model_gemini", driverId: "antigravity", role: .both)
        ]

        let run = await coord.run(resolved: resolved, prompt: "PLAIN", models: models, runId: "r2")
        let snap = run.workers.first { $0.id == "model_opus#0" }?.resolvedWorkerPromptSnapshot
        XCTAssertTrue(snap?.contains("PLAIN") == true)
        XCTAssertFalse(snap?.contains("Attached images") == true, "no attachments → no image block")
        XCTAssertFalse(snap?.contains("does not support image viewing") == true, "no attachments → no notice")
    }
}
