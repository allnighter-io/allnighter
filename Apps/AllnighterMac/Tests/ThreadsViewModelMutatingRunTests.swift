import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// Unified Run Model: mutating runs take `RunWriteLock` per repo root. These guard
/// the honest refuse path (busy root) and a happy mutating run via `RunService`.
@MainActor
final class ThreadsViewModelMutatingRunTests: XCTestCase {

    private struct StubRunner: CommandRunner {
        func run(command: String, args: [String], stdin: String?, env: [String: String],
                 workingDirectory: String?, timeout: Duration) async -> CommandResult {
            CommandResult(stdout: "Added retry with backoff; ran tests — all green.", exitCode: 0)
        }
    }

    private func tempDir() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-repo-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func makeVM(toolStatuses: [ToolProbeRecord], writeLock: RunWriteLockRegistry) -> ThreadsViewModel {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-tvm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stub = StubRunner()
        return ThreadsViewModel(
            store: ThreadStore(rootDirectory: root),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry, models: config.models, toolStatuses: toolStatuses,
            runner: WorkerRunner(commandRunner: stub), commandRunner: stub, writeLock: writeLock,
            projectStore: ProjectStore(rootDirectory: root.appendingPathComponent("projects", isDirectory: true))
        )
    }

    private func readyExecutorId(_ ready: [ToolProbeRecord]) -> String? {
        let config = AppConfig.loadConfiguration()
        let readyDrivers = Set(ready.filter { $0.status.isReady }.map(\.driverId))
        return config.models.first {
            $0.enabled && readyDrivers.contains($0.driverId)
            && config.registry.manifest(for: $0)?.kind == .headlessCLI
        }?.id
    }

    private func routing(_ to: String, _ text: String, team: String? = nil) -> ComposeRouting {
        ComposeRouting(team: team, to: to, effort: .med, lane: .code, text: text)
    }

    private func firstRunTurn(_ vm: ThreadsViewModel, kind: ThreadTurnKind) async throws -> ThreadTurn? {
        for _ in 0..<300 {
            if let t = vm.selectedThread?.turns.first(where: { $0.kind == kind }), t.status.isTerminal {
                return t
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        return vm.selectedThread?.turns.first { $0.kind == kind }
    }

    func testChatWithoutProjectDoesNotCreateUnboundThread() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let vm = makeVM(toolStatuses: ready, writeLock: RunWriteLockRegistry())
        let to = try XCTUnwrap(readyExecutorId(ready))
        vm.sendRouting(routing(to, "hello without a repo"), createThread: true)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.threads.isEmpty)
        XCTAssertNil(vm.selectedThreadId)
    }

    func testBusyWriteLockRefusesConcurrentMutatingRun() async throws {
        let reg = RunWriteLockRegistry()
        let dir = tempDir()
        let key = RunWriteLock.key(repoRoot: dir)
        let held = await reg.acquire(key)
        XCTAssertTrue(held, "precondition: write lock is held")

        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let vm = makeVM(toolStatuses: ready, writeLock: reg)
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        _ = vm.newThread(title: "t", workingDir: dir)
        XCTAssertNotNil(vm.selectedThread?.projectId)

        vm.sendRouting(routing(to, "edit the repo concurrently"))
        let settled = try await firstRunTurn(vm, kind: .mutatingRun)
        let turn = try XCTUnwrap(settled)
        XCTAssertEqual(turn.status, .failed, "a busy repo root refuses the mutating run")
        XCTAssertTrue(turn.text?.lowercased().contains("editing") == true
                      || turn.text?.lowercased().contains("agent") == true,
                      "honest busy reason")
    }

    func testMutatingRunCompletesWithDurableTeamRun() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        let dir = tempDir()
        let vm = makeVM(toolStatuses: ready, writeLock: RunWriteLockRegistry())
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(routing(to, "add exponential backoff retry"))
        let settled = try await firstRunTurn(vm, kind: .mutatingRun)
        let turn = try XCTUnwrap(settled)
        XCTAssertEqual(turn.status, .done)
        let runId = try XCTUnwrap(turn.runId)
        let run = try XCTUnwrap(vm.teamRun(forRunId: runId))
        XCTAssertFalse(run.workerAnswers.isEmpty)
    }

    func testWriteLockReleasedAfterRunSettles() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready))
        let dir = tempDir()
        let reg = RunWriteLockRegistry()
        let vm = makeVM(toolStatuses: ready, writeLock: reg)
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(routing(to, "first order"))
        _ = try await firstRunTurn(vm, kind: .mutatingRun)
        let heldAfter = await reg.isHeld(RunWriteLock.key(repoRoot: dir))
        XCTAssertFalse(heldAfter, "the write lock must be released once the run settles")
    }
}
