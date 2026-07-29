import XCTest
import AllnighterCore
@testable import AllnighterCLI
@testable import AllnighterEngine

/// RSC-HF: `alln run --no-wait` — public `--run-id` removed; child is the normal
/// registered verb; parent acks only after `DetachedHandoff` acceptance.
final class RunNoWaitTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-run-no-wait-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    func testMintRunIdProducesDistinctUUIDStrings() {
        let a = RunService.mintRunId()
        let b = RunService.mintRunId()
        XCTAssertNotEqual(a, b)
        XCTAssertNotNil(UUID(uuidString: a))
        XCTAssertNotNil(UUID(uuidString: b))
    }

    func testRunIdCollisionFalseForNilOrEmpty() {
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        XCTAssertFalse(RunCLI.runIdCollision(nil, store: store))
        XCTAssertFalse(RunCLI.runIdCollision("", store: store))
    }

    func testRunIdCollisionTrueAfterPersist() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let svc = fixtureService(repo: repo, store: store)
        let request = RunRequest(message: "make a change", repoRoot: repo.path, pinnedModelId: "model_grok")

        XCTAssertFalse(RunCLI.runIdCollision("run_fixed_id", store: store))
        guard case .success = await svc.run(request, origin: .cli, runId: "run_fixed_id") else {
            return XCTFail("fixture run failed")
        }
        XCTAssertTrue(RunCLI.runIdCollision("run_fixed_id", store: store))
    }

    func testRunIdCollisionTreatsCorruptJournalAsOccupied() throws {
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let dir = store.rootDirectory.appendingPathComponent("run_corrupt_id", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: dir.appendingPathComponent("run.json"))
        XCTAssertTrue(RunCLI.runIdCollision("corrupt_id", store: store))
    }

    func testValidateRunIdRejectsPathTraversal() {
        XCTAssertThrowsError(try RunStore.validateRunId("../escape"))
        XCTAssertThrowsError(try RunStore.validateRunId("a/b"))
        XCTAssertThrowsError(try RunStore.validateRunId(""))
        XCTAssertNoThrow(try RunStore.validateRunId(UUID().uuidString))
    }

    func testDetachedHandoffReportAcceptedWritesRunnerReady() throws {
        let handoff = tmp.appendingPathComponent("handoff", isDirectory: true)
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        DetachedHandoff.reportAccepted(
            id: "run_accepted",
            environment: [DetachedHandoff.envKey: handoff.path]
        )
        let ready = ProcessOwnership.readRunnerReady(in: handoff)
        XCTAssertEqual(ready?.outcome, .accepted)
        XCTAssertEqual(ready?.runId, "run_accepted")
    }

    func testChildArgumentsStripsOnlyNoWait() {
        let parentArgv = ["run", "fix the bug", "--project", ".", "--no-wait", "--json", "--no-auto-serve"]
        XCTAssertEqual(
            DetachedDispatch.childArguments(from: parentArgv),
            ["run", "fix the bug", "--project", ".", "--json", "--no-auto-serve"]
        )
    }

    func testRunStartedUnderExplicitIdIsFindable() async throws {
        let repo = tmp.appendingPathComponent("repo2", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let svc = fixtureService(repo: repo, store: store)
        let request = RunRequest(message: "make a change", repoRoot: repo.path, pinnedModelId: "model_grok")
        let mintedId = RunService.mintRunId()
        guard case .success(let run) = await svc.run(request, origin: .cli, runId: mintedId) else {
            return XCTFail("fixture run failed")
        }
        XCTAssertEqual(run.id, mintedId)
        let found = store.loadRaw(runId: mintedId) ?? store.load(runId: mintedId)
        XCTAssertEqual(found?.id, mintedId)
    }

    func testRunCLIRoutesNoWaitThroughLaunchAndAwaitAcceptance() throws {
        let here = URL(fileURLWithPath: #filePath)
        let packageRoot = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runCLI = packageRoot.appendingPathComponent("Sources/AllnighterCLI/RunCLI.swift")
        let text = try String(contentsOf: runCLI, encoding: .utf8)
        XCTAssertFalse(text.contains("Process()"))
        XCTAssertTrue(text.contains("launchAndAwaitAcceptance"))
        XCTAssertTrue(text.contains("DetachedDispatch.childArguments"))
        XCTAssertFalse(text.contains("FlagSpec(\"run-id\"") || text.contains("opts.value(\"run-id\")"))
    }

    private func fixtureService(repo: URL, store: RunStore) -> RunService {
        RunService(
            models: [Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                           driverId: "grok", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: store,
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .frontier, allowHealthySubstitutions: true,
                                     tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }
}
