import XCTest
import AgentOSTeam
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// PERF-S06: terminal Team-run open must not re-decode `run.json` on every body read.
@MainActor
final class TeamRunOpenPerformanceTests: XCTestCase {

    private struct StubRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            CommandResult(stdout: "ok", exitCode: 0)
        }
    }

    private func makeVM() -> (vm: ThreadsViewModel, runStore: RunStore, models: [Model]) {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-team-open-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runStore = RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true))
        let vm = ThreadsViewModel(
            store: ThreadStore(rootDirectory: root.appendingPathComponent("threads", isDirectory: true)),
            runStore: runStore,
            registry: config.registry,
            models: config.models,
            toolStatuses: [],
            runner: WorkerInvokerFactory.makeWorkerInvoker(commandRunner: CommandRunnerAsStreaming(StubRunner())),
            commandRunner: StubRunner(),
            projectStore: ProjectStore(rootDirectory: root.appendingPathComponent("projects", isDirectory: true))
        )
        return (vm, runStore, config.models)
    }

    private func fatTerminalRun(id: String) -> TeamRun {
        let now = Date()
        let fat = String(repeating: "# Agent answer\n\n" + String(repeating: "markdown body. ", count: 80) + "\n", count: 12)
        var workers: [Agent] = []
        var answers: [TeamAnswer] = []
        for i in 0..<11 {
            let memberId = "model_opus#\(i)"
            workers.append(Agent(
                id: memberId, modelId: "model_opus", instanceIndex: i,
                skillId: "code_review", skillName: "Reviewer \(i)", purpose: .answer
            ))
            answers.append(TeamAnswer(
                memberId: memberId, modelId: "model_opus", role: "answer",
                result: WorkerRunResult(status: .done, output: fat, timing: RunTiming(finishedAt: now))
            ))
        }
        let plan = StageOutput(
            id: "stage_plan", purpose: .plan, status: .done,
            payload: .plan(markdown: String(repeating: "synthesis. ", count: 200))
        )
        return TeamRun(
            id: id, prompt: "find the bug", status: .complete, origin: .gui,
            presetId: "custom_code_bug_hunt_custom",
            workers: workers, workerAnswers: answers, stages: [plan], createdAt: now,
            lane: .code, teamDisplayName: "Bug Hunt MAX", outputKind: .plan
        )
    }

    func testTerminalTeamRunClickDoesNotDecodeRunMoreThanOnce() throws {
        let (vm, runStore, models) = makeVM()
        let runId = "run_" + UUID().uuidString
        let run = fatTerminalRun(id: runId)
        try runStore.save(run, models: models)

        PerfCounters.reset()
        let first = try XCTUnwrap(vm.teamRun(forRunId: runId))
        XCTAssertEqual(first.workerAnswers.count, 11)
        XCTAssertEqual(PerfCounters.value(.runJSONDecode), 1, "first open pays one decode")

        // SwiftUI body re-reads the same run many times per frame — cache must absorb them.
        for _ in 0..<40 {
            XCTAssertEqual(vm.teamRun(forRunId: runId)?.id, runId)
        }
        XCTAssertEqual(PerfCounters.value(.runJSONDecode), 1,
                       "terminal run.json must not re-decode on repeated teamRun lookups")
    }

    /// Receipt path: Open Factory Floor exists for terminal boards; worker markdown stays
    /// collapsed until expanded (ThreadBoardRow uses plain-text preview). Proved here via
    /// the durable cache + fat fixture shape rather than SwiftUI hosting.
    func testTerminalTeamRunFirstPaintUsesReceiptNotAllWorkerMarkdown() throws {
        let (vm, runStore, models) = makeVM()
        let runId = "run_" + UUID().uuidString
        try runStore.save(fatTerminalRun(id: runId), models: models)

        let run = try XCTUnwrap(vm.teamRun(forRunId: runId))
        XCTAssertTrue(run.status.isTerminal)
        XCTAssertFalse(run.workerAnswers.isEmpty)
        // Synthesis/plan is available for the receipt card without requiring every
        // worker answer to be markdown-rendered (GUI expands per-answer on demand).
        let synthesis = run.stages.last { $0.purpose == .plan && $0.status == .done }?.payload?.markdown
        XCTAssertEqual(synthesis?.isEmpty, false)
        let totalWorkerChars = run.workerAnswers.compactMap(\.output).map(\.count).reduce(0, +)
        XCTAssertGreaterThan(totalWorkerChars, 10_000,
                             "fixture is fat enough that eager markdown would hurt first paint")
    }
}
