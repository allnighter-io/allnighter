import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class CouncilRunCoordinatorTests: XCTestCase {

    private func makeCoordinator(
        scripts: [String: MockCommandRunner.Script]
    ) -> CouncilRunCoordinator {
        let mock = MockCommandRunner(scripts: scripts)
        let runner = WorkerRunner(commandRunner: mock)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "grok", command: "grok"),
            TestSupport.headlessManifest(id: "gemini", command: "gemini")
        ])
        return CouncilRunCoordinator(
            workerRunner: runner,
            registry: registry,
            idFactory: { UUID().uuidString }
        )
    }

    func testFansOutToAllWorkersAndReachesAnswersIn() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "opus answer", exitCode: 0),
            "grok": .init(stdout: "grok answer", exitCode: 0),
            "gemini": .init(stdout: "gemini answer", exitCode: 0)
        ])
        let workers = [
            TestSupport.worker("worker_opus", driverId: "claude_code"),
            TestSupport.worker("worker_grok", driverId: "grok"),
            TestSupport.worker("worker_gemini", driverId: "gemini")
        ]

        let run = await coordinator.fanOut(prompt: "p", workers: workers, runId: "run1")

        XCTAssertEqual(run.status, .answersIn)
        XCTAssertEqual(run.answeredMembers.count, 3)
        XCTAssertEqual(Set(run.members.map(\.workerId)), ["worker_opus", "worker_grok", "worker_gemini"])
    }

    func testRunsInParallel() async {
        // Each worker "takes" 400ms; three in parallel should finish well under
        // the 1.2s serial sum.
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "a", exitCode: 0, delay: .milliseconds(400)),
            "grok": .init(stdout: "b", exitCode: 0, delay: .milliseconds(400)),
            "gemini": .init(stdout: "c", exitCode: 0, delay: .milliseconds(400))
        ])
        let workers = [
            TestSupport.worker("worker_opus", driverId: "claude_code"),
            TestSupport.worker("worker_grok", driverId: "grok"),
            TestSupport.worker("worker_gemini", driverId: "gemini")
        ]

        let start = Date()
        _ = await coordinator.fanOut(prompt: "p", workers: workers)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "fan-out should be parallel, not serial")
    }

    func testFailedWorkerDoesNotBlockRun() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "good", exitCode: 0),
            "grok": .init(stderr: "auth", exitCode: 1),
            "gemini": .init(forcesTimeout: true)
        ])
        let workers = [
            TestSupport.worker("worker_opus", driverId: "claude_code"),
            TestSupport.worker("worker_grok", driverId: "grok"),
            TestSupport.worker("worker_gemini", driverId: "gemini")
        ]

        let run = await coordinator.fanOut(prompt: "p", workers: workers)
        XCTAssertEqual(run.status, .answersIn)
        XCTAssertEqual(run.answeredMembers.count, 1)
        XCTAssertEqual(run.failedMembers.count, 2)
    }

    func testDisabledWorkersExcludedFromPanel() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let workers = [
            TestSupport.worker("worker_opus", driverId: "claude_code"),
            TestSupport.worker("worker_grok", driverId: "grok", enabled: false)
        ]

        let run = await coordinator.fanOut(prompt: "p", workers: workers)
        XCTAssertEqual(run.panel, ["worker_opus"])
        XCTAssertEqual(run.members.count, 1)
    }

    func testEmitsRunAndMemberEvents() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let workers = [TestSupport.worker("worker_opus", driverId: "claude_code")]

        // Collect events concurrently with the run.
        let eventStream = coordinator.events
        let collector = Task { () -> [RunEvent] in
            var events: [RunEvent] = []
            for await event in eventStream {
                events.append(event)
            }
            return events
        }

        _ = await coordinator.fanOut(prompt: "p", workers: workers)
        let events = await collector.value

        let kinds = events.map(\.kind)
        XCTAssertTrue(kinds.contains(RunEventKind.runStatusChanged))
        XCTAssertTrue(kinds.contains(RunEventKind.memberStatusChanged))
        // Monotonic, gap-free sequence numbers.
        XCTAssertEqual(events.map(\.seq), Array(1...Int64(events.count)))
    }

    func testCancellationResolvesCancelled() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "slow", exitCode: 0, delay: .seconds(10))
        ])
        let workers = [TestSupport.worker("worker_opus", driverId: "claude_code")]

        let task = Task { await coordinator.fanOut(prompt: "p", workers: workers) }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let run = await task.value

        XCTAssertEqual(run.status, .cancelled)
    }
}
