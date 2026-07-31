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
    /// `.messageFallback` confidence + a concrete `retryAfterSeconds`).
    private func vendorParkScript() -> MockCommandRunner.Script {
        .init(stdout: "", stderr: "usage limit reached, retry after: 120 seconds", exitCode: 1)
    }

    // MARK: - Dev turn parks

    func testParkedDevTurnDoesNotClassifyAsInfraBackoff() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [vendorParkScript()]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        // A misclassified park reads as `.infraBackoff`, thrash-retries up to
        // `maxInfraBackoffAttempts` (10), then escalates. The only honest outcome for a
        // genuine park is still-running — never `.escalated`.
        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1, "must not have retried the parked dev turn")
    }

    func testParkedTurnMintsNoCompetingRunIds() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [vendorParkScript()]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        _ = try await coordinator.run(config: config).get()

        // The ten-orphans regression: every infra-backoff retry called
        // `RunService.mintRunId()` at the top of `dispatchDevTurn`'s loop and re-parked a
        // fresh mutating run. One dev CLI spawn must mean exactly one run id minted.
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1, "exactly one run id must be minted for the parked dev turn")
    }

    func testParkedLoopStaysRunningWithCapacityPark() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [vendorParkScript()]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(state.status, .running)
        let park = try XCTUnwrap(state.capacityPark, "a parked dev turn must record LoopState.capacityPark")
        XCTAssertNotNil(park.wakeAfter)
        XCTAssertFalse(park.runId.isEmpty)

        // `.running` is the ONLY status `LoopStateStore.save` writes the owner-liveness
        // marker for (Corrections #8) — a parked-but-running loop's owning process is
        // alive for the whole wait, so it must stay reconcilable/live, not orphaned.
        XCTAssertFalse(stateStore.isOwnerDead(id: state.id), "a live .running parked loop must still carry its owner marker")
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
