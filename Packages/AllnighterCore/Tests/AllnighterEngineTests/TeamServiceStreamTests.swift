import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Proves `TeamService.run(events:)` emits NDJSON events LIVE — `teamRunStarted`
/// and `workerStarted` arrive while a worker is still running, before the run
/// settles (not a post-run batch).
final class TeamServiceStreamTests: XCTestCase {

    /// First call (the worker) blocks until released; later calls (the plan)
    /// return the combined analysis+plan output immediately.
    final class GatedRunner: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let started: AsyncStream<Void>
        private let startedCont: AsyncStream<Void>.Continuation
        private let release: AsyncStream<Void>
        private let releaseCont: AsyncStream<Void>.Continuation
        let planOutput: String
        init(planOutput: String) {
            (started, startedCont) = AsyncStream.makeStream()
            (release, releaseCont) = AsyncStream.makeStream()
            self.planOutput = planOutput
        }
        func releaseWorker() { releaseCont.yield(()); releaseCont.finish() }
        func run(command: String, args: [String], stdin: String?, env: [String: String], workingDirectory: String?, timeout: Duration) async -> CommandResult {
            let n = lock.withLock { calls += 1; return calls }
            if n == 1 {
                startedCont.yield(()); startedCont.finish()
                for await _ in release { break }   // block until the test releases
                return CommandResult(stdout: "first principles: use an actor", exitCode: 0)
            }
            return CommandResult(stdout: planOutput, exitCode: 0)
        }
    }

    actor Collected {
        private var names: [String] = []
        func add(_ s: String) { names.append(s) }
        func all() -> [String] { names }
        func contains(_ s: String) -> Bool { names.contains(s) }
    }

    private let combined = """
    ```json
    {"consensus":[{"statement":"actor","sourceWorkerIds":["model_opus#0"]}],"contradictions":[],"partialCoverage":[],"uniqueInsights":[],"blindSpots":[],"failedWorkers":[]}
    ```
    ===PLAN===
    # Plan
    Use an actor.
    """

    func testStreamEmitsEventsBeforeCompletion() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stream-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")])
        let team = TeamPreset(
            id: "build_test", displayName: "Test", lane: .build, outputKind: .plan, defaultEffort: .low, isDefaultForLane: true,
            workerSpecs: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", purpose: .answer, minEffort: .low)],
            synthesisPolicyByEffort: [.low: TeamSynthesisPolicy(outputKind: .plan, planWriterSkillId: "plan_writer_build")],
            builtIn: true)
        let gated = GatedRunner(planOutput: combined)
        let service = TeamService(
            models: [opus], registry: registry, teams: [team],
            config: ToolConfig(maxConcurrentTeamRuns: 2, maxTeamRunDepth: 1),
            runStore: RunStore(rootDirectory: tmp), commandRunner: gated,
            governor: TeamGovernor(directory: tmp.appendingPathComponent("gov"), capacity: 2))

        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let collected = Collected()
        let consumer = Task {
            var mapper = NDJSONStreamProjector.LiveMapper()
            for await event in stream {
                guard let line = mapper.line(for: event),
                      let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let name = obj["event"] as? String else { continue }
                await collected.add(name)
            }
        }
        let runTask = Task { await service.run(TeamRequest(question: "actor or queue?", lane: .build, teamPresetId: "build_test", effort: .low), origin: .cli, events: continuation) }

        // Worker is now running and blocked.
        for await _ in gated.started { break }
        try await waitUntil { await collected.contains("workerStarted") }

        let midRun = await collected.all()
        XCTAssertTrue(midRun.contains("teamRunStarted"), "teamRunStarted must arrive live")
        XCTAssertTrue(midRun.contains("workerStarted"), "workerStarted must arrive live")
        XCTAssertFalse(midRun.contains("teamRunCompleted"), "completion must NOT arrive while the worker is blocked")

        gated.releaseWorker()
        _ = await runTask.value
        await consumer.value

        let final = await collected.all()
        XCTAssertEqual(final.last, "teamRunCompleted", "terminal event is last")
        XCTAssertTrue(final.contains("workerAnswered"))
        XCTAssertTrue(final.contains("planWritten"))
    }

    private func waitUntil(_ cond: @escaping () async -> Bool, timeoutMs: Int = 3000) async throws {
        let start = Date()
        while await cond() == false {
            if Date().timeIntervalSince(start) > Double(timeoutMs) / 1000 { return XCTFail("timed out waiting for condition") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
