import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Unified Run Model: answer-team runs land a board turn referencing a durable
/// `TeamRun`. An unresolvable team lands an honest failed board — never a faked one.
@MainActor
final class ThreadsViewModelTeamRunTests: XCTestCase {

    private struct StubRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            CommandResult(stdout: "Token bucket — allow bursts, hold the average.", exitCode: 0)
        }
    }

    private func tempDir() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-repo-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeVM(toolStatuses: [ToolProbeRecord]) -> ThreadsViewModel {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-tvm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stub = StubRunner()
        return ThreadsViewModel(
            store: ThreadStore(rootDirectory: root),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            toolStatuses: toolStatuses,
            runner: WorkerRunner(commandRunner: stub),
            commandRunner: stub
        )
    }

    private var buildTeamId: String {
        let teams = BuiltInTeams.teams(in: .code)
        return (teams.first(where: \.isDefaultForLane) ?? teams.first)?.id ?? ""
    }

    func testUnresolvableTeamLandsHonestFailedBoard() async throws {
        let vm = makeVM(toolStatuses: [])
        _ = vm.newThread(title: "t", workingDir: tempDir())
        vm.sendRouting(ComposeRouting(team: buildTeamId, to: "", effort: .med,
                                      lane: .code, text: "rate limit?"))

        for _ in 0..<300 {
            if let b = vm.selectedThread?.turns.first(where: { $0.kind == .teamRun }), b.status.isTerminal { break }
            try await Task.sleep(nanoseconds: 15_000_000)
        }

        let board = vm.selectedThread?.turns.first { $0.kind == .teamRun }
        XCTAssertNotNil(board, "a team run must always record a board turn, even when it can't run")
        XCTAssertEqual(board?.status, .failed)
        XCTAssertNil(board?.runId, "a team that never ran has no durable run")
        XCTAssertFalse((board?.text ?? "").isEmpty, "the failed board must carry the honest block reason")
    }

    func testAnswerTeamRunsAndBoardReferencesDurableRun() async throws {
        let config = AppConfig.loadConfiguration()
        let ready = GUIFixture.seededToolStatuses(for: config.models, now: Date(), scenario: "thread-ready")
        let vm = makeVM(toolStatuses: ready)
        try XCTSkipIf(vm.readyModels.isEmpty, "default config has no ready models")

        guard let preset = BuiltInTeams.team(buildTeamId) else { return XCTFail("no build team") }
        let resolved = TeamResolver.resolve(team: preset, requestLane: .code,
                                            requestEffort: .med, readyModels: vm.readyModels)
        try XCTSkipUnless(resolved.isRunnable, "default build team can't form on this bench: \(resolved.blockReason ?? "")")

        _ = vm.newThread(title: "t", workingDir: tempDir())
        vm.sendRouting(ComposeRouting(team: buildTeamId, to: "", effort: .med,
                                      lane: .code, text: "rate limit the public API"))

        let optimistic = vm.selectedThread?.turns.first { $0.kind == .teamRun }
        let runId = try XCTUnwrap(optimistic?.runId, "running board turn must reference its run")
        XCTAssertEqual(optimistic?.status, .running)

        for _ in 0..<300 {
            if let b = vm.selectedThread?.turns.first(where: { $0.kind == .teamRun }), b.status.isTerminal { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let board = vm.selectedThread?.turns.first { $0.kind == .teamRun }
        XCTAssertEqual(board?.status, .done, "a completed run settles the board turn to done")
        let run = try XCTUnwrap(vm.teamRun(forRunId: runId), "the board must load a durable TeamRun by runId")
        XCTAssertFalse(run.workerAnswers.isEmpty)
        XCTAssertTrue(run.workerAnswers.contains { $0.status == .done || $0.output != nil },
                      "the stubbed bench produces answers")
    }
}
