import XCTest
import AllnighterCore
@testable import AllnighterEngine

// MARK: - Shared harness

/// Serializes async lifecycle tests — XCTest may run test classes in parallel.
private actor AsyncTeamLifecycleTestGate {
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        try await body()
    }
}
private let asyncTeamLifecycleGate = AsyncTeamLifecycleTestGate()

private enum AsyncTeamTestHarness {
    static let planMarkdown = "# Plan\nAsync ok."

    static func testTeam() -> TeamPreset {
        TeamPreset(
            id: "code_test", displayName: "Test", lane: .code, outputKind: .plan, defaultEffort: .low,
            isDefaultForLane: true,
            agentSpecs: [TeamAgentSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true)
    }

    static func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    static func tempRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("async-\(UUID().uuidString)")
    }

    /// Unit tests must not inherit a host agent's `ALLNIGHTER_TEAM_DEPTH` —
    /// a piloted/relay seat sets that and would false-fail every start as nested.
    static var cleanEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ALLNIGHTER_TEAM_DEPTH")
        return env
    }

    static func makeService(
        root: URL,
        mock: MockCommandRunner,
        idempotency: IdempotencyStore? = nil,
        runId: String = "run-async-test"
    ) -> AsyncTeamService {
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let governorDir = root.appendingPathComponent("gov")
        return AsyncTeamService(
            models: [opus()],
            registry: registry,
            teams: [testTeam()],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs")),
            commandRunner: mock,
            governor: TeamGovernor(directory: governorDir, capacity: 2),
            idempotency: idempotency ?? IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
            environment: cleanEnvironment,
            idFactory: { runId }
        )
    }

    static func startRequest(_ prompt: String = "async?", key: String? = nil) -> AsyncTeamStartRequest {
        AsyncTeamStartRequest(
            question: prompt,
            lane: .code,
            teamPresetId: "code_test",
            effort: .low,
            originAgent: "test-agent",
            originConversationId: "conv-1",
            originMessageId: "msg-1",
            idempotencyKey: key
        )
    }
}

// MARK: - TeamStartTests

final class TeamStartTests: XCTestCase {
    func testInvalidTeamFailsPreflightWithoutRunId() async {
        await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock)
            let outcome = await service.start(
                AsyncTeamStartRequest(question: "x", lane: .code, teamPresetId: "missing_team", effort: .low),
                origin: .cli,
                readyModels: [AsyncTeamTestHarness.opus()]
            )
            guard case .failure(let refusal) = outcome else {
                return XCTFail("expected refusal")
            }
            XCTAssertEqual(refusal.code, "DEFAULT_TEAM_INVALID")
            XCTAssertTrue(FileManager.default.contents(atPath: root.appendingPathComponent("Runs").path) == nil
                          || (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Runs").path))?.isEmpty == true)
        }
    }

    func testStartPinsModelOnSingleWorkerMutatingTeam() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let sonnet = Model(
                id: "model_sonnet", displayName: "Sonnet", modelLabel: "sonnet",
                driverId: "claude_code", role: .answerer
            )
            let pinTeam = TeamPreset(
                id: "pin_test", displayName: "Pin", lane: .code, outputKind: .plan,
                mutating: true, executionSourceId: "claude_code", defaultEffort: .med,
                agentSpecs: [
                    TeamAgentSpec(id: "w1", skillId: SkillCatalog.directChatSkillId, purpose: .answer,
                                   preferredModelId: "model_opus")
                ],
                lead: TeamLeadSpec(skillId: SkillCatalog.directChatSkillId, preferredModelId: "model_opus"),
                builtIn: false
            )
            let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown, delay: .milliseconds(200))])
            let service = AsyncTeamService(
                models: [AsyncTeamTestHarness.opus(), sonnet],
                registry: registry,
                teams: [pinTeam],
                config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
                runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs")),
                commandRunner: mock,
                governor: TeamGovernor(directory: root.appendingPathComponent("gov"), capacity: 2),
                idempotency: IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json")),
                environment: AsyncTeamTestHarness.cleanEnvironment,
                idFactory: { "run-pin-1" }
            )
            let ready = [AsyncTeamTestHarness.opus(), sonnet]
            let outcome = await service.start(
                AsyncTeamStartRequest(
                    question: "pin sonnet", lane: .code, teamPresetId: "pin_test", effort: .med,
                    modelId: "model_sonnet", originAgent: "ios:test"
                ),
                origin: .ios,
                readyModels: ready
            )
            guard case .success(let response) = outcome else {
                return XCTFail("expected success")
            }
            let run = try XCTUnwrap(RunStore(rootDirectory: root.appendingPathComponent("Runs")).load(runId: response.runId))
            XCTAssertEqual(run.answers.first?.modelId, "model_sonnet")
            _ = await service.cancel(runId: response.runId)
        }
    }

    func testValidStartReturnsRunIdAndDurableJournalBeforeWorkers() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown, delay: .milliseconds(200))])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: "run-start-1")
            let outcome = await service.start(AsyncTeamTestHarness.startRequest(), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            guard case .success(let response) = outcome else {
                return XCTFail("expected success")
            }
            XCTAssertEqual(response.runId, "run-start-1")
            XCTAssertTrue([RunLifecycle.queued, .running].contains(response.status))
            XCTAssertGreaterThan(response.nextPollAfterMs, 0)
            XCTAssertEqual(
                response.nextActions.first?.command,
                "alln show run-start-1 --stream"
            )
            XCTAssertEqual(
                ContractRegistry.resolveCommandName(from: response.nextActions.first?.command ?? ""),
                "show")

            let runURL = root.appendingPathComponent("Runs/run_run-start-1/run.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: runURL.path), "journal must exist before workers finish")
            let run = try XCTUnwrap(RunStore(rootDirectory: root.appendingPathComponent("Runs")).load(runId: "run-start-1"))
            // RLR-L3: the single-worker `code_test` team is accepted as `queued`
            // and advances to `running` — it never carries fanning_out. (Which of
            // the two the load catches depends on the coordinator handoff timing.)
            XCTAssertTrue([RunStatus.queued, .running].contains(run.status),
                          "expected queued/running, got \(run.status.rawValue)")
            XCTAssertEqual(run.originAgent, "test-agent")
            XCTAssertEqual(run.originConversationId, "conv-1")

            _ = await service.cancel(runId: "run-start-1")
        }
    }

    /// Concurrent Invocation Isolation standing regression invariant:
    /// **`team start` never sweeps.** The only caller of `RunStore.reconcileAll`
    /// is the explicit bare `alln team reconcile`. Plant an identity-dead run
    /// (exactly what a sweep WOULD reap); a full start→terminal lifecycle must
    /// leave it untouched on disk.
    func testTeamStartNeverSweepsReconcileAll() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = RunStore(rootDirectory: root.appendingPathComponent("Runs"))

            let orphan = TeamRun(
                id: "run-planted-orphan", prompt: "p", status: .fanningOut,
                createdAt: Date(),
                repoRoot: "/tmp/repo-a"
            )
            try store.save(orphan, models: [])
            let orphanDir = try store.runDirectory(forRunId: orphan.id)
            try ProcessOwnership.writeOwnerIdentity(
                .init(pid: 2_100_900, pgid: 9_900, startTimeTicks: 1, kind: .detachedRunner),
                in: orphanDir
            )
            XCTAssertTrue(store.wouldReconcile(runId: orphan.id), "fixture must be reapable")

            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: "run-start-nosweep")
            guard case .success = await service.start(
                AsyncTeamTestHarness.startRequest(), origin: .cli,
                readyModels: [AsyncTeamTestHarness.opus()]
            ) else {
                return XCTFail("expected start success")
            }
            // Wait for the started run to settle via journal (status/result path deleted ORS-S03b).
            let storeForWait = RunStore(rootDirectory: root.appendingPathComponent("Runs"))
            for _ in 0..<100 {
                if let r = storeForWait.load(runId: "run-start-nosweep"), r.status.isTerminal { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            // Nothing swept the planted orphan: still raw non-terminal, no endReason.
            let raw = try XCTUnwrap(store.loadRaw(runId: orphan.id))
            XCTAssertFalse(raw.status.isTerminal, "team start must never reconcileAll")
            XCTAssertNil(raw.endReason)

            // Only the explicit bare reconcile (scoped to the orphan's project)
            // sweeps it.
            let reaped = await service.reconcile(runId: nil, scopeRoot: "/tmp/repo-a")
            XCTAssertEqual(reaped.map(\.id), [orphan.id])
        }
    }
}

// MARK: - AsyncTeamTests

final class AsyncTeamTests: XCTestCase {
    /// ORS-S03b: journal settles to terminal; agents read via `alln show`, not team result.
    func testJournalSettlesToTerminalWithEvents() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: "run-result-2")
            _ = await service.start(AsyncTeamTestHarness.startRequest(), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            let store = RunStore(rootDirectory: root.appendingPathComponent("Runs"))
            var run: TeamRun?
            for _ in 0..<50 {
                if let loaded = store.load(runId: "run-result-2"), loaded.status.isTerminal {
                    run = loaded
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let settled = try XCTUnwrap(run)
            XCTAssertEqual(settled.status, .complete)
            XCTAssertEqual(settled.plan, AsyncTeamTestHarness.planMarkdown)

            let journal = RemoteRunEventJournal(rootDirectory: root.appendingPathComponent("Runs"))
            var events: [RunEvent] = []
            for _ in 0..<50 {
                events = try journal.events(after: 0)
                if events.contains(where: { $0.kind == RunEventKind.stageCompleted }) { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            XCTAssertEqual(events.map(\.seq), events.indices.map { Int64($0 + 1) })
            XCTAssertTrue(events.allSatisfy { $0.payload["runId"]?.stringValue == "run-result-2" })
            XCTAssertTrue(events.contains { $0.kind == RunEventKind.runStatusChanged })
            XCTAssertTrue(events.contains { $0.kind == RunEventKind.workerStatusChanged })
            XCTAssertTrue(events.contains { $0.kind == RunEventKind.stageCompleted })
        }
    }

    func testCancelRecordsCancelledHonestly() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let runId = "run-cancel-\(UUID().uuidString)"
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown, delay: .seconds(2))])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: runId)
            guard case .success = await service.start(AsyncTeamTestHarness.startRequest(), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()]) else {
                return XCTFail("expected start to succeed")
            }
            let cancel = await service.cancel(runId: runId)
            XCTAssertEqual(cancel?.status, .cancelled)
            let store = RunStore(rootDirectory: root.appendingPathComponent("Runs"))
            let run = try XCTUnwrap(store.load(runId: runId))
            XCTAssertEqual(run.status, .cancelled)
        }
    }
}

// MARK: - IdempotencyTests

final class IdempotencyTests: XCTestCase {
    func testSameKeyAndPayloadReturnsSameRunId() async {
        await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json"))
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, idempotency: store, runId: "run-idem-1")
            let req = AsyncTeamTestHarness.startRequest("same prompt", key: "key-abc")
            let first = await service.start(req, origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            let second = await service.start(req, origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            guard case .success(let a) = first, case .success(let b) = second else {
                return XCTFail("expected successes")
            }
            XCTAssertEqual(a.runId, b.runId)
            let runs = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Runs").path)) ?? []
            XCTAssertEqual(runs.filter { $0.hasPrefix("run_") }.count, 1)
            _ = await service.cancel(runId: "run-idem-1")
        }
    }

    func testSameKeyDifferentPayloadIsRejected() async {
        await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json"))
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, idempotency: store, runId: "run-idem-2")
            _ = await service.start(AsyncTeamTestHarness.startRequest("first", key: "key-xyz"), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            let second = await service.start(AsyncTeamTestHarness.startRequest("changed", key: "key-xyz"), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            guard case .failure(let refusal) = second else {
                return XCTFail("expected idempotency refusal")
            }
            XCTAssertEqual(refusal.code, "IDEMPOTENCY_CONFLICT")
            XCTAssertFalse(refusal.message.contains("changed"))
            _ = await service.cancel(runId: "run-idem-2")
        }
    }

    /// F5 (Concurrent Invocation Isolation): `record()` used to be an unlocked
    /// load → mutate → save RMW — concurrent callers lost-updated the shared
    /// file. Under the per-file flock, every concurrent record survives.
    func testConcurrentRecordsDoNotLoseEntries() throws {
        let root = AsyncTeamTestHarness.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json"))
        let payload = AsyncTeamCanonicalPayload(from: AsyncTeamTestHarness.startRequest("concurrent"))
        let count = 32
        let failures = NSMutableArray()
        DispatchQueue.concurrentPerform(iterations: count) { i in
            do {
                _ = try store.record(key: "key-\(i)", payload: payload, runId: "run-\(i)")
            } catch {
                failures.add(error)
            }
        }
        XCTAssertEqual(failures.count, 0, "record must not fail under concurrency: \(failures)")
        let text = String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self)
        for i in 0..<count {
            XCTAssertTrue(text.contains("key-\(i)"), "lost update dropped key-\(i)")
        }
        XCTAssertEqual(store.lookup(key: "key-7")?.runId, "run-7")
    }

    /// F5b: simultaneous same-key claims — exactly one caller mints; the rest replay.
    func testConcurrentSameKeyClaimSingleFlights() throws {
        let root = AsyncTeamTestHarness.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json"))
        let payload = AsyncTeamCanonicalPayload(from: AsyncTeamTestHarness.startRequest("same"))
        let lock = NSLock()
        var results: [IdempotencyStore.ClaimResult] = []
        let failures = NSMutableArray()
        DispatchQueue.concurrentPerform(iterations: 16) { i in
            do {
                let result = try store.claim(key: "shared-key", payload: payload, runId: "run-\(i)")
                lock.lock(); results.append(result); lock.unlock()
            } catch {
                failures.add(error)
            }
        }
        XCTAssertEqual(failures.count, 0)
        let claimed = results.filter {
            if case .claimed = $0 { return true }
            return false
        }
        let replayed = results.filter {
            if case .replay = $0 { return true }
            return false
        }
        XCTAssertEqual(claimed.count, 1, "exactly one claim must win: \(results)")
        XCTAssertEqual(replayed.count, 15)
        guard case .claimed(let winner) = claimed.first else {
            return XCTFail("missing claimed winner")
        }
        for case .replay(let entry) in replayed {
            XCTAssertEqual(entry.runId, winner.runId)
            XCTAssertEqual(entry.payloadDigest, winner.payloadDigest)
        }
        XCTAssertEqual(store.lookup(key: "shared-key")?.runId, winner.runId)
    }

    /// F5b: in-process concurrent starts with the same key mint one run only.
    func testConcurrentSameKeyStartsShareOneRun() async {
        await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = IdempotencyStore(fileURL: root.appendingPathComponent("idempotency.json"))
            let mock = MockCommandRunner(scripts: [
                "claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)
            ])
            let counter = LockedCounter()
            let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
            let service = AsyncTeamService(
                models: [AsyncTeamTestHarness.opus()],
                registry: registry,
                teams: [AsyncTeamTestHarness.testTeam()],
                config: ToolConfig(maxConcurrentTeamRuns: 4, maxTeamRunDepth: 1),
                runStore: RunStore(rootDirectory: root.appendingPathComponent("Runs")),
                commandRunner: mock,
                governor: TeamGovernor(directory: root.appendingPathComponent("gov"), capacity: 4),
                idempotency: store,
                environment: AsyncTeamTestHarness.cleanEnvironment,
                idFactory: { "run-concurrent-\(counter.next())" }
            )
            let req = AsyncTeamTestHarness.startRequest("same prompt", key: "key-concurrent")
            async let a = service.start(req, origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            async let b = service.start(req, origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            let first = await a
            let second = await b
            guard case .success(let ra) = first, case .success(let rb) = second else {
                return XCTFail("expected successes: \(first) \(second)")
            }
            XCTAssertEqual(ra.runId, rb.runId)
            let runs = (try? FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent("Runs").path
            )) ?? []
            XCTAssertEqual(runs.filter { $0.hasPrefix("run_") }.count, 1)
            _ = await service.cancel(runId: ra.runId)
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
}
