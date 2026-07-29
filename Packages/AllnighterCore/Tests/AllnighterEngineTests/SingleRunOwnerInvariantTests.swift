import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CR-S02 proof wall: `RunService` is the sole run-resolution/semantics owner.
/// The direct CLI adapter only parses + hands off to `RunService` (run / dryRun),
/// and contains no Team/root/write-lock resolution; dry-run and foreground resolve
/// through the same owner and agree on write policy.
final class SingleRunOwnerInvariantTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-single-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    // MARK: - Source invariant: the CLI adapter holds no resolution logic

    private func runCLISource() throws -> String {
        // #filePath = .../Packages/AllnighterCore/Tests/AllnighterEngineTests/<this>.swift
        let here = URL(fileURLWithPath: #filePath)
        let packageRoot = here.deletingLastPathComponent()   // AllnighterEngineTests
            .deletingLastPathComponent()                     // Tests
            .deletingLastPathComponent()                     // AllnighterCore
        let runCLI = packageRoot
            .appendingPathComponent("Sources/AllnighterCLI/RunCLI.swift")
        return try String(contentsOf: runCLI, encoding: .utf8)
    }

    func testDirectCLIDelegatesToRunServiceOwner() throws {
        let source = try runCLISource()
        XCTAssertTrue(source.contains("service.run("), "RunCLI must dispatch foreground runs to RunService.run")
        XCTAssertTrue(source.contains("service.dryRun("), "RunCLI must dispatch dry-run to RunService.dryRun")
    }

    func testCLIContainsNoTeamRootOrWriteLockResolution() throws {
        let source = try runCLISource()
        let forbidden = [
            "RunInvocationResolver",       // team/worker/Auto resolution
            "RunInvocationInput",          // resolver input assembly
            "RunInvocationResolveContext", // resolver context assembly
            "RunInvocationNormalizedFlags",
            "RunWriteLockRegistry",        // write-lock reasoning
            "ExecutionLane.key",           // write-lock key derivation
            "TeamResolver",                // roster resolution
            "TeamCatalog.get",             // team-shape lookup for resolution
            "TeamCatalog.defaultRunTeam",
            ".isHeld(",                    // live write-lock probe
        ]
        for symbol in forbidden {
            XCTAssertFalse(source.contains(symbol),
                           "RunCLI must not perform resolution — found `\(symbol)`")
        }
    }

    // MARK: - Functional: dry-run and foreground resolve through the same owner

    private func service(team: TeamPreset, model: Model, driverCommand: String) -> RunService {
        RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: model.driverId, command: driverCommand)]),
            teams: [team],
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: MockCommandRunner(scripts: [driverCommand: .init(stdout: "# Answer\nok", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: [model.id]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: model.driverId, status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }

    func testDryRunAndForegroundAgreeOnResearchWritePolicy() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let model = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                          driverId: "claude_code", role: .both)
        let team = TeamPreset(
            id: "research_owner", displayName: "Research", lane: .code, outputKind: .plan,
            mutating: false,
            agentSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer",
                                         purpose: .answer, preferredModelId: "model_opus")],
            lead: TeamLeadSpec(skillId: "plan_writer_build"))
        let svc = service(team: team, model: model, driverCommand: "claude")
        let request = RunRequest(message: "research", repoRoot: repo.path, presetId: "research_owner")

        let dry = await svc.dryRun(request, readyModels: [model])
        XCTAssertEqual(dry.writePolicy, RunWritePolicy.readOnly.rawValue)

        guard case .success(let run) = await svc.run(request, origin: .cli, runId: "owner-research") else {
            return XCTFail("run failed")
        }
        XCTAssertFalse(run.mutating, "dry-run and foreground agree: research is read-only")
    }

    func testDryRunAndForegroundAgreeOnMutatingWritePolicy() async throws {
        let repo = tmp.appendingPathComponent("repo2", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let model = Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                          driverId: "grok", role: .both)
        // Bare prompt + explicit worker resolves to the mutating Default Team.
        let svc = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
        let request = RunRequest(message: "make a change", repoRoot: repo.path, workerId: "model_grok")

        let dry = await svc.dryRun(request, readyModels: [model])
        XCTAssertEqual(dry.writePolicy, RunWritePolicy.mutating.rawValue)

        guard case .success(let run) = await svc.run(request, origin: .cli, runId: "owner-mutating") else {
            return XCTFail("run failed")
        }
        XCTAssertTrue(run.mutating, "dry-run and foreground agree: this run is mutating")
    }
}
