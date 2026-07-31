import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// QABC-S01b: both loop turn dispatchers (`dispatchTurn` for PM, `dispatchDevTurn` for
/// dev) must yield to a vendor park instead of letting `LoopTurnClassifier.classify`
/// read the parked run's structured `capacityObservation` as `.infraBackoff` and
/// thrash-retry. The old bug: every 5s retry called `RunService.mintRunId()` and
/// re-parked a FRESH mutating run — up to ten orphaned parked runs, each of which
/// `VendorBackoffReconciler` would independently wake and replay the same dev prompt
/// against the repo.
///
/// Drives the REAL `RunService` (no fake/injected service) — only `CommandRunner` is
/// scripted, mirroring `LoopCoordinatorTests`' seam. A non-zero exit + a message-fallback
/// rate-limit phrasing makes `CapacityClassifier` produce a `.accountRateLimit`
/// observation with a concrete `retryAfterSeconds`, which `VendorBackoffPolicy.shouldPark`
/// accepts — the same shape a real vendor CLI's session-cap stderr produces. This makes
/// `RunService.run` genuinely park the run (`.queued` / `.waitingForVendor` /
/// `.vendorBackoff`), exactly like production.
final class LoopCapacityParkYieldTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relay-park-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures (mirrors LoopCoordinatorTests)

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    @discardableResult
    private func makeGitRepo() throws -> URL {
        let dir = tmp.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for a in [["init", "-q"], ["config", "user.email", "t@t.dev"], ["config", "user.name", "T"],
                  ["config", "commit.gpgsign", "false"]] { runGit(a, cwd: dir) }
        try "spec".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        runGit(["add", "."], cwd: dir)
        runGit(["commit", "-q", "-m", "c1"], cwd: dir)
        return dir
    }

    private func makeService(
        pmScripts: [MockCommandRunner.Script],
        devScripts: [MockCommandRunner.Script],
        runStore: RunStore
    ) -> (RunService, SequencedCommandRunner) {
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "pm_cli", role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "pm_cli", command: "pm_cli"),
            TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: ["pm_cli": pmScripts, "dev_cli": devScripts])
        let service = RunService(
            models: [pmModel, devModel],
            registry: registry,
            runStore: runStore,
            commandRunner: runner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: "pm_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "dev_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                ]
            }
        )
        return (service, runner)
    }

    private func verdictJSON(_ verdict: String, handover: String? = nil, note: String? = nil) -> String {
        var fields = ["\"verdict\": \"\(verdict)\""]
        if let handover { fields.append("\"handover\": \"\(handover)\"") }
        if let note { fields.append("\"note\": \"\(note)\"") }
        return "```json\n{\(fields.joined(separator: ", "))}\n```"
    }

    /// A vendor session-cap script: non-zero exit + a message-fallback rate-limit
    /// phrasing `CapacityClassifier.retryAfterSeconds(fromMessage:)` recognizes, which
    /// makes `VendorBackoffPolicy.shouldPark` accept it (`.accountRateLimit` +
    /// `.messageFallback` confidence + a concrete `retryAfterSeconds`). The ACTUAL
    /// `wakeAfter` is never this raw value — `VendorBackoffPolicy.computeWakeAfter`
    /// always adds `minimumPadSeconds` (120s) plus 60-300s of jitter on top, by design
    /// (never hammer a vendor right at the stated reset). A real wait is therefore
    /// always >=180s regardless of what this script says — the QABC-S01c resolution
    /// tests below use a fake clock/sleeper (`SimulatedClock`) instead of waiting for
    /// real wall-clock time.
    private func vendorParkScript() -> MockCommandRunner.Script {
        .init(stdout: "", stderr: "usage limit reached, retry after: 120 seconds", exitCode: 1)
    }

    /// A controllable clock threaded through `LoopCoordinator.now` AND the fake
    /// sleeper below, so "sleeping" just advances this shared clock instead of
    /// blocking the test for the vendor's real (>=180s) retry-after window.
    private final class SimulatedClock: @unchecked Sendable {
        private var current: Date
        init(_ start: Date) { current = start }
        func now() -> Date { current }
        func advance(to date: Date) { if date > current { current = date } }
    }

    private final class InstantAdvancingSleeper: PendingWakeSleeper, @unchecked Sendable {
        let clock: SimulatedClock
        init(clock: SimulatedClock) { self.clock = clock }
        func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
            clock.advance(to: until)
        }
    }

    /// Simulates a rival coordinator (the shape of `alln serve`'s
    /// `VendorBackoffReconciler`) winning the wake race: the FIRST time our own loop
    /// "sleeps" waiting for the wake, this claims and fully resumes the parked run
    /// itself, before our own loop ever attempts its own claim.
    private final class RivalClaimingSleeper: PendingWakeSleeper, @unchecked Sendable {
        let clock: SimulatedClock
        let runStore: RunStore
        let runService: RunService
        private var hasActed = false
        init(clock: SimulatedClock, runStore: RunStore, runService: RunService) {
            self.clock = clock
            self.runStore = runStore
            self.runService = runService
        }
        func sleep(until: Date, jitterSeconds: TimeInterval) async throws {
            clock.advance(to: until)
            guard !hasActed else { return }
            hasActed = true
            guard let parked = runStore.list().first(where: { $0.phase == .waitingForVendor }) else { return }
            guard runStore.claimVendorWake(runId: parked.id, coordinatorId: "rival_serve", now: clock.now()) != nil else { return }
            _ = await runService.resumeParkedRun(runId: parked.id, coordinatorId: "rival_serve")
        }
    }

    // MARK: - Dev turn parks

    func testParkedDevTurnDoesNotClassifyAsInfraBackoff() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            vendorParkScript(),
            .init(stdout: "Implemented and committed after the vendor reset."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let clock = SimulatedClock(Date())
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            now: { clock.now() }, sleeper: InstantAdvancingSleeper(clock: clock)
        )

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 1
        )
        let state = try await coordinator.run(config: config).get()

        // A misclassified park reads as `.infraBackoff`, thrash-retries up to
        // `maxInfraBackoffAttempts` (10), then escalates. The honest outcome is: the
        // park yields once, claim-or-adopt resolves it after the (simulated) wake,
        // and the round completes normally — never a bare `.escalated` from thrash.
        XCTAssertEqual(state.rounds.first?.outcome, .continued, "note: \(state.note ?? "nil")")
        XCTAssertNil(state.capacityPark, "resolved — no dangling park side-field")
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2, "one park attempt + one resumed attempt — never a thrash retry")
    }

    func testParkedTurnMintsNoCompetingRunIds() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            vendorParkScript(),
            .init(stdout: "Implemented and committed after the vendor reset."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let clock = SimulatedClock(Date())
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            now: { clock.now() }, sleeper: InstantAdvancingSleeper(clock: clock)
        )

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 1
        )
        _ = try await coordinator.run(config: config).get()

        // The ten-orphans regression: every infra-backoff retry called
        // `RunService.mintRunId()` at the top of `dispatchDevTurn`'s loop and re-parked a
        // fresh mutating run. Resolving via claim-or-adopt mints exactly one MORE run
        // (the resumed attempt) — never a competing third, fourth, ... tenth id.
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2, "exactly the park attempt plus the one resumed attempt")
    }

    func testParkPastDeadlineStopsWithWakeInReason() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [vendorParkScript()]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)

        // `until` must be reachable AFTER round 1 starts (else `loop()`'s own
        // pre-round deadline check fires first, before the dev turn ever dispatches)
        // but BEFORE the vendor wake (>=180s away) — so `resolveCapacityPark`'s own
        // deadline check is what fires. The advancing clock carries `now()` up to
        // `until` via `sleepUntil`'s clamp during the FIRST wake wait.
        let start = Date()
        let clock = SimulatedClock(start)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            now: { clock.now() }, sleeper: InstantAdvancingSleeper(clock: clock)
        )

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5,
            until: start.addingTimeInterval(1)
        )
        let state = try await coordinator.run(config: config).get()

        // The loop's own `--until` passed while the dev turn was parked, waiting
        // for the (much later) vendor wake — correction #7's "one legal escalation":
        // stop, don't thrash, and name the wake that was interrupted.
        XCTAssertEqual(state.status, .stopped)
        let reason = try XCTUnwrap(state.stoppedReason)
        XCTAssertTrue(reason.contains("parked"), "reason must say the turn was parked: \(reason)")
        XCTAssertTrue(reason.contains("wakes after"), "reason must name the wake it was waiting for: \(reason)")
        XCTAssertNil(state.capacityPark, "resolved (to a stop) — no dangling park side-field")
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1, "must not attempt a claim once the deadline has already passed")
    }

    func testWakeClaimLostToServeAdoptsInsteadOfEscalating() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            vendorParkScript(),
            .init(stdout: "Implemented and committed by the rival's resume."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let clock = SimulatedClock(Date())
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            now: { clock.now() },
            sleeper: RivalClaimingSleeper(clock: clock, runStore: runStore, runService: service)
        )

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 1
        )
        let state = try await coordinator.run(config: config).get()

        // The rival (e.g. `alln serve`) claimed and resumed first. Losing that race
        // must ADOPT its settlement, never escalate (correction #7).
        XCTAssertEqual(state.rounds.first?.outcome, .continued, "adopting the rival's settlement must not escalate")
        XCTAssertNotEqual(state.status, .escalated)
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2, "the park attempt plus the rival's one resume — our own loop mints no competing id")
    }

    // MARK: - PM turn parks (dispatchTurn twin)

    func testPMTurnParkYieldsToo() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [vendorParkScript()]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(state.status, .running)
        XCTAssertNotNil(state.capacityPark)
        XCTAssertEqual(runner.callCount(for: "pm_cli"), 1, "PM turn must not thrash-retry on a park")
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0, "dev seat must never dispatch when the PM turn itself parks")
    }
}
