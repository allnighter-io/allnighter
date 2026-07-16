import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PN-S02: additive per-seat messages on the answer path (`CatalogRunCoordinator`)
/// + blind independence (each seat's prompt is its own; no cross-seat leakage).
final class PanelPerSeatDispatchTests: XCTestCase {

    func testPerSeatWorkerPromptsAreIndependentAndBlind() async {
        let runner = DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(MockCommandRunner(scripts: [
            "claude": .init(stdout: "seat A answer", exitCode: 0),
            "codex": .init(stdout: "seat B answer", exitCode: 0),
        ])))
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "codex", command: "codex"),
        ])
        let coord = CatalogRunCoordinator(
            workerRunner: runner, registry: registry, idFactory: { UUID().uuidString }
        )

        // Worker ids must match how seats are keyed in workerPrompts. For panel,
        // seats use model ids as workerId (roster resolution is PN-S04); here we
        // key off the resolved Worker.id so the answer path can look them up.
        let workerA = Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, skillId: nil, purpose: .answer)
        let workerB = Worker(id: "model_codex#0", modelId: "model_codex", instanceIndex: 0, skillId: nil, purpose: .answer)
        let resolved = ResolvedTeamRun(
            teamPresetId: "panel_test", teamDisplayName: "Panel", lane: .code, outputKind: .specReview,
            effort: .med, scoutWorker: nil, answerWorkers: [workerA, workerB],
            planWriter: nil, isRunnable: true
        )
        let models = [
            TestSupport.worker("model_opus", driverId: "claude_code"),
            TestSupport.worker("model_codex", driverId: "codex"),
        ]

        let seatA = PanelSeat(workerId: workerA.id, lens: "adversary", lensInstruction: "Lens-A-only-token")
        let seatB = PanelSeat(workerId: workerB.id, lens: "simplicity", lensInstruction: "Lens-B-only-token")
        let brief = "Brief shared; seats stay blind to each other."
        let target = "docs/phases/Pilot_Panel.md"
        let workerPrompts = PanelSeatPrompt.workerPrompts(
            seats: [seatA, seatB], brief: brief, targetPath: target
        )

        let run = await coord.run(
            resolved: resolved,
            prompt: "SHARED_FALLBACK_SHOULD_NOT_APPEAR",
            models: models,
            runId: "panel_dispatch_1",
            workerPrompts: workerPrompts
        )

        let snapA = run.workers.first { $0.id == workerA.id }?.resolvedWorkerPromptSnapshot
        let snapB = run.workers.first { $0.id == workerB.id }?.resolvedWorkerPromptSnapshot
        XCTAssertNotNil(snapA)
        XCTAssertNotNil(snapB)

        // Per-seat content present.
        XCTAssertTrue(snapA?.contains("Lens-A-only-token") == true)
        XCTAssertTrue(snapA?.contains("adversary") == true)
        XCTAssertTrue(snapA?.contains(brief) == true)
        XCTAssertTrue(snapA?.contains(PanelSeatPrompt.schemaContract) == true)
        XCTAssertTrue(snapB?.contains("Lens-B-only-token") == true)
        XCTAssertTrue(snapB?.contains("simplicity") == true)

        // Blind law: no cross-seat leakage in either prompt.
        XCTAssertFalse(snapA?.contains("Lens-B-only-token") == true,
                       "seat A must not see seat B's lens instruction")
        XCTAssertFalse(snapB?.contains("Lens-A-only-token") == true,
                       "seat B must not see seat A's lens instruction")
        XCTAssertFalse(snapA?.contains("simplicity") == true)
        XCTAssertFalse(snapB?.contains("adversary") == true)

        // Shared fallback prompt is NOT used when per-seat messages are provided.
        XCTAssertFalse(snapA?.contains("SHARED_FALLBACK_SHOULD_NOT_APPEAR") == true)
        XCTAssertFalse(snapB?.contains("SHARED_FALLBACK_SHOULD_NOT_APPEAR") == true)

        // Both seats produced answers (dispatch ran independently).
        XCTAssertEqual(run.workerAnswers.count, 2)
        XCTAssertTrue(run.workerAnswers.allSatisfy { $0.result.status == .done })
    }

    func testSharedPromptPathUnchangedWhenWorkerPromptsNil() async {
        let runner = DefaultWorkerRunner(streamingRunner: CommandRunnerAsStreaming(MockCommandRunner(scripts: [
            "claude": .init(stdout: "answer", exitCode: 0),
        ])))
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
        ])
        let coord = CatalogRunCoordinator(
            workerRunner: runner, registry: registry, idFactory: { UUID().uuidString }
        )
        let worker = Worker(id: "model_opus#0", modelId: "model_opus", instanceIndex: 0, skillId: nil, purpose: .answer)
        let resolved = ResolvedTeamRun(
            teamPresetId: "t", teamDisplayName: "T", lane: .code, outputKind: .specReview,
            effort: .med, scoutWorker: nil, answerWorkers: [worker],
            planWriter: nil, isRunnable: true
        )
        let models = [TestSupport.worker("model_opus", driverId: "claude_code")]

        let run = await coord.run(
            resolved: resolved,
            prompt: "SHARED_ONLY_PROMPT",
            models: models,
            runId: "shared_path",
            workerPrompts: nil
        )
        let snap = run.workers.first?.resolvedWorkerPromptSnapshot
        XCTAssertTrue(snap?.contains("SHARED_ONLY_PROMPT") == true)
    }

    func testSchemaContractAppearsOncePerSeatPrompt() {
        let seat = PanelSeat(workerId: "w", lens: "adversary", lensInstruction: "x")
        let p = PanelSeatPrompt.assemble(seat: seat, brief: "b", targetPath: "t")
        let count = p.components(separatedBy: "# Finding schema (required)").count - 1
        XCTAssertEqual(count, 1)
    }
}
