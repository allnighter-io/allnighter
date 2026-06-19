import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PRJ-S08: the Project Manager chat turn — model resolution, the no-ready-model
/// wait turn (never fabricated), and a grounded answer turn via a mock model.
final class ProjectManagerServiceTests: XCTestCase {

    private func project(managerModelId: String? = nil) -> Project {
        Project(
            id: "prj_test", displayName: "Test", localRootPath: NSTemporaryDirectory(),
            normalizedRootPath: NSTemporaryDirectory(), kind: .folder,
            createdAt: Date(timeIntervalSince1970: 1), lastOpenedAt: Date(timeIntervalSince1970: 1),
            managerModelId: managerModelId
        )
    }

    private func packet() -> ProjectContextPacket {
        ProjectContextPacketBuilder.build(project: project())
    }

    // MARK: - Model resolution

    func testResolveNilWhenNoReadyModels() {
        XCTAssertNil(ProjectManagerService.resolveManagerModel(project: project(), readyModels: []))
    }

    func testResolvePrefersPinnedManagerModelWhenReady() {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let grok = TestSupport.worker("model_grok", driverId: "grok")
        let chosen = ProjectManagerService.resolveManagerModel(
            project: project(managerModelId: "model_grok"), readyModels: [opus, grok])
        XCTAssertEqual(chosen?.id, "model_grok", "a ready pinned manager model wins over the strongest planner")
    }

    func testResolveFallsBackToStrongestReadyPlannerWhenPinnedNotReady() {
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        // Pinned model is not in the ready set → fall back to strongest ready planner.
        let chosen = ProjectManagerService.resolveManagerModel(
            project: project(managerModelId: "model_absent"), readyModels: [opus])
        XCTAssertEqual(chosen?.id, "model_opus")
    }

    // MARK: - Turn production

    func testNoReadyModelYieldsWaitTurnNeverFabricated() async {
        let service = ProjectManagerService(runner: MockCommandRunner(scripts: [:]), registry: DriverRegistry([]))
        let turn = await service.chat(project: project(), packet: packet(), message: "Where are we?", readyModels: [])
        XCTAssertEqual(turn.mode, .wait)
        XCTAssertNil(turn.answerMarkdown, "a wait turn never carries a fabricated answer")
        XCTAssertNil(turn.modelId)
        XCTAssertFalse(turn.warnings.isEmpty, "the readiness blocker is sourced")
        XCTAssertTrue(turn.nextActions.contains { $0.kind == .recheckWorkers })
        XCTAssertTrue(turn.isWellFormed)
    }

    func testAnswerTurnIsGroundedAndRecordsModel() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let mock = MockCommandRunner(scripts: ["claude": .init(stdout: "We are at commit abc on main.", exitCode: 0)])
        let service = ProjectManagerService(runner: mock, registry: DriverRegistry([manifest]))

        let turn = await service.chat(project: project(), packet: packet(), message: "Where are we?", readyModels: [opus])
        XCTAssertEqual(turn.mode, .answer)
        XCTAssertEqual(turn.modelId, "model_opus", "the answer records which model produced it (run truth)")
        XCTAssertEqual(turn.answerMarkdown, "We are at commit abc on main.")
        XCTAssertNotNil(turn.contextPacketId)
        XCTAssertTrue(turn.proposals.isEmpty, "Chat Law: an answer turn never auto-creates work")
        XCTAssertTrue(turn.isWellFormed)
    }

    func testModelFailureYieldsWaitTurnWithSourcedReason() async {
        let manifest = TestSupport.headlessManifest(id: "claude_code", command: "claude")
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        // The model runs but errors — surface the reason, never invent an answer.
        let mock = MockCommandRunner(scripts: ["claude": .init(stderr: "not logged in", exitCode: 1)])
        let service = ProjectManagerService(runner: mock, registry: DriverRegistry([manifest]))

        let turn = await service.chat(project: project(), packet: packet(), message: "Where are we?", readyModels: [opus])
        XCTAssertEqual(turn.mode, .wait)
        XCTAssertNil(turn.answerMarkdown)
        XCTAssertTrue(turn.warnings.contains { $0.contains("not logged in") || $0.contains("did not answer") })
    }

    // MARK: - Prompt grounding

    func testPromptEmbedsPacketTruthAndForbidsInvention() {
        let prompt = ProjectManagerService.buildPrompt(packet: packet(), message: "Where are we?")
        XCTAssertTrue(prompt.contains("Project context"))
        XCTAssertTrue(prompt.contains("Where are we?"))
        XCTAssertTrue(prompt.lowercased().contains("inventing") || prompt.lowercased().contains("don't know"))
    }
}
