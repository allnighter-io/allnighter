import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PairCoordinatorTests: XCTestCase {
    private func makeService(repo: URL, stdout: String) -> RunService {
        let model = Model(
            id: "model_cursor_composer_25", displayName: "Cursor Composer",
            modelLabel: "composer-2.5", driverId: "cursor_agent", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        return RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: stdout, exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] })
    }

    func testRunSlicePassesCheckAndLinksRuns() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let service = makeService(repo: repo, stdout: "edited ok")
        let checkRunner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "", exitCode: 0),
        ]))
        let coordinator = PairCoordinator(runService: service, checkRunner: checkRunner)

        let packet = WorkSlicePacket(
            sliceId: "PPT-test",
            intent: "make a change",
            touchAllowlist: ["README.md"],
            check: .init(method: .command, command: "true")
        )

        let result = await coordinator.runSlice(
            packet: packet,
            repoRoot: repo.path,
            projectId: nil,
            executorTeamId: "execution_playbook",
            origin: .cli,
            seats: PairCoordinator.Seats(
                plannerWorkerId: "model_cursor_composer_25",
                executorWorkerId: "model_cursor_composer_25"
            )
        )
        guard case .success(let outcome) = result else { return XCTFail("unexpected \(result)") }
        XCTAssertEqual(outcome.gate, .allowed)
        XCTAssertEqual(outcome.terminal, .passed)
        XCTAssertNotNil(outcome.parentRun?.id)
        XCTAssertNotNil(outcome.childRun?.id)
        XCTAssertEqual(outcome.childRun?.parentRunId, outcome.parentRun?.id)
    }

    func testRunQueueAdvancesPassedSlice() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("pair-queue-\(UUID().uuidString)", isDirectory: true)
        let queueDir = repo.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = WorkSlicePacket(
            sliceId: "Q1",
            intent: "work",
            touchAllowlist: ["a.swift"],
            check: .init(method: .command, command: "true"),
            maxRetries: 1
        )
        try CoreJSON.encode(packet).write(to: queueDir.appendingPathComponent("q1.json"))

        let service = makeService(repo: repo, stdout: "ok")
        let checkRunner = CheckRunner(commandRunner: MockCommandRunner(scripts: [
            "/bin/sh": .init(stdout: "", exitCode: 0),
        ]))
        let coordinator = PairCoordinator(runService: service, checkRunner: checkRunner)
        var queue = try SliceQueueStore.bootstrapQueue(from: queueDir)
        let store = SliceQueueStore(rootDirectory: queueDir)

        let outcome = await coordinator.runQueue(
            queue: &queue,
            store: store,
            repoRoot: repo.path,
            projectId: nil,
            options: .init(executorTeamId: "execution_playbook"),
            origin: .cli
        )
        XCTAssertEqual(outcome.passed, 1)
        XCTAssertEqual(outcome.escalated, 0)
        XCTAssertEqual(outcome.entries.first?.status, .passed)
    }
}
