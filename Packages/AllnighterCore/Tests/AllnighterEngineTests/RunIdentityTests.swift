import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// FR2 — run identity tells the truth: worker · lane · mutating|readOnly; Default Team naming.
final class RunIdentityTests: XCTestCase {
    func testTeamDisplayNameHonestForDefaultRoute() {
        XCTAssertEqual(
            RunIdentity.teamDisplayName(
                presetId: "default_chat", catalogDisplayName: "Auto", explicitTeamChosen: false),
            "Default Team")
        XCTAssertEqual(
            RunIdentity.teamDisplayName(
                presetId: "default_chat", catalogDisplayName: "Auto (mine)", explicitTeamChosen: false),
            "Default Team")
        XCTAssertEqual(
            RunIdentity.teamDisplayName(
                presetId: "default_chat", catalogDisplayName: "Auto", explicitTeamChosen: true),
            "Auto")
        XCTAssertEqual(
            RunIdentity.teamDisplayName(
                presetId: "execution_playbook", catalogDisplayName: "Execution Playbook",
                explicitTeamChosen: false),
            "Execution Playbook")
    }

    func testIdentitySummaryFormat() {
        XCTAssertEqual(
            RunIdentity.summary(workerId: "model_grok", lane: .code, mutating: true),
            "worker model_grok · lane code · mutating")
        XCTAssertEqual(
            RunIdentity.summary(workerId: "model_opus", lane: .design, mutating: false),
            "worker model_opus · lane design · readOnly")
    }

    func testExplicitWorkerMutatingRunIdentity() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let model = Model(
            id: "model_grok", displayName: "Grok Build", modelLabel: "grok-build",
            driverId: "grok", role: .both)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry()
        )

        let result = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path, workerId: "model_grok", lane: .code),
            origin: .cli, runId: "identity-run")

        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }

        XCTAssertEqual(run.presetId, "default_chat")
        XCTAssertEqual(run.teamDisplayName, "Default Team")
        XCTAssertEqual(run.lane, .code)
        XCTAssertEqual(run.workers.first?.modelId, "model_grok")
        XCTAssertTrue(run.mutating)

        let trj = TeamRunJSONMapper.map(
            run, models: [model], manifests: [], context: .init(runJournalPath: "/tmp/run.json"))
        XCTAssertEqual(trj.teamRun.teamDisplayName, "Default Team")
        XCTAssertEqual(trj.teamRun.teamPresetId, "default_chat")
        XCTAssertEqual(trj.teamRun.workerId, "model_grok")
        XCTAssertEqual(trj.teamRun.writePolicy, "mutating")
        XCTAssertEqual(trj.teamRun.identitySummary, "worker model_grok · lane code · mutating")

        XCTAssertEqual(
            RunIdentity.cliFooter(run),
            "run identity-run · worker model_grok · lane code · mutating · no repo change · Default Team · default_chat")
    }
}
