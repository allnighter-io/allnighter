import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PairCoordinatorTests: XCTestCase {
    private func makeService(repo: URL, stdout: String) -> RunService {
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        return RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: stdout, exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] })
    }

    func testRunSlicePassesCheckAndLinksRuns() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let service = makeService(repo: repo, stdout: "edited ok")
        let checkRunner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "", exitCode: 0),
        ]))
        let coordinator = PairCoordinator(runService: service, checkRunner: checkRunner)

        let packet = WorkSlicePacket(
            sliceId: "PPT-test",
            intent: "make a change",
            touchAllowlist: ["README.md"],
            check: .init(method: .command, command: "true")
        )

        let result = await coordinator.runSlice(
            packet: packet,
            repoRoot: repo.path,
            projectId: nil,
            executorTeamId: "execution_playbook",
            origin: .cli,
            seats: PairCoordinator.Seats(
                plannerWorkerId: "model_cursor_composer_25",
                executorWorkerId: "model_cursor_composer_25"
            )
        )
        guard case .success(let outcome) = result else { return XCTFail("unexpected \(result)") }
        XCTAssertEqual(outcome.gate, .allowed)
        XCTAssertEqual(outcome.terminal, .passed)
        XCTAssertNotNil(outcome.parentRun?.id)
        XCTAssertNotNil(outcome.childRun?.id)
        XCTAssertEqual(outcome.childRun?.parentRunId, outcome.parentRun?.id)
    }

    func testRunQueueAdvancesPassedSlice() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-queue-\(UUID().uuidString)", isDirectory: true)
        let queueDir = repo.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = WorkSlicePacket(
            sliceId: "Q1",
            intent: "work",
            touchAllowlist: ["a.swift"],
            check: .init(method: .command, command: "true"),
            maxRetries: 1
        )
        try CoreJSON.encode(packet).write(to: queueDir.appendingPathComponent("q1.json"))

        let service = makeService(repo: repo, stdout: "ok")
        let checkRunner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "", exitCode: 0),
        ]))
        let coordinator = PairCoordinator(runService: service, checkRunner: checkRunner)
        var queue = try SliceQueueStore.bootstrapQueue(from: queueDir)
        let store = SliceQueueStore(rootDirectory: queueDir)

        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: store,
            repoRoot: repo.path,
            projectId: nil,
            options: .init(executorTeamId: "execution_playbook"),
            origin: .cli
        )
        XCTAssertEqual(outcome.passed, 1)
        XCTAssertEqual(outcome.escalated, 0)
        XCTAssertEqual(outcome.entries.first?.status, .passed)
    }

    func testRunQueuePlannerTakeoverAfterThreeCheckFailures() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-planner-\(UUID().uuidString)", isDirectory: true)
        let queueDir = repo.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = WorkSlicePacket(
            sliceId: "Q-planner",
            intent: "work",
            touchAllowlist: ["a.swift"],
            check: .init(method: .command, command: "false"),
            maxRetries: 1
        )
        try CoreJSON.encode(packet).write(to: queueDir.appendingPathComponent("q-planner.json"))

        let counting = CountingCommandRunner(passAfter: 4)
        let checkRunner = CheckRunner(commandRunner: counting)
        let service = makeService(repo: repo, stdout: "ok")
        let coordinator = PairCoordinator(runService: service, checkRunner: checkRunner)
        var queue = try SliceQueueStore.bootstrapQueue(from: queueDir)
        let store = SliceQueueStore(rootDirectory: queueDir)

        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: store,
            repoRoot: repo.path,
            projectId: nil,
            options: .init(executorAttemptsBeforePlanner: 3, executorTeamId: "execution_playbook"),
            origin: .cli
        )

        XCTAssertEqual(outcome.passed, 0)
        XCTAssertEqual(outcome.plannerResolved, 1)
        XCTAssertEqual(outcome.escalated, 0)
        XCTAssertEqual(outcome.entries.first?.status, .passed)
        XCTAssertEqual(outcome.entries.first?.resolvedBy, "planner")
        XCTAssertNotNil(outcome.entries.first?.plannerRunId)
        XCTAssertEqual(counting.attempts, 4)
    }

    func testRunQueueEscalatesAfterInfraBackoffBudgetExhausted() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-infra-\(UUID().uuidString)", isDirectory: true)
        let queueDir = repo.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = WorkSlicePacket(
            sliceId: "Q-infra",
            intent: "work",
            touchAllowlist: ["a.swift"],
            check: .init(method: .command, command: "true"),
            maxRetries: 1
        )
        try CoreJSON.encode(packet).write(to: queueDir.appendingPathComponent("q-infra.json"))

        let infraRunner = InfraBackoffMockRunner()
        let service = makeService(repo: repo, stdout: "429 rate limit")
        let checkRunner = CheckRunner(commandRunner: infraRunner)
        let coordinator = PairCoordinator(runService: service, checkRunner: checkRunner)
        var queue = try SliceQueueStore.bootstrapQueue(from: queueDir)
        let store = SliceQueueStore(rootDirectory: queueDir)

        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: store,
            repoRoot: repo.path,
            projectId: nil,
            options: .init(
                maxInfraBackoffRetries: 2,
                infraBackoffGraceSeconds: 0,
                executorTeamId: "execution_playbook"
            ),
            origin: .cli
        )

        XCTAssertEqual(outcome.passed, 0)
        XCTAssertEqual(outcome.escalated, 1)
        XCTAssertEqual(outcome.entries.first?.status, .escalated)
        XCTAssertEqual(outcome.entries.first?.escalatedReason, "infra backoff budget exhausted")
        XCTAssertEqual(infraRunner.attempts, 3)
    }

    func testReconcileStaleRunningResetsDeadChild() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-reconcile-\(UUID().uuidString)", isDirectory: true)
        let queueDir = repo.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = WorkSlicePacket(
            sliceId: "stale",
            intent: "work",
            touchAllowlist: ["a.swift"],
            check: .init(method: .command, command: "true")
        )
        var queue = SliceQueue(entries: [
            SliceQueueEntry(packet: packet, status: .running, childRunId: "dead_child_run")
        ])
        let store = SliceQueueStore(rootDirectory: queueDir)
        try store.save(queue)

        let runStore = RunStore(rootDirectory: repo.appendingPathComponent("runs"))
        let deadRun = TeamRun(
            id: "dead_child_run", prompt: "x", status: .interrupted, origin: .cli, createdAt: Date())
        try runStore.save(deadRun, models: [])

        let coordinator = PairCoordinator(
            runService: makeService(repo: repo, stdout: "ok"),
            checkRunner: CheckRunner(commandRunner: MockCommandRunner(scripts: [:])),
            runStore: runStore
        )
        coordinator.reconcileStaleRunning(&queue, store: store)
        XCTAssertEqual(queue.entries.first?.status, .pending)
        XCTAssertNil(queue.entries.first?.childRunId)
    }
}

/// Always returns infraBackoff-classifying worker output; counts check invocations.
private final class InfraBackoffMockRunner: CommandRunner, @unchecked Sendable {
    private(set) var attempts = 0

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        attempts += 1
        return CommandResult(stdout: "", exitCode: 0)
    }
}

/// Fails the first N-1 `/bin/sh` check invocations, then passes.
private final class CountingCommandRunner: CommandRunner, @unchecked Sendable {
    private(set) var attempts = 0
    private let passAfter: Int

    init(passAfter: Int) {
        self.passAfter = passAfter
    }

    func run(
        command: String,
        args: [String],
        stdin: String?,
        env: [String: String],
        workingDirectory: String?,
        timeout: Duration
    ) async -> CommandResult {
        guard command == "/bin/sh" else {
            return CommandResult(stdout: "", exitCode: 0)
        }
        attempts += 1
        if attempts < passAfter {
            return CommandResult(stdout: "fail \(attempts)", exitCode: 1)
        }
        return CommandResult(stdout: "ok", exitCode: 0)
    }
}
