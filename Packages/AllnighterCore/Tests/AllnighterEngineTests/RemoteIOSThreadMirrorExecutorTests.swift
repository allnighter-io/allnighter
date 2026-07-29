import XCTest
import AgentOSTeam
import AllnighterCore
@testable import AllnighterEngine

final class RemoteIOSThreadMirrorExecutorTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_750_500_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-thread-mirror-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testStartRunMirrorsThreadAndSettlesWhenRunCompletes() async throws {
        let runsRoot = root.appendingPathComponent("runs", isDirectory: true)
        let threadStore = ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true))
        let runStore = RunStore(rootDirectory: runsRoot)
        let stub = StubRemoteTeamExecutor(runStore: runStore, now: now)
        let fixedNow = now
        let executor = RemoteIOSThreadMirrorExecutor(
            underlying: stub,
            threadStore: threadStore,
            runStore: runStore,
            idFactory: { "turn_\(UUID().uuidString.prefix(4))" },
            now: { fixedNow }
        )

        let request = AsyncTeamStartRequest(
            question: "Test",
            modelId: "model_cursor",
            threadId: "thread_test",
            originAgent: "ios:device_1",
            idempotencyKey: "remote:req_1"
        )
        let response = try await executor.startRun(request).get()
        XCTAssertEqual(response.runId, "run_mirror_1")

        let mirrored = try XCTUnwrap(threadStore.get("thread_test"))
        XCTAssertEqual(mirrored.title, "Test")
        XCTAssertEqual(mirrored.turns.count, 2)
        XCTAssertEqual(mirrored.turns.last?.status, .running)
        XCTAssertEqual(mirrored.turns.last?.runId, "run_mirror_1")

        await stub.complete(runId: "run_mirror_1", output: "Hello from Mac")

        try await Task.sleep(nanoseconds: 1_500_000_000)

        let settled = try XCTUnwrap(threadStore.get("thread_test"))
        let workerTurn = try XCTUnwrap(settled.turns.last)
        XCTAssertEqual(workerTurn.status, .done)
        XCTAssertEqual(workerTurn.text, "Hello from Mac")
    }
}

private actor StubRemoteTeamExecutor: RemoteTeamCommandExecuting {
    private let runStore: RunStore
    private let now: Date

    init(runStore: RunStore, now: Date) {
        self.runStore = runStore
        self.now = now
    }

    func startRun(_ request: AsyncTeamStartRequest) async -> Result<TeamStartResponse, AsyncTeamStartRefusal> {
        let run = TeamRun(
            id: "run_mirror_1",
            prompt: request.question,
            status: .fanningOut,
            origin: .ios,
            answers: [
                TeamAnswer(memberId: "model_cursor#0", modelId: "model_cursor", role: "answer",
                          result: WorkerRunResult(status: .running))
            ],
            createdAt: now,
            threadId: request.threadId
        )
        _ = try? runStore.save(run, models: [])
        return .success(
            TeamStartResponse(
                runId: run.id,
                status: .running,
                lane: nil,
                teamPresetId: nil,
                teamDisplayName: nil,
                effort: nil,
                acceptedAt: now,
                nextPollAfterMs: 1_000,
                nextActions: []
            )
        )
    }

    func complete(runId: String, output: String) {
        guard var run = runStore.load(runId: runId) else { return }
        run.status = .complete
        run.answers = [
            TeamAnswer(
                memberId: "model_cursor#0",
                modelId: "model_cursor",
                role: "answer",
                result: WorkerRunResult(status: .done, output: output, timing: RunTiming(finishedAt: now))
            )
        ]
        _ = try? runStore.save(run, models: [])
    }

    func stopRun(runId: String) async -> TeamCancelResponse? { nil }
    func stopAllRuns() async -> StopAllResult { StopAllResult(terminated: 0) }
}
