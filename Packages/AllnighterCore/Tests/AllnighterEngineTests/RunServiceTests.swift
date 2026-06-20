import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class RunServiceTests: XCTestCase {
    func testExecutionRunStreamFinishesAndEmitsTerminalEvents() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let model = Model(
            id: "model_cursor_composer_25",
            displayName: "Cursor Composer",
            modelLabel: "composer-2.5",
            driverId: "cursor_agent",
            role: .both
        )
        // Auto (default route) resolves the worker from the Default-model tiers, so the
        // test's model must be the default tier's default and its source probe ready.
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_cursor_composer_25"]))
        let probe = ToolProbeRecord(driverId: "cursor_agent", status: .ready(version: "1.0"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )
        let request = RunRequest(message: "Say done", repoRoot: repo.path)
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        let eventsTask = Task {
            var events: [RunEvent] = []
            for await event in stream { events.append(event) }
            return events
        }

        let result = await service.run(request, origin: .cli, events: continuation)
        let events = await eventsTask.value

        guard case .success(let run) = result else {
            return XCTFail("run failed: \(result)")
        }
        XCTAssertEqual(run.status, .complete)
        XCTAssertTrue(events.contains { $0.kind == RunEventKind.workerStatusChanged && $0.payload["to"] == .string(WorkerAnswerStatus.done.rawValue) })
        XCTAssertTrue(events.contains { $0.kind == RunEventKind.runStatusChanged && $0.payload["to"] == .string(RunStatus.complete.rawValue) })
    }

    /// SBDS-S03: Auto runs the tier default, but routes around a down CLI to the next
    /// source-ready model on the same tier — without asking.
    func testAutoRoutesAroundADownCLIWithinTheTier() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        // Flagship = [Opus (claude_code, DOWN), ChatGPT (codex, ready)]. Auto must skip
        // the down default and run ChatGPT.
        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let gpt = Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt", driverId: "codex", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_opus", "model_chatgpt"]))
        // Only codex is probe-ready; claude_code has no ready record → Opus is down.
        let probe = ToolProbeRecord(driverId: "codex", status: .ready(version: "1"), lastProbeAt: .distantPast)
        let service = RunService(
            models: [opus, gpt],
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "claude_code", command: "claude"),
                TestSupport.headlessManifest(id: "codex", command: "codex")]),
            commandRunner: MockCommandRunner(scripts: [
                "claude": .init(stdout: "", exitCode: 1),       // would fail if Auto wrongly used it
                "codex": .init(stdout: "Routed.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [probe] }
        )

        let result = await service.run(RunRequest(message: "hi", repoRoot: repo.path), origin: .cli)
        guard case .success(let run) = result else { return XCTFail("run failed: \(result)") }
        XCTAssertEqual(run.workerAnswers.first?.modelId, "model_chatgpt", "Auto routed around the down Opus to ChatGPT")
        XCTAssertEqual(run.status, .complete)
    }

    /// SBDS-S03: when the whole default tier is down, Auto waits (clean failure) rather
    /// than guessing some other model.
    func testAutoWaitsWhenTheWholeTierIsDown() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        let opus = Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both)
        let settings = DefaultModelSettings(
            defaultTier: .flagship, allowHealthySubstitutions: true,
            tiers: TierMembership(flagship: ["model_opus"]))
        let service = RunService(
            models: [opus],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "x", exitCode: 0)]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { settings },
            probeRecords: { [] }   // nothing probe-ready
        )

        let result = await service.run(RunRequest(message: "hi", repoRoot: repo.path), origin: .cli)
        guard case .failure(let err) = result else { return XCTFail("expected Auto to wait, got \(result)") }
        XCTAssertEqual(err.code, "DEFAULT_TEAM_INVALID")
    }
}
