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
        let service = RunService(
            models: [model],
            registry: DriverRegistry([TestSupport.headlessManifest(id: "cursor_agent", command: "cursor")]),
            commandRunner: MockCommandRunner(scripts: ["cursor": .init(stdout: "Done.", exitCode: 0)]),
            writeLock: RunWriteLockRegistry()
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
}
