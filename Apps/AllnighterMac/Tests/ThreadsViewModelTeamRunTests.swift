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

    private final class PromptCapturingRunner: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var prompts: [String] = []

        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            let prompt: String
            if let index = args.firstIndex(of: "-p"), index + 1 < args.count {
                prompt = args[index + 1]
            } else {
                prompt = stdin ?? args.joined(separator: " ")
            }
            lock.lock()
            prompts.append(prompt)
            lock.unlock()
            return CommandResult(stdout: "Read the referenced file.", exitCode: 0)
        }

        func lastPrompt() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return prompts.last
        }
    }

    private func tempDir() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-repo-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeVM(toolStatuses: [ToolProbeRecord], commandRunner: CommandRunner = StubRunner()) -> ThreadsViewModel {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-tvm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ThreadsViewModel(
            store: ThreadStore(rootDirectory: root),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry,
            models: config.models,
            toolStatuses: toolStatuses,
            runner: WorkerRunner(commandRunner: commandRunner),
            commandRunner: commandRunner,
            projectStore: ProjectStore(rootDirectory: root.appendingPathComponent("projects", isDirectory: true))
        )
    }

    private var buildTeamId: String {
        let teams = BuiltInTeams.teams(in: .code)
        return (teams.first(where: \.isDefaultForLane) ?? teams.first)?.id ?? ""
    }

    private func readyExecutorId(_ ready: [ToolProbeRecord]) -> String? {
        let config = AppConfig.loadConfiguration()
        let readyDrivers = Set(ready.filter { $0.status.isReady }.map(\.driverId))
        return config.models.first {
            $0.enabled && readyDrivers.contains($0.driverId)
            && config.registry.manifest(for: $0)?.kind == .headlessCLI
        }?.id
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

    func testProjectRunDeliversComposerFileReferencesToWorkerPrompt() async throws {
        let repo = URL(fileURLWithPath: tempDir(), isDirectory: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "let selectedValue = 42\n".write(
            to: repo.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )

        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        let capture = PromptCapturingRunner()
        let vm = makeVM(toolStatuses: ready, commandRunner: capture)
        _ = vm.newThread(title: "t", workingDir: repo.path)
        XCTAssertNotNil(vm.selectedThread?.projectId)

        vm.sendRouting(ComposeRouting(
            team: nil,
            to: to,
            effort: .med,
            lane: .code,
            text: "Use the selected file.",
            fileReferences: [FileReferenceInput(path: "Sources/App.swift")]
        ))

        for _ in 0..<300 {
            if capture.lastPrompt() != nil { break }
            try await Task.sleep(nanoseconds: 15_000_000)
        }

        let prompt = try XCTUnwrap(capture.lastPrompt())
        XCTAssertTrue(prompt.contains("Referenced files:"))
        XCTAssertTrue(prompt.contains("Sources/App.swift"))
        XCTAssertTrue(prompt.contains("let selectedValue = 42"))

        let userTurn = try XCTUnwrap(vm.selectedThread?.turns.first { $0.kind == .userMessage })
        XCTAssertEqual(userTurn.fileReferenceRefs.count, 1)
        XCTAssertNotNil(userTurn.contextPacketId)
    }
}
