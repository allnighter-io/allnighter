import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// P0 acceptance gate (`docs/phases/Concurrent_Invocation_Isolation.md`):
/// two invocations in two distinct repo roots sharing one support root must
/// be as isolated as two `claude`s — one invocation's aggregate cleanup
/// (`kill --all` / bare `team reconcile`) never reaps or alters the other
/// project's runs, and each run's durable context is its own.
final class ConcurrentInvocationIsolationTests: XCTestCase {

    private static let planMarkdown = "# Plan\nAsync ok."

    private func makeService(
        support: URL,
        runId: String,
        workerDelay: Duration
    ) -> AsyncTeamService {
        let team = TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            agentSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true)
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let mock = MockCommandRunner(scripts: [
            "claude": .init(stdout: Self.planMarkdown, delay: workerDelay)
        ])
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")
        return AsyncTeamService(
            models: [opus],
            registry: registry,
            teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: support.appendingPathComponent("Runs")),
            commandRunner: mock,
            governor: TeamGovernor(directory: support.appendingPathComponent("gov"), capacity: 2),
            idempotency: IdempotencyStore(fileURL: support.appendingPathComponent("idempotency.json")),
            environment: env,
            idFactory: { runId }
        )
    }

    private func startRequest(_ prompt: String, repoRoot: String) -> AsyncTeamStartRequest {
        AsyncTeamStartRequest(
            question: prompt,
            lane: .code,
            teamPresetId: "code_test",
            effort: .low,
            originAgent: "isolation-test",
            repoRoot: repoRoot
        )
    }

    /// The acceptance invariant: mutation isolation (A's cleanup never touches
    /// B's runs) + context isolation (each run's journal is its own request).
    func testTwoProjectInvocationsAreMutationAndContextIsolated() async throws {
        let support = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("isolation-\(UUID().uuidString)", isDirectory: true)
        let repoA = support.appendingPathComponent("repoA", isDirectory: true)
        let repoB = support.appendingPathComponent("repoB", isDirectory: true)
        try FileManager.default.createDirectory(at: repoA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        let store = RunStore(rootDirectory: support.appendingPathComponent("Runs"))
        let surface = ProcessOwnershipSurface(
            runStore: store,
            relayStore: RelayStateStore(rootDirectory: support.appendingPathComponent("Relays")),
            lanesRoot: support.appendingPathComponent("Lanes")
        )

        // A dead-owner orphan inside project B — exactly what a machine-wide
        // reconcile WOULD reap. Project A's sweep must leave it alone.
        let orphanB = TeamRun(
            id: "run-b-orphan", prompt: "b-orphan", status: .fanningOut,
            createdAt: Date(), repoRoot: repoB.path
        )
        try store.save(orphanB, models: [])
        let orphanBDir = try store.runDirectory(forRunId: orphanB.id)
        try ProcessOwnership.writeOwnerIdentity(
            .init(pid: 2_101_000, pgid: 9_910, startTimeTicks: 1, kind: .detachedRunner),
            in: orphanBDir
        )
        XCTAssertTrue(store.wouldReconcile(runId: orphanB.id), "fixture must be reapable")

        // Two live runs, one per project, one shared store, blocking fake
        // workers (no real models, no quota, deterministic).
        let serviceA = makeService(support: support, runId: "run-a-live", workerDelay: .seconds(30))
        let serviceB = makeService(support: support, runId: "run-b-live", workerDelay: .seconds(30))
        guard case .success = await serviceA.start(
            startRequest("project A brief", repoRoot: repoA.path),
            origin: .cli,
            readyModels: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)]
        ) else { return XCTFail("project A start must succeed") }
        guard case .success = await serviceB.start(
            startRequest("project B brief", repoRoot: repoB.path),
            origin: .cli,
            readyModels: [Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)]
        ) else { return XCTFail("project B start must succeed") }

        // Context isolation, part 1: each run's durable journal carries only
        // its own prompt + repo root — no cross-delivery of the other
        // project's brief.
        let liveA = try XCTUnwrap(store.loadRaw(runId: "run-a-live"))
        let liveB = try XCTUnwrap(store.loadRaw(runId: "run-b-live"))
        XCTAssertEqual(liveA.prompt, "project A brief")
        XCTAssertEqual(liveA.repoRoot, repoA.path)
        XCTAssertEqual(liveB.prompt, "project B brief")
        XCTAssertEqual(liveB.repoRoot, repoB.path)
        XCTAssertFalse(liveA.status.isTerminal, "fake worker blocks: A is live")
        XCTAssertFalse(liveB.status.isTerminal, "fake worker blocks: B is live")

        // Snapshot B's journal: nothing project A does may change its facts.
        // (Byte-identity is NOT the invariant — B's own service legitimately
        // progress-saves its own journal. The gate is semantic: A's storm
        // must not reap, kill, stamp, or re-scope B's run.)
        let bBefore = try XCTUnwrap(store.loadRaw(runId: "run-b-live"))

        // --- Project A's aggregate cleanup storm ---

        // Bare `team reconcile` scoped to A: reaps nothing (A has no dead
        // runs) and MUST NOT reap B's dead-owner orphan.
        let reapedByA = await serviceA.reconcile(runId: nil, scopeRoot: repoA.path)
        XCTAssertTrue(reapedByA.isEmpty, "A has no dead runs to reap")
        XCTAssertFalse(
            try XCTUnwrap(store.loadRaw(runId: orphanB.id)).status.isTerminal,
            "bare team reconcile in project A must not reap project B's orphan")

        // `kill --all` scoped to A: kills A's live run only — never B's.
        let killByA = surface.killAll(scopeRoot: repoA.path)
        XCTAssertEqual(Set(killByA.killed.map(\.id)), ["run-a-live"])
        XCTAssertFalse(killByA.killed.contains { $0.id == "run-b-live" })
        XCTAssertEqual(try XCTUnwrap(store.loadRaw(runId: "run-a-live")).endReason, .killed)

        // Mutation isolation: B's run was not reaped, not killed, not
        // stamped, not re-scoped — every fact A's storm could have corrupted
        // is intact.
        let bAfter = try XCTUnwrap(store.loadRaw(runId: "run-b-live"))
        XCTAssertEqual(bAfter.id, bBefore.id)
        XCTAssertEqual(bAfter.createdAt, bBefore.createdAt)
        XCTAssertFalse(bAfter.status.isTerminal, "A's kill --all must not reap or kill B's live run")
        XCTAssertNil(bAfter.endReason, "A's storm must not stamp an endReason on B")
        XCTAssertEqual(bAfter.repoRoot, repoB.path)
        XCTAssertTrue(
            bAfter.answers.allSatisfy { $0.result.status != .cancelled },
            "A's kill --all must not cancel B's workers")

        // Positive control: B's own scope reaps its orphan, and B's context
        // after the storm is still exactly its own request.
        let reapedByB = await serviceB.reconcile(runId: nil, scopeRoot: repoB.path)
        XCTAssertEqual(reapedByB.map(\.id), [orphanB.id])
        XCTAssertEqual(bAfter.prompt, "project B brief")

        _ = await serviceB.cancel(runId: "run-b-live")
    }
}
