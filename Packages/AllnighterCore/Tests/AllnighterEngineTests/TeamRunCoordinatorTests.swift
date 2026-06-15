import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class TeamRunCoordinatorTests: XCTestCase {

    private func makeCoordinator(
        scripts: [String: MockCommandRunner.Script]
    ) -> TeamRunCoordinator {
        let mock = MockCommandRunner(scripts: scripts)
        let runner = WorkerRunner(commandRunner: mock)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
            TestSupport.headlessManifest(id: "grok", command: "grok"),
            TestSupport.headlessManifest(id: "gemini", command: "gemini")
        ])
        return TeamRunCoordinator(
            workerRunner: runner,
            registry: registry,
            idFactory: { UUID().uuidString }
        )
    }

    private func threeWorkers() -> [Model] {
        [
            TestSupport.worker("model_opus", driverId: "claude_code"),
            TestSupport.worker("model_grok", driverId: "grok"),
            TestSupport.worker("model_gemini", driverId: "gemini")
        ]
    }

    func testFansOutToAllSeatsAndReachesAnswersIn() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "opus answer", exitCode: 0),
            "grok": .init(stdout: "grok answer", exitCode: 0),
            "gemini": .init(stdout: "gemini answer", exitCode: 0)
        ])
        let models = threeWorkers()
        let seats = TestSupport.workers(models.map(\.id))

        let run = await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: models, runId: "run1")

        XCTAssertEqual(run.status, .answersIn)
        XCTAssertEqual(run.answeredWorkers.count, 3)
        XCTAssertEqual(Set(run.workerAnswers.map(\.workerId)), ["model_opus#0", "model_grok#0", "model_gemini#0"])
    }

    func testSelfFusionSeatsDoNotCollide() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "an answer", exitCode: 0)])
        let opus = TestSupport.worker("model_opus", driverId: "claude_code")
        let seats = WorkerSpec(modelId: "model_opus", count: 3).expand(startingIndex: 0)

        let run = await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: [opus], runId: "run_sf")
        XCTAssertEqual(run.workerAnswers.count, 3)
        XCTAssertEqual(Set(run.workerAnswers.map(\.workerId)).count, 3)
        XCTAssertTrue(run.workerAnswers.allSatisfy { $0.modelId == "model_opus" })
    }

    func testRunsInParallel() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "a", exitCode: 0, delay: .milliseconds(400)),
            "grok": .init(stdout: "b", exitCode: 0, delay: .milliseconds(400)),
            "gemini": .init(stdout: "c", exitCode: 0, delay: .milliseconds(400))
        ])
        let models = threeWorkers()
        let seats = TestSupport.workers(models.map(\.id))

        let start = Date()
        _ = await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: models)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "fan-out should be parallel, not serial")
    }

    func testFailedSeatDoesNotBlockRun() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "good", exitCode: 0),
            "grok": .init(stderr: "auth", exitCode: 1),
            "gemini": .init(forcesTimeout: true)
        ])
        let models = threeWorkers()
        let seats = TestSupport.workers(models.map(\.id))

        let run = await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: models)
        XCTAssertEqual(run.status, .answersIn)
        XCTAssertEqual(run.answeredWorkers.count, 1)
        XCTAssertEqual(run.failedWorkerAnswers.count, 2)
    }

    func testPanelIsExactlyTheSeatsGiven() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let models = [TestSupport.worker("model_opus", driverId: "claude_code")]
        let seats = TestSupport.workers(["model_opus"])

        let run = await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: models)
        XCTAssertEqual(run.workers.map(\.id), ["model_opus#0"])
        XCTAssertEqual(run.workerAnswers.count, 1)
    }

    func testEmitsRunAndMemberEvents() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let models = [TestSupport.worker("model_opus", driverId: "claude_code")]
        let seats = TestSupport.workers(["model_opus"])

        let eventStream = coordinator.events
        let collector = Task { () -> [RunEvent] in
            var events: [RunEvent] = []
            for await event in eventStream { events.append(event) }
            return events
        }

        _ = await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: models)
        let events = await collector.value

        let kinds = events.map(\.kind)
        XCTAssertTrue(kinds.contains(RunEventKind.runStatusChanged))
        XCTAssertTrue(kinds.contains(RunEventKind.memberStatusChanged))
        // Member events carry workerId.
        let memberEvents = events.filter { $0.kind == RunEventKind.memberStatusChanged }
        XCTAssertTrue(memberEvents.allSatisfy { $0.payload["workerId"]?.stringValue == "model_opus#0" })
        XCTAssertEqual(events.map(\.seq), Array(1...Int64(events.count)))
    }

    func testCancellationResolvesCancelled() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "slow", exitCode: 0, delay: .seconds(10))
        ])
        let models = [TestSupport.worker("model_opus", driverId: "claude_code")]
        let seats = TestSupport.workers(["model_opus"])

        let task = Task { await coordinator.fanOut(prompt: "p", teamWorkers: seats, models: models) }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let run = await task.value

        XCTAssertEqual(run.status, .cancelled)
    }
}
