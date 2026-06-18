import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterMac

/// CR4d: Execute hands the work to an executor CLI in the repo. These guard the
/// INVIOLABLE execute-lane safety at the integration layer (a busy folder refuses a
/// concurrent order — never two agents in one repo) and the honest no-run paths
/// (missing dir), plus the happy path (dispatch settles + records a durable return).
@MainActor
final class ThreadsViewModelDispatchTests: XCTestCase {

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

    private func makeVM(toolStatuses: [ToolProbeRecord], laneRegistry: ExecutionLaneRegistry) -> ThreadsViewModel {
        let config = AppConfig.loadConfiguration()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-tvm-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return ThreadsViewModel(
            store: ThreadStore(rootDirectory: root),
            runStore: RunStore(rootDirectory: root.appendingPathComponent("runs", isDirectory: true)),
            registry: config.registry, models: config.models, toolStatuses: toolStatuses,
            runner: WorkerRunner(commandRunner: StubRunner()), laneRegistry: laneRegistry
        )
    }

    /// A ready headless model the Dispatcher will actually invoke.
    private func readyExecutorId(_ ready: [ToolProbeRecord]) -> String? {
        let config = AppConfig.loadConfiguration()
        let readyDrivers = Set(ready.filter { $0.status.isReady }.map(\.driverId))
        return config.models.first {
            $0.enabled && readyDrivers.contains($0.driverId)
            && config.registry.manifest(for: $0)?.kind == .headlessCLI
        }?.id
    }

    private func exec(_ to: String, _ text: String) -> ComposeRouting {
        ComposeRouting(mode: .exec, to: to, effort: .med, lane: .code, team: "", text: text)
    }

    private func firstDispatchTurn(_ vm: ThreadsViewModel) async throws -> ThreadTurn? {
        for _ in 0..<300 {
            if let t = vm.selectedThread?.turns.first(where: { $0.kind == .dispatch }), t.status.isTerminal {
                return t
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        return vm.selectedThread?.turns.first { $0.kind == .dispatch }
    }

    func testExecuteWithoutWorkingDirIsHonestlyRefused() {
        let vm = makeVM(toolStatuses: [], laneRegistry: ExecutionLaneRegistry())
        _ = vm.newThread(title: "t")   // no working dir
        let to = AppConfig.loadConfiguration().models.first?.id ?? "x"
        vm.sendRouting(exec(to, "do the thing"))   // synchronous refusal

        let turn = vm.selectedThread?.turns.first { $0.kind == .dispatch }
        XCTAssertEqual(turn?.status, .failed)
        XCTAssertNil(turn?.runId, "a refused order never ran")
        XCTAssertTrue((turn?.text ?? "").lowercased().contains("working directory"),
                      "must say why it refused")
    }

    /// THE safety law at the integration layer: a folder with an Execute already
    /// running REFUSES a second order — it is never run concurrently.
    func testBusyExecutionLaneRefusesConcurrentExecute() async throws {
        let reg = ExecutionLaneRegistry()
        let dir = tempDir()
        let held = await reg.acquire(ExecutionLane.key(workingDirectory: dir))
        XCTAssertTrue(held, "precondition: lane is occupied by an in-flight order")

        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let vm = makeVM(toolStatuses: ready, laneRegistry: reg)
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(exec(to, "edit the repo concurrently"))
        let settled = try await firstDispatchTurn(vm)
        let turn = try XCTUnwrap(settled)
        XCTAssertEqual(turn.status, .failed, "a busy execution lane refuses the order")
        XCTAssertNil(turn.runId, "the refused order never ran")
        XCTAssertTrue(turn.text?.lowercased().contains("busy") == true, "honest busy reason")
    }

    func testExecuteRunsAndRecordsADurableReturn() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready), "need a ready headless executor")
        let dir = tempDir()
        let vm = makeVM(toolStatuses: ready, laneRegistry: ExecutionLaneRegistry())
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(exec(to, "add exponential backoff retry"))
        let settled = try await firstDispatchTurn(vm)
        let turn = try XCTUnwrap(settled)
        XCTAssertEqual(turn.status, .done)
        let runId = try XCTUnwrap(turn.runId)
        let ret = try XCTUnwrap(vm.executionReturn(runId: runId, stageId: turn.stageId),
                                "the dispatch turn must reference a durable ExecutionReturn")
        XCTAssertEqual(ret.status, .done)
        XCTAssertEqual(ret.workingDirectory, dir, "the executor ran in the chosen repo")
    }

    /// After a run settles, the lane is free again — the next order is not blocked.
    func testLaneIsReleasedAfterDispatchSettles() async throws {
        let ready = GUIFixture.seededToolStatuses(for: AppConfig.loadConfiguration().models, now: Date(), scenario: "thread-ready")
        let to = try XCTUnwrap(readyExecutorId(ready))
        let dir = tempDir()
        let reg = ExecutionLaneRegistry()
        let vm = makeVM(toolStatuses: ready, laneRegistry: reg)
        _ = vm.newThread(title: "t", workingDir: dir)

        vm.sendRouting(exec(to, "first order"))
        _ = try await firstDispatchTurn(vm)
        let busyAfter = await reg.isBusy(ExecutionLane.key(workingDirectory: dir))
        XCTAssertFalse(busyAfter, "the lane must be released once the order settles")
    }
}
