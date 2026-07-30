import XCTest
import AllnighterCore
@testable import AllnighterEngine
@testable import AllnighterCLI

/// AVQ-S04 — `alln run --read-only --model` lock policy (not a team, not FS isolation).
final class AVQReadOnlyFlagTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-avq-s04-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func readyModel(_ id: String = "model_grok") -> Model {
        Model(id: id, displayName: "Grok", modelLabel: "grok", driverId: "grok", role: .both)
    }

    private func makeService(models: [Model]? = nil) -> RunService {
        let m = models ?? [readyModel()]
        return RunService(
            models: m,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(UUID().uuidString)")),
            commandRunner: MockCommandRunner(scripts: [
                "grok": .init(stdout: "# Answer\nok", exitCode: 0)
            ]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: m.map(\.id)))
            },
            probeRecords: {
                m.map { ToolProbeRecord(driverId: $0.driverId, status: .ready(version: "1"), lastProbeAt: .distantPast) }
            }
        )
    }

    // MARK: - Dry-run contract

    func testReadOnlyDryRunWritePolicyAndNoTicket() async throws {
        let repo = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let service = makeService()
        let dry = await service.dryRun(
            RunRequest(
                message: "Review this doc.",
                repoRoot: repo.path,
                pinnedModelId: "model_grok",
                readOnly: true
            ),
            readyModels: [readyModel()]
        )
        XCTAssertEqual(dry.writePolicy, RunWritePolicy.readOnly.rawValue)
        XCTAssertEqual(dry.effects.repoWrite, false)
        XCTAssertTrue(dry.canStart)
        // writeLockHeld is nil when takesWriteLock is false (no probe / no ticket).
        XCTAssertNil(dry.writeLockHeld)
    }

    func testNoCommitStillMutating() async throws {
        let repo = tmp.appendingPathComponent("repo-nc")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let service = makeService()
        let dry = await service.dryRun(
            RunRequest(
                message: "build something",
                repoRoot: repo.path,
                pinnedModelId: "model_grok",
                noCommit: true
            ),
            readyModels: [readyModel()]
        )
        XCTAssertEqual(dry.writePolicy, RunWritePolicy.mutating.rawValue)
        XCTAssertEqual(dry.effects.repoWrite, true)
    }

    func testReadOnlyDoesNotQueueBehindHeldLock() async throws {
        let repo = tmp.appendingPathComponent("repo-held")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let registry = RunWriteLockRegistry()
        let key = RunWriteLock.key(repoRoot: repo.path)
        let token = await registry.acquire(key)
        XCTAssertNotNil(token)

        let service = RunService(
            models: [readyModel()],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "grok", command: "grok")]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs-held")),
            commandRunner: MockCommandRunner(scripts: [
                "grok": .init(stdout: "# Answer\nparallel ok", exitCode: 0)
            ]),
            writeLock: registry,
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: ["model_grok"]))
            },
            probeRecords: {
                [ToolProbeRecord(driverId: "grok", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )

        let result = await service.run(
            RunRequest(
                message: "Review this doc.",
                repoRoot: repo.path,
                pinnedModelId: "model_grok",
                readOnly: true
            ),
            origin: .cli,
            runId: "readonly-parallel"
        )
        guard case .success(let run) = result else {
            return XCTFail("read-only run failed under held lock: \(result)")
        }
        XCTAssertFalse(run.mutating)
        XCTAssertNil(run.blocker, "must not queue for write lock")
        XCTAssertTrue(run.status.isTerminal || run.status == .running || run.status == .done)

        await registry.release(key, token: token!)
    }

    // MARK: - Resolver unit

    func testResolverForcesReadOnlyWritePolicy() {
        let input = RunInvocationInput(
            message: "review",
            projectRoot: "/tmp/repo",
            flagMode: .dryRun,
            flags: .init(pinnedModelId: "model_grok", readOnly: true)
        )
        let model = readyModel()
        let resolved = RunInvocationResolver.resolve(
            input,
            context: RunInvocationResolveContext(
                models: [model],
                teams: TeamCatalog.all,
                readyModels: [model],
                readyModelIds: [model.id],
                defaultSettings: DefaultModelSettings(
                    defaultTier: .frontier, allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: [model.id])),
                writeLockHeld: true,
                governorAvailable: true,
                governorBlockedReason: nil
            )
        )
        XCTAssertEqual(resolved.writePolicy, .readOnly)
        XCTAssertFalse(resolved.takesWriteLock)
        XCTAssertNil(resolved.writeLockHeld, "lock probe skipped when not taking lock")
        XCTAssertTrue(resolved.canStart)
        XCTAssertTrue(
            resolved.warnings.contains { $0.contains("observation only") },
            "should note held lock is observation only: \(resolved.warnings)"
        )
    }

    // MARK: - CLI flag constraints

    func testReadOnlyRequiresModelConstraint() {
        let err = CLIUsage.validateFlagConstraints(
            args: ["--read-only", "--json", "hi"],
            commandName: "run"
        )
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("read-only") == true)
        XCTAssertTrue(err?.message.contains("model") == true)
    }

    func testReadOnlyMutexTeam() {
        let err = CLIUsage.validateFlagConstraints(
            args: ["--read-only", "--model", "model_grok", "--team", "code_plan", "hi"],
            commandName: "run"
        )
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
    }

    func testReadOnlyMutexNoCommit() {
        let err = CLIUsage.validateFlagConstraints(
            args: ["--read-only", "--model", "model_grok", "--no-commit", "hi"],
            commandName: "run"
        )
        XCTAssertNotNil(err)
        XCTAssertTrue(err?.message.contains("mutually exclusive") == true)
    }

    func testReadOnlyAllowsDryRunAndJson() {
        let err = CLIUsage.validateFlagConstraints(
            args: ["--read-only", "--model", "model_grok", "--dry-run", "--json", "hi"],
            commandName: "run"
        )
        XCTAssertNil(err)
    }

    func testContractRegistersReadOnlyFlag() {
        let run = ContractRegistry.milestone1.commands.first { $0.name == "run" }
        XCTAssertNotNil(run?.flags.first { $0.name == "read-only" })
        XCTAssertTrue(run?.mutuallyExclusiveFlags.contains(where: { $0.contains("read-only") && $0.contains("team") }) == true)
        XCTAssertTrue(run?.flagConstraints.contains(where: {
            $0.kind == .requires && $0.subject == "read-only" && $0.peers.contains("model")
        }) == true)
    }
}
