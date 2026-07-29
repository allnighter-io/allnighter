import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// FR2 — run identity tells the truth: worker · lane · mutating|readOnly; Default Team naming.
final class RunIdentityTests: HermeticSupportTestCase {
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
                presetId: "build_slice", catalogDisplayName: "Build a Slice",
                explicitTeamChosen: false),
            "Build a Slice")
    }

    func testIdentitySummaryFormat() {
        XCTAssertEqual(
            RunIdentity.summary(workerId: "model_grok", lane: .code, mutating: true),
            "agent model_grok · lane code · mutating")
        XCTAssertEqual(
            RunIdentity.summary(workerId: "model_opus", lane: .design, mutating: false),
            "agent model_opus · lane design · readOnly")
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
            // Hermetic: a temp run journal (never the real ~/Library Runs) and a
            // seeded probe so the explicit-worker readiness gate does not depend on
            // this machine's grok probe state.
            runStore: RunStore(rootDirectory: repo.appendingPathComponent("runs", isDirectory: true)),
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )

        let result = await service.run(
            RunRequest(message: "Say done", repoRoot: repo.path, pinnedModelId: "model_grok", lane: .code),
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
        XCTAssertEqual(trj.teamRun.modelId, "model_grok")
        XCTAssertEqual(trj.teamRun.writePolicy, "mutating")
        XCTAssertEqual(trj.teamRun.identitySummary, "agent model_grok · lane code (context — --team routes) · mutating")

        // SH-S08 (a8fddec1) inserts measured single-seat timing (queue/duration/…)
        // into the outcome headline; this run executes live, so bracket the variable
        // timing with the stable identity prefix and the team/preset suffix.
        let footer = RunIdentity.cliFooter(run)
        XCTAssertTrue(
            footer.hasPrefix("run identity-run · agent model_grok · lane code (context — --team routes) · mutating · no repo change"),
            "footer identity prefix; got: \(footer)")
        XCTAssertTrue(
            footer.hasSuffix("· Default Team · preset default_chat"),
            "footer team/preset suffix; got: \(footer)")
    }
}
