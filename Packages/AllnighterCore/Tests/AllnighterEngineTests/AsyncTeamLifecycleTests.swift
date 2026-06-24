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
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer)],
            lead: TeamLeadSpec(skillId: "plan_writer_build"),
            builtIn: true)
    }

    static func opus() -> Model {
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
    }

    static func tempRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("async-\(UUID().uuidString)")
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
                workerSpecs: [
                    TeamWorkerSpec(id: "w1", skillId: SkillCatalog.directChatSkillId, purpose: .answer,
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
            XCTAssertEqual(run.workerAnswers.first?.modelId, "model_sonnet")
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
            XCTAssertTrue([AsyncTeamLiveStatus.accepted, .running].contains(response.status))
            XCTAssertGreaterThan(response.nextPollAfterMs, 0)
            XCTAssertEqual(response.nextActions.first?.tool, "team_status")

            let runURL = root.appendingPathComponent("Runs/run_run-start-1/run.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: runURL.path), "journal must exist before workers finish")
            let run = try XCTUnwrap(RunStore(rootDirectory: root.appendingPathComponent("Runs")).load(runId: "run-start-1"))
            XCTAssertEqual(run.status, .fanningOut)
            XCTAssertEqual(run.originAgent, "test-agent")
            XCTAssertEqual(run.originConversationId, "conv-1")

            _ = await service.cancel(runId: "run-start-1")
        }
    }
}

// MARK: - AsyncTeamTests

final class AsyncTeamTests: XCTestCase {
    func testStatusReportsLiveStateWithNextPollAfterMs() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown, delay: .milliseconds(300))])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: "run-status-1")
            _ = await service.start(AsyncTeamTestHarness.startRequest(), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            let status = await service.status(runId: "run-status-1")
            XCTAssertNotNil(status)
            XCTAssertEqual(status?.runId, "run-status-1")
            XCTAssertFalse(status?.status.isTerminal ?? true)
            XCTAssertGreaterThan(status?.nextPollAfterMs ?? 0, 0)
            XCTAssertFalse(status?.workers.isEmpty ?? true)
            _ = await service.cancel(runId: "run-status-1")
        }
    }

    func testResultNotReadyBeforeTerminal() async {
        await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown, delay: .milliseconds(400))])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: "run-result-1")
            _ = await service.start(AsyncTeamTestHarness.startRequest(), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            let early = await service.result(runId: "run-result-1")
            guard case .notReady(let nr) = early else {
                return XCTFail("expected not ready")
            }
            XCTAssertEqual(nr.error.code, "RESULT_NOT_READY")
            XCTAssertGreaterThan(nr.nextPollAfterMs, 0)
            _ = await service.cancel(runId: "run-result-1")
        }
    }

    func testResultReturnsTeamRunJSONAfterCompletion() async throws {
        try await asyncTeamLifecycleGate.run {
            let root = AsyncTeamTestHarness.tempRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let mock = MockCommandRunner(scripts: ["claude": .init(stdout: AsyncTeamTestHarness.planMarkdown)])
            let service = AsyncTeamTestHarness.makeService(root: root, mock: mock, runId: "run-result-2")
            _ = await service.start(AsyncTeamTestHarness.startRequest(), origin: .cli, readyModels: [AsyncTeamTestHarness.opus()])
            for _ in 0..<50 {
                if case .ready = await service.result(runId: "run-result-2") { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let final = await service.result(runId: "run-result-2")
            guard case .ready(let run) = final else {
                return XCTFail("expected ready result")
            }
            XCTAssertEqual(run.status, .complete)
            XCTAssertEqual(run.plan, AsyncTeamTestHarness.planMarkdown)

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
            XCTAssertEqual(refusal.code, "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD")
            XCTAssertFalse(refusal.message.contains("changed"))
            _ = await service.cancel(runId: "run-idem-2")
        }
    }
}
