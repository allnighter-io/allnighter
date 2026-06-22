import XCTest
import AllnighterCore
@testable import AllnighterEngine

final class PendingWakePlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let wakeAt = Date(timeIntervalSince1970: 1_700_000_100)

    private func coolingItem(id: String = "p1", projectId: String = "proj1") -> PendingItem {
        PendingItem(
            id: id,
            projectId: projectId,
            title: "Review",
            kind: .workerChat,
            status: .pending,
            createdAt: now,
            updatedAt: now,
            prompt: "Review patch",
            target: PendingTarget(workerIds: ["model_opus"], preferredWorkerIds: ["model_opus"]),
            policy: PendingPolicy(),
            resume: PendingResume(
                reason: .cooldown,
                observedResetAt: wakeAt,
                capacityObservation: CapacityObservation(
                    kind: .accountRateLimit,
                    source: "claude-code",
                    sourceConfidence: .structured,
                    rawSnippet: "rate limited",
                    observedAt: now,
                    observedResetAt: wakeAt
                )
            )
        )
    }

    func testSelectsEarliestDueWakeTicket() {
        var later = coolingItem(id: "later", projectId: "proj1")
        var earlier = coolingItem(id: "earlier", projectId: "proj1")
        earlier.resume?.observedResetAt = nil
        earlier.resume?.wakeAfter = Date(timeIntervalSince1970: 1_700_000_050)

        let plan = PendingWakePlanner.plan(items: [later, earlier], now: now.addingTimeInterval(200))
        XCTAssertEqual(plan.dueItemId, "earlier")
    }

    func testReturnsFutureDeadlineWhenNothingDue() {
        let item = coolingItem()
        let plan = PendingWakePlanner.plan(items: [item], now: now)
        XCTAssertNil(plan.dueItemId)
        XCTAssertEqual(plan.nextWakeAt, wakeAt)
    }

    func testSkipsDraftRunningDoneFailedCancelledIdleAndUnassigned() {
        var draft = coolingItem(); draft.status = .draft
        var running = coolingItem(id: "run"); running.status = .running
        var done = coolingItem(id: "done"); done.status = .done
        var failed = coolingItem(id: "failed"); failed.status = .failed
        var cancelled = coolingItem(id: "cancel"); cancelled.status = .cancelled
        var idle = coolingItem(id: "idle"); idle.resume = nil
        var unassigned = coolingItem(id: "unassigned"); unassigned.projectId = nil
        var team = coolingItem(id: "team"); team.kind = .teamRun
        var auth = coolingItem(id: "auth")
        auth.resume?.capacityObservation = CapacityObservation(
            kind: .authRequired, source: "claude-code", sourceConfidence: .messageFallback, rawSnippet: "auth", observedAt: now
        )

        let plan = PendingWakePlanner.plan(
            items: [draft, running, done, failed, cancelled, idle, unassigned, team, auth],
            now: now.addingTimeInterval(200)
        )
        XCTAssertNil(plan.dueItemId)
        XCTAssertFalse(plan.skips.isEmpty)
        XCTAssertTrue(plan.skips.contains { $0.reason == "draft" })
        XCTAssertTrue(plan.skips.contains { $0.reason == "idlePending" })
        XCTAssertTrue(plan.skips.contains { $0.reason == "unassigned" })
    }
}

final class PendingWakeSchedulerTests: XCTestCase {
    private final class FakeSleeper: PendingWakeSleeper, @unchecked Sendable {
        var sleepCalls: [Date] = []
        func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
            sleepCalls.append(until)
        }
    }

    private let models = [
        Model(id: "model_opus", displayName: "Opus", modelLabel: "opus", driverId: "claude_code", role: .both),
    ]

    func testDueWakeUsesServeLeaseOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wake-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PendingStore(rootDirectory: root)
        let now = Date(timeIntervalSince1970: 1_700_000_200)
        let service = PendingService(store: store, models: models, now: { now })
        let item = try service.add(.init(prompt: "Review", workerToken: "model_opus", submit: true))
        var saved = try XCTUnwrap(store.load(id: item.id))
        saved.projectId = "proj1"
        saved.resume = PendingResume(reason: .cooldown, wakeAfter: Date(timeIntervalSince1970: 1_700_000_100))
        try store.save(saved)

        let sleeper = FakeSleeper()
        let scheduler = PendingWakeScheduler(
            store: store,
            models: models,
            registry: DriverRegistry([TestSupport.headlessManifest(id: "claude_code", command: "claude")]),
            commandRunner: MockCommandRunner(scripts: ["claude": .init(stdout: "ok", exitCode: 0)]),
            now: { now },
            sleeper: sleeper,
            jitterSeconds: 0
        )

        let flag = ShutdownFlag()
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            flag.fire()
        }
        await scheduler.run { flag.isCancelled }

        let settled = try XCTUnwrap(store.load(id: item.id))
        XCTAssertEqual(settled.status, .done)
        XCTAssertEqual(settled.attempts.count, 1)
        XCTAssertNil(settled.lease)
    }
}
