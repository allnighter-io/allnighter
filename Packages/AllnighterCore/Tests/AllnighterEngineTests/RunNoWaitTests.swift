import XCTest
import AllnighterCore
@testable import AllnighterCLI
@testable import AllnighterEngine

/// RSC-S04 (`docs/phases/Round_Survives_The_Caller.md`): `alln run --no-wait` +
/// `--run-id`. Unlike relay's `--no-wait` — whose own dispatch correctness IS a
/// mutate-under-lock step a naive child re-run would get wrong — `RunService.run`'s
/// dispatch has no shared mutable state to race, so the detached child is the
/// normal, REGISTERED `alln run … --run-id <id>` command, not a hidden verb. These
/// tests prove: (1) the RUN_ID_IN_USE collision primitive `RunCLI.run(_:runtime:)`
/// checks in the foreground before ever reaching the `--no-wait` dispatch branch,
/// (2) `RunService.mintRunId()`'s format, (3) the detached child's argv
/// construction, and (4) the semantic round trip — a run persisted under an id
/// chosen at dispatch time is the exact id `alln run resume <id>` looks up.
///
/// A real subprocess round trip (spawn the actual `alln` binary detached, kill the
/// caller, poll `resume`) is exercised only by the Works Test — no existing unit
/// test infra in this package builds and drives the real product binary end to end
/// (`DetachedDispatchTests` proves `DetachedDispatch.launch`/`childArguments`
/// hermetically with a throwaway shell script instead, and RSC-S03's own relay
/// `--no-wait` tests stop at the same boundary). What IS unit-tested here is the
/// exact in-process mechanism the child performs: `RunService.run(runId:)` persists
/// under the given id, and that id is what `alln run resume` looks up
/// (`RunStore.loadRaw`/`.load`).
final class RunNoWaitTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-run-no-wait-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - RunService.mintRunId(): one format, matching the internal default

    func testMintRunIdProducesDistinctUUIDStrings() {
        let a = RunService.mintRunId()
        let b = RunService.mintRunId()
        XCTAssertNotEqual(a, b)
        XCTAssertNotNil(UUID(uuidString: a), "mintRunId must match the format RunService.run mints internally")
        XCTAssertNotNil(UUID(uuidString: b))
    }

    // MARK: - runIdCollision: the RUN_ID_IN_USE refusal condition

    func testRunIdCollisionFalseForNilOrEmpty() {
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        XCTAssertFalse(RunCLI.runIdCollision(nil, store: store))
        XCTAssertFalse(RunCLI.runIdCollision("", store: store))
    }

    func testRunIdCollisionFalseWhenNoRunPersistedUnderThatId() {
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        XCTAssertFalse(RunCLI.runIdCollision("run_never_persisted", store: store))
    }

    func testRunIdCollisionTrueAfterAServiceRunPersistsThatExactId() async throws {
        let repo = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let svc = fixtureService(repo: repo, store: store)
        let request = RunRequest(message: "make a change", repoRoot: repo.path, workerId: "model_grok")

        // Before dispatch: no collision — this is exactly what the foreground
        // `--run-id`/`--no-wait` preflight observes before minting/accepting an id.
        XCTAssertFalse(RunCLI.runIdCollision("run_fixed_id", store: store))

        guard case .success(let run) = await svc.run(request, origin: .cli, runId: "run_fixed_id") else {
            return XCTFail("fixture run failed")
        }
        XCTAssertEqual(run.id, "run_fixed_id")

        // After: the same id now collides — a second `--run-id run_fixed_id` (with
        // or without `--no-wait`) must refuse with RUN_ID_IN_USE.
        XCTAssertTrue(RunCLI.runIdCollision("run_fixed_id", store: store))
    }

    // MARK: - Semantic round trip: --no-wait's child persists under the chosen id;
    // `alln run resume <id>` looks up that exact id.

    func testRunStartedUnderAnExplicitIdIsFindableByResumeLookup() async throws {
        let repo = tmp.appendingPathComponent("repo2", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let store = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let svc = fixtureService(repo: repo, store: store)
        let request = RunRequest(message: "make a change", repoRoot: repo.path, workerId: "model_grok")

        // Simulates exactly what the detached child of `alln run --no-wait` does:
        // it is handed a minted id via `--run-id` and calls the normal `service.run`.
        let mintedId = RunService.mintRunId()
        guard case .success(let run) = await svc.run(request, origin: .cli, runId: mintedId) else {
            return XCTFail("fixture run failed")
        }
        XCTAssertEqual(run.id, mintedId)

        // `RunCLI.resume`'s own lookup: `store.loadRaw(runId:) ?? store.load(runId:)`.
        let found = store.loadRaw(runId: mintedId) ?? store.load(runId: mintedId)
        XCTAssertNotNil(found, "alln run resume <id> must find the run --no-wait's child persisted")
        XCTAssertEqual(found?.id, mintedId)
        XCTAssertTrue(found?.status.isTerminal ?? false, "the fixture driver settles synchronously")
    }

    // MARK: - noWaitChildArguments: argv minus --no-wait, plus --run-id when minted

    func testNoWaitChildArgumentsAddsRunIdWhenMinted() {
        let parentArgv = ["run", "fix the bug", "--project", ".", "--no-wait", "--json"]
        let childArgs = RunCLI.noWaitChildArguments(
            parentArgv: parentArgv, runId: "run_minted", explicitRunId: nil)
        XCTAssertEqual(childArgs, ["run", "fix the bug", "--project", ".", "--json", "--run-id", "run_minted"])
        XCTAssertFalse(childArgs.contains("--no-wait"))
    }

    func testNoWaitChildArgumentsLeavesExplicitRunIdAloneNoDuplicate() {
        let parentArgv = ["run", "fix the bug", "--project", ".", "--run-id", "run_explicit", "--no-wait"]
        let childArgs = RunCLI.noWaitChildArguments(
            parentArgv: parentArgv, runId: "run_explicit", explicitRunId: "run_explicit")
        XCTAssertEqual(childArgs, ["run", "fix the bug", "--project", ".", "--run-id", "run_explicit"])
        // Exactly one occurrence of the flag — no duplicate --run-id appended.
        XCTAssertEqual(childArgs.filter { $0 == "--run-id" }.count, 1)
    }

    // MARK: - Structural: RunCLI does not build its own Process() (reuses DetachedDispatch)

    func testRunCLIDoesNotConstructProcessDirectly() throws {
        let here = URL(fileURLWithPath: #filePath)
        let packageRoot = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runCLI = packageRoot.appendingPathComponent("Sources/AllnighterCLI/RunCLI.swift")
        let text = try String(contentsOf: runCLI, encoding: .utf8)
        XCTAssertFalse(text.contains("Process()"), "RunCLI must route --no-wait through DetachedDispatch.launch")
        XCTAssertTrue(text.contains("DetachedDispatch.launch"), "RunCLI must reuse the shared detached-spawn helper")
        XCTAssertTrue(text.contains("DetachedDispatch.childArguments"), "RunCLI must reuse the shared argv filter")
    }

    // MARK: - Fixtures (mirrors SingleRunOwnerInvariantTests' RunService fixture shape)

    private func fixtureService(repo: URL, store: RunStore) -> RunService {
        RunService(
            models: [Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                           driverId: "grok", role: .both)],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: store,
            commandRunner: MockCommandRunner(scripts: ["grok": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(defaultTier: .flagship, allowHealthySubstitutions: true,
                                     tiers: TierMembership(flagship: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            })
    }
}
