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

    private func threeWorkers() -> [Worker] {
        [
            TestSupport.worker("worker_opus", driverId: "claude_code"),
            TestSupport.worker("worker_grok", driverId: "grok"),
            TestSupport.worker("worker_gemini", driverId: "gemini")
        ]
    }

    func testFansOutToAllSeatsAndReachesAnswersIn() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "opus answer", exitCode: 0),
            "grok": .init(stdout: "grok answer", exitCode: 0),
            "gemini": .init(stdout: "gemini answer", exitCode: 0)
        ])
        let workers = threeWorkers()
        let seats = TestSupport.seats(workers.map(\.id))

        let run = await coordinator.fanOut(prompt: "p", seats: seats, workers: workers, runId: "run1")

        XCTAssertEqual(run.status, .answersIn)
        XCTAssertEqual(run.answeredMembers.count, 3)
        XCTAssertEqual(Set(run.members.map(\.seatId)), ["worker_opus#0", "worker_grok#0", "worker_gemini#0"])
    }

    func testSelfFusionSeatsDoNotCollide() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "an answer", exitCode: 0)])
        let opus = TestSupport.worker("worker_opus", driverId: "claude_code")
        let seats = PanelSeatSpec(workerId: "worker_opus", count: 3).expand(startingIndex: 0)

        let run = await coordinator.fanOut(prompt: "p", seats: seats, workers: [opus], runId: "run_sf")
        XCTAssertEqual(run.members.count, 3)
        XCTAssertEqual(Set(run.members.map(\.seatId)).count, 3)
        XCTAssertTrue(run.members.allSatisfy { $0.workerId == "worker_opus" })
    }

    func testRunsInParallel() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "a", exitCode: 0, delay: .milliseconds(400)),
            "grok": .init(stdout: "b", exitCode: 0, delay: .milliseconds(400)),
            "gemini": .init(stdout: "c", exitCode: 0, delay: .milliseconds(400))
        ])
        let workers = threeWorkers()
        let seats = TestSupport.seats(workers.map(\.id))

        let start = Date()
        _ = await coordinator.fanOut(prompt: "p", seats: seats, workers: workers)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "fan-out should be parallel, not serial")
    }

    func testFailedSeatDoesNotBlockRun() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "good", exitCode: 0),
            "grok": .init(stderr: "auth", exitCode: 1),
            "gemini": .init(forcesTimeout: true)
        ])
        let workers = threeWorkers()
        let seats = TestSupport.seats(workers.map(\.id))

        let run = await coordinator.fanOut(prompt: "p", seats: seats, workers: workers)
        XCTAssertEqual(run.status, .answersIn)
        XCTAssertEqual(run.answeredMembers.count, 1)
        XCTAssertEqual(run.failedMembers.count, 2)
    }

    func testPanelIsExactlyTheSeatsGiven() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let workers = [TestSupport.worker("worker_opus", driverId: "claude_code")]
        let seats = TestSupport.seats(["worker_opus"])

        let run = await coordinator.fanOut(prompt: "p", seats: seats, workers: workers)
        XCTAssertEqual(run.panel.map(\.id), ["worker_opus#0"])
        XCTAssertEqual(run.members.count, 1)
    }

    func testEmitsRunAndMemberEvents() async {
        let coordinator = makeCoordinator(scripts: ["claude": .init(stdout: "x", exitCode: 0)])
        let workers = [TestSupport.worker("worker_opus", driverId: "claude_code")]
        let seats = TestSupport.seats(["worker_opus"])

        let eventStream = coordinator.events
        let collector = Task { () -> [RunEvent] in
            var events: [RunEvent] = []
            for await event in eventStream { events.append(event) }
            return events
        }

        _ = await coordinator.fanOut(prompt: "p", seats: seats, workers: workers)
        let events = await collector.value

        let kinds = events.map(\.kind)
        XCTAssertTrue(kinds.contains(RunEventKind.runStatusChanged))
        XCTAssertTrue(kinds.contains(RunEventKind.memberStatusChanged))
        // Member events carry seatId.
        let memberEvents = events.filter { $0.kind == RunEventKind.memberStatusChanged }
        XCTAssertTrue(memberEvents.allSatisfy { $0.payload["seatId"]?.stringValue == "worker_opus#0" })
        XCTAssertEqual(events.map(\.seq), Array(1...Int64(events.count)))
    }

    func testCancellationResolvesCancelled() async {
        let coordinator = makeCoordinator(scripts: [
            "claude": .init(stdout: "slow", exitCode: 0, delay: .seconds(10))
        ])
        let workers = [TestSupport.worker("worker_opus", driverId: "claude_code")]
        let seats = TestSupport.seats(["worker_opus"])

        let task = Task { await coordinator.fanOut(prompt: "p", seats: seats, workers: workers) }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let run = await task.value

        XCTAssertEqual(run.status, .cancelled)
    }
}
