import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// R-S04 works test: the LoopCoordinator loop against a real git repo and a scripted
/// (never-real-network) worker CLI, mirroring PairCoordinatorTests' seam — a custom
/// `CommandRunner` double keyed by command name, here extended to (a) return a DIFFERENT
/// scripted answer on each successive call to the same command (a relay's PM seat is
/// called more than once per relay) and (b) capture the args each call received so tests
/// can assert on the ACTUAL prompt text a turn was given (e.g. that a resumed relay's
/// founder note really reached the PM prompt).
final class LoopCoordinatorTests: HermeticSupportTestCase {
    private var tmp: URL!

    /// `CoreJSON` encodes dates as ISO-8601 without fractional seconds, so a raw
    /// `Date()` fixture never round-trips byte-for-byte through disk. Tests that assert
    /// on a reloaded `LoopState` equalling the in-memory one inject this instead of
    /// `Date.init` so both sides already carry whole-second precision.
    private static func flooredNow() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

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
        runStore: RunStore,
        pmDriverId: String = "pm_cli",
        devDriverId: String = "dev_cli",
        commandRunner: CommandRunner? = nil
    ) -> (RunService, SequencedCommandRunner) {
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: pmDriverId, role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: devDriverId, role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: pmDriverId, command: "pm_cli"),
            TestSupport.headlessManifest(id: devDriverId, command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: ["pm_cli": pmScripts, "dev_cli": devScripts])
        let service = RunService(
            models: [pmModel, devModel],
            registry: registry,
            runStore: runStore,
            commandRunner: commandRunner ?? runner,
            writeLock: RunWriteLockRegistry(),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: pmDriverId, status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: devDriverId, status: .ready(version: "1"), lastProbeAt: .distantPast),
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

    // MARK: - Happy path

    func testHappyTwoRoundRelayEndsInDone() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1 review.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
            .init(stdout: "Round 2 review, dev delivered.\n\n" + verdictJSON("done", note: "All criteria met.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Implemented and committed. Verified with `true`."),
        ]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(state.status, .done)
        XCTAssertEqual(state.note, "All criteria met.")
        XCTAssertEqual(state.rounds.count, 2)
        XCTAssertEqual(state.rounds[0].outcome, .continued)
        XCTAssertEqual(state.rounds[0].verdict?.verdict, .continueRelay)
        XCTAssertNotNil(state.rounds[0].pmRunId)
        XCTAssertNotNil(state.rounds[0].devRunId)
        XCTAssertNotNil(state.rounds[0].baselineHead)
        XCTAssertEqual(state.rounds[1].outcome, .done)
        XCTAssertEqual(state.rounds[1].verdict?.verdict, .done)
        // Round 2's PM prompt should have threaded round 1's dev report + head range —
        // verified indirectly: round 2 dispatched at all (there'd be no second PM call
        // otherwise) and the relay reached `done` only via round 2's verdict.
    }

    /// PO-F10: unresolvable `--dev-model` escalates with AGENT_NOT_AVAILABLE before
    /// silent stall retries (no 4 stalls + devRunId:NONE).
    func testUnresolvableDevWorkerEscalatesWithAgentNotAvailable() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement something.")),
        ]
        let (service, runner) = makeService(
            pmScripts: pmScripts, devScripts: [], runStore: runStore
        )
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm",
            // Known catalog id but disabled on this service's bench (makeService only
            // registers model_dev enabled). Pass an unknown id to trip PO-F10.
            devModelId: "model_does_not_exist",
            maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(state.status, .escalated)
        XCTAssertTrue(
            (state.note ?? "").contains("AGENT_NOT_AVAILABLE"),
            "escalation note must surface typed code, got: \(state.note ?? "")"
        )
        XCTAssertEqual(state.rounds.count, 1)
        XCTAssertEqual(state.rounds[0].outcome, .escalated)
        XCTAssertNil(state.rounds[0].devRunId, "must not enter stall-retry with a fake/none run")
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0, "dev CLI must never spawn")
    }

    /// D1 (Pilot_Defect_Fixes): the Execution Playbook preamble must appear at most once
    /// on a relay dev-turn dispatch. Captures the real `dev_cli` prompt through the same
    /// `SequencedCommandRunner` seam as the other coordinator tests — not a unit of
    /// `SkillCatalog.assemblePrompt` alone.
    func testDevTurnPlaybookPreambleAppearsAtMostOnce() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the D1 fix.")),
            .init(stdout: "Shipped.\n\n" + verdictJSON("done", note: "Preamble is single.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Fixed and committed."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/Pilot_Defect_Fixes.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()
        XCTAssertEqual(state.status, .done)
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 1)

        let devArgs = runner.capturedArgs(for: "dev_cli").first ?? []
        let prompt: String
        if let index = devArgs.firstIndex(of: "-p"), index + 1 < devArgs.count {
            prompt = devArgs[index + 1]
        } else {
            prompt = devArgs.joined(separator: " ")
        }
        XCTAssertFalse(prompt.isEmpty, "dev turn must have dispatched a prompt")

        let marker = "You are executing a product slice in the user's repo. Follow the Execution Playbook:"
        var count = 0
        var search = prompt.startIndex..<prompt.endIndex
        while let range = prompt.range(of: marker, range: search) {
            count += 1
            search = range.upperBound..<prompt.endIndex
        }
        XCTAssertEqual(
            count, 1,
            "playbook preamble must appear exactly once on the assembled dev prompt; got \(count). Prefix:\n\(String(prompt.prefix(600)))"
        )
        XCTAssertTrue(
            prompt.contains("# PM Relay — round 1 (dev seat)"),
            "LoopDevPrompt wrapper must still be present after the single preamble"
        )
    }

    // MARK: - FR9 delivered-not-stalled

    func testCommitThenStallSettlesDeliveredWithOneDevDispatch() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Commit a file.")),
            .init(stdout: "Shipped.\n\n" + verdictJSON("done", note: "Observed delivery.")),
        ]
        let devRunner = CommittingThenStallingCommandRunner(repoRoot: repo)
        let pmRunner = SequencedCommandRunner(queues: ["pm_cli": pmScripts])
        let routingRunner = LoopTestCommandRouter(pm: pmRunner, dev: devRunner)
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: [], runStore: runStore, commandRunner: routingRunner
        )
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(devRunner.callCount, 1, "delivered-not-stalled must not re-dispatch")
        XCTAssertEqual(pmRunner.callCount(for: "pm_cli"), 2)
        XCTAssertEqual(state.rounds.count, 2)
        XCTAssertEqual(state.rounds[0].outcome, .continued)
        XCTAssertNotEqual(state.rounds[0].baselineHead, state.rounds[0].headAfterDev)
        XCTAssertNotNil(state.rounds[0].devRunId)
        let devRun = runStore.load(runId: try XCTUnwrap(state.rounds[0].devRunId))
        XCTAssertTrue(try XCTUnwrap(devRun?.repoDelta).changed)
        XCTAssertEqual(state.status, .done)
    }

    // MARK: - PO-F7 dev-turn idle-timeout override

    func testDevTurnIdleTimeoutOverrideReachesRunRequest() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Implemented and committed."),
        ]
        let pmRunner = SequencedCommandRunner(queues: ["pm_cli": pmScripts])
        let devSpy = TimeoutCapturingCommandRunner(inner: SequencedCommandRunner(queues: ["dev_cli": devScripts]))
        let routingRunner = LoopTestCommandRouter(pm: pmRunner, dev: devSpy)
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore, commandRunner: routingRunner
        )
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 1,
            devTurnIdleTimeoutSeconds: 555
        )
        _ = try await coordinator.run(config: config).get()

        XCTAssertEqual(
            devSpy.lastTimeout?.components.seconds, 555,
            "Config.devTurnIdleTimeoutSeconds must reach RunRequest.workerTimeoutSeconds on the dev turn"
        )
    }

    func testDevTurnIdleTimeoutDefaultLeavesRunnerTimeoutAtManifestDefault() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Implemented and committed."),
        ]
        let pmRunner = SequencedCommandRunner(queues: ["pm_cli": pmScripts])
        let devSpy = TimeoutCapturingCommandRunner(inner: SequencedCommandRunner(queues: ["dev_cli": devScripts]))
        let routingRunner = LoopTestCommandRouter(pm: pmRunner, dev: devSpy)
        let (service, _) = makeService(
            pmScripts: pmScripts, devScripts: devScripts, runStore: runStore, commandRunner: routingRunner
        )
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 1
        )
        _ = try await coordinator.run(config: config).get()

        // `makeService`'s `TestSupport.headlessManifest` default `invoke.timeoutSeconds`
        // (2) — no override flows through when `devTurnIdleTimeoutSeconds` is nil (default).
        XCTAssertEqual(devSpy.lastTimeout?.components.seconds, 2)
    }

    func testAmbiguousStallRetryAppendsPartialCompletionHint() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Try the fix.")),
            .init(stdout: "Done.\n\n" + verdictJSON("done", note: "Eventually shipped.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [
            .init(stdout: "partial output without commit", exitCode: 1),
            .init(stdout: "finished cleanly."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2)
        let secondPrompt = runner.capturedArgs(for: "dev_cli")[1].joined(separator: " ")
        XCTAssertTrue(
            secondPrompt.contains("A prior attempt may have partially completed"),
            "ambiguous stall retry must warn before redoing work"
        )
        XCTAssertEqual(state.status, .done)
    }

    // MARK: - Verdict re-ask

    func testContinueWithoutHandoverTriggersReaskThenContinues() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "No verdict tail here at all."),
            .init(stdout: "Recovered.\n\n" + verdictJSON("continue", handover: "Do the thing.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "Done, committed.")]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 1
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2, "first attempt + one re-ask")
        XCTAssertEqual(state.rounds.count, 1)
        XCTAssertEqual(state.rounds[0].outcome, .continued)
        XCTAssertEqual(state.rounds[0].verdict?.verdict, .continueRelay)
        XCTAssertNotNil(state.rounds[0].devRunId)
        // maxRounds: 1 means round 2 never starts — the relay stops on the ceiling right
        // after the successful re-ask round, proving the re-ask path itself works.
        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.stoppedReason, "reached --max-rounds (1)")
    }

    func testReaskFailsEscalates() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "No verdict at all."),
            .init(stdout: "Still no verdict tail."),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev"
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2)
        XCTAssertEqual(state.status, .escalated)
        XCTAssertEqual(state.rounds.count, 1)
        XCTAssertEqual(state.rounds[0].outcome, .escalated)
        XCTAssertTrue(state.note?.contains("re-ask") ?? false)
    }

    // MARK: - HandoverGate

    func testGateBlockedHandoverEscalatesWithDangerClassInNote() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let dangerousHandover = "Run git reset --hard on main to clean this up."
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Reviewed.\n\n" + verdictJSON("continue", handover: dangerousHandover)),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev"
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(runner.callCount(for: "dev_cli"), 0, "the dev turn must never dispatch on a blocked handover")
        XCTAssertEqual(state.status, .escalated)
        XCTAssertEqual(state.rounds[0].gate?.allowed, false)
        XCTAssertEqual(state.rounds[0].gate?.dangerClass, "destructiveGit")
        XCTAssertTrue(state.note?.contains("destructiveGit") ?? false)
        XCTAssertTrue(state.note?.contains("RELAY_HANDOVER_UNSAFE") ?? false)
    }

    // MARK: - Ceilings

    func testMaxRoundsStops() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Keep going.\n\n" + verdictJSON("continue", handover: "Keep building.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "Some progress, no commit this time.")]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev",
            maxRounds: 2, stagnationRoundCap: 10
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.stoppedReason, "reached --max-rounds (2)")
        XCTAssertEqual(state.rounds.count, 2)
        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2)
        XCTAssertEqual(runner.callCount(for: "dev_cli"), 2)
    }

    func testStagnationStops() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Same flag again.\n\n" + verdictJSON("continue", handover: "Please fix the same thing.")),
        ]
        // The dev CLI is scripted, never touches git — the repo genuinely does not change,
        // which is exactly the deadlock signature stagnation exists to catch.
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "I tried again but nothing changed.")]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev",
            maxRounds: 20, stagnationRoundCap: 2
        )
        let state = try await coordinator.run(config: config).get()

        XCTAssertEqual(state.status, .stopped)
        XCTAssertTrue(state.stoppedReason?.contains("stagnation") ?? false)
        XCTAssertEqual(state.rounds.count, 2, "stops right after the 2nd consecutive no-change round")
        XCTAssertEqual(runner.callCount(for: "pm_cli"), 2)
    }

    // MARK: - Resume

    func testResumeAfterEscalateInjectsFounderNoteIntoNextPMTurn() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "I need to know which env.\n\n" + verdictJSON("escalate", note: "staging or prod?")),
        ]
        let (service, runner) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_resume_test" }
        )
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev"
        )
        let escalated = try await coordinator.run(config: config).get()
        XCTAssertEqual(escalated.status, .escalated)
        XCTAssertEqual(escalated.id, "relay_resume_test")

        // Resume: the PM now delivers `done`. Assert the founder's answer actually reached
        // the PM prompt text for the resumed round (not just that the loop continued).
        runner.enqueue(command: "pm_cli", .init(stdout: "Using staging.\n\n" + verdictJSON("done", note: "Shipped to staging.")))
        let resumedConfig = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let resumedResult = await coordinator.resume(loopId: "relay_resume_test", founderAnswer: "use staging", config: resumedConfig)
        guard case .success(let resumed) = resumedResult else { return XCTFail("expected success") }

        XCTAssertEqual(resumed.status, .done)
        XCTAssertEqual(resumed.rounds.count, 2)
        XCTAssertNil(resumed.founderNote, "consumed after the first post-resume PM turn")

        let secondCallArgs = runner.capturedArgs(for: "pm_cli").last ?? []
        XCTAssertTrue(secondCallArgs.joined(separator: " ").contains("use staging"), "founder note must reach the PM prompt verbatim")
    }

    func testResumeOnNonEscalatedRelayReturnsNil() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [.init(stdout: "Done.\n\n" + verdictJSON("done", note: "ok"))]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_done_test" }
        )
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let done = try await coordinator.run(config: config).get()
        XCTAssertEqual(done.status, .done)

        let result = await coordinator.resume(loopId: "relay_done_test", founderAnswer: "irrelevant", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notResumable(status: "done"))
    }

    // MARK: - Durability

    func testStatePersistedAfterEachRoundNotOnlyAtTheEnd() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Round 1.\n\n" + verdictJSON("continue", handover: "Build it.")),
            .init(stdout: "Round 2, done.\n\n" + verdictJSON("done", note: "Shipped.")),
        ]
        let devScripts: [MockCommandRunner.Script] = [.init(stdout: "Built and committed.")]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: devScripts, runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            now: Self.flooredNow, idFactory: { "relay_durability_test" }
        )
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )

        let midRelayRoundCount = LockedBox<Int?>(nil)
        let final = try await coordinator.run(config: config) { event in
            if case .devTurnFinished(let round) = event, round == 1 {
                // The relay is still mid-flight (round 2 hasn't started) — the loaded
                // on-disk state must already reflect round 1's completed dev turn.
                midRelayRoundCount.value = stateStore.load(id: "relay_durability_test")?.rounds.count
            }
        }.get()

        XCTAssertEqual(midRelayRoundCount.value, 1)
        XCTAssertEqual(final.status, .done)

        let reloaded = stateStore.load(id: "relay_durability_test")
        XCTAssertEqual(reloaded, final)
    }

    // MARK: - Orphan reconciliation (works-test hazard #1)

    /// Simulates `LoopCoordinator.run()`'s own bootstrap up through the exact durable
    /// checkpoint a real relay leaves on disk the instant it dispatches round 1's PM turn —
    /// `started` (creates the thread), append the round, `save` (records THIS test
    /// process's pid as owner) — then overwrites the marker with a pid that cannot
    /// possibly be alive (mirrors `RunStoreJournalTests.testOrphanWithDeadPidResolvesToInterrupted`)
    /// to stand in for "the process was killed mid-round."
    @discardableResult
    private func makeOrphanedRunningRelay(
        id: String, projectRoot: String, stateStore: LoopStateStore, projector: LoopThreadProjector
    ) throws -> LoopState {
        var state = LoopState(
            id: id, projectRoot: projectRoot, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Self.flooredNow()
        )
        projector.started(state: state, projectId: nil)
        state.rounds.append(RelayRound(roundNumber: 1, baselineHead: "abc123", startedAt: Self.flooredNow()))
        try stateStore.save(state)
        projector.sync(state: state, now: Self.flooredNow())

        let ownerURL = stateStore.rootDirectory.appendingPathComponent(id, isDirectory: true).appendingPathComponent("owner.pid")
        try Data("2000000".utf8).write(to: ownerURL)
        return state
    }

    func testStatusReconcilesDeadOwnerRunningRelayAndSettlesTheThread() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = LoopThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(id: "relay_orphan_status", projectRoot: tmp.path, stateStore: stateStore, projector: projector)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore, threadProjector: projector)

        let reconciled = coordinator.status(loopId: "relay_orphan_status")
        XCTAssertEqual(reconciled?.status, .stopped)
        XCTAssertEqual(reconciled?.stoppedReason, LoopState.orphanReconciledReason)
        XCTAssertEqual(reconciled?.rounds.last?.outcome, .stopped)

        // Durable: a fresh read (a different process re-opening the same file) sees the
        // SAME reconciled result, not just an in-memory view.
        XCTAssertEqual(stateStore.load(id: "relay_orphan_status")?.status, .stopped)

        // Thread projection settled: the open PM turn closes, and a stopped system event lands.
        let thread = threadStore.get("relay_orphan_status")
        XCTAssertEqual(thread?.turn(id: "relay_orphan_status_pm1")?.status, .cancelled)
        let stopped = thread?.turn(id: "relay_orphan_status_stopped")
        XCTAssertNotNil(stopped)
        XCTAssertEqual(stopped?.text, LoopState.orphanReconciledReason)
    }

    func testResumeAfterOrphanReconciliationContinuesFromLastDurableRound() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = LoopThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(id: "relay_resume_after_kill", projectRoot: repo.path, stateStore: stateStore, projector: projector)

        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Recovered after kill.\n\n" + verdictJSON("done", note: "Finished after resume.")),
        ]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore, threadProjector: projector)

        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )
        let resumedResult = await coordinator.resume(loopId: "relay_resume_after_kill", founderAnswer: "continue please", config: config)
        guard case .success(let resumed) = resumedResult else { return XCTFail("expected success") }

        XCTAssertEqual(resumed.status, .done)
        // The killed round stays recorded as stopped — reconciliation never silently
        // erases it, it settles it — and the resumed attempt is a NEW round after it.
        XCTAssertEqual(resumed.rounds.count, 2)
        XCTAssertEqual(resumed.rounds.first?.outcome, .stopped)
        XCTAssertEqual(resumed.rounds.last?.outcome, .done)
    }

    func testResumeNeverAcceptsADoneRelayEvenThoughReconciliationOnlyTouchesRunning() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let state = LoopState(
            id: "relay_done_never_resumable", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .done, createdAt: Date(), note: "Shipped."
        )
        try stateStore.save(state)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: "/repo", docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let result = await coordinator.resume(loopId: "relay_done_never_resumable", founderAnswer: "anything", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notResumable(status: "done"))
        XCTAssertEqual(stateStore.load(id: "relay_done_never_resumable")?.status, .done, "never mutated")
    }

    /// A ceiling-fired `.stopped` relay (`--max-rounds`/`--until`/stagnation) is a
    /// deliberate stop, not an orphan — `reconcileOrphan`'s `.running`-only guard means it
    /// is never mistaken for one, and `relay-resume` must keep refusing it.
    func testCeilingStoppedRelayIsNeitherReconciledNorResumable() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let state = LoopState(
            id: "relay_ceiling_stopped", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .stopped, createdAt: Date(),
            stoppedReason: "reached --max-rounds (5)"
        )
        try stateStore.save(state)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)

        XCTAssertEqual(coordinator.status(loopId: "relay_ceiling_stopped")?.stoppedReason, "reached --max-rounds (5)", "untouched by reconciliation")

        let config = LoopCoordinator.Config(
            projectRoot: "/repo", docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let result = await coordinator.resume(loopId: "relay_ceiling_stopped", founderAnswer: "anything", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notResumable(status: "stopped"))
    }

    // MARK: - ATL-S02: founder stop

    func testFounderStopOnRunningWithDeadOwnerStampsReasonAndPMTurn() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmTurnStore = PMTurnStore(loopsRootDirectory: stateStore.rootDirectory)
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = LoopThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(
            id: "relay_founder_stop", projectRoot: tmp.path, stateStore: stateStore, projector: projector
        )
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            pmTurnStore: pmTurnStore, threadProjector: projector
        )

        let result = coordinator.stop(loopId: "relay_founder_stop")
        guard case .success(let state) = result else { return XCTFail("expected stop success, got \(result)") }
        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.stoppedReason, LoopState.founderStoppedReason)
        XCTAssertFalse(state.isResumable, "founder stop is never resumable")
        XCTAssertEqual(state.rounds.last?.outcome, .stopped)

        let durable = try XCTUnwrap(stateStore.load(id: "relay_founder_stop"))
        XCTAssertEqual(durable.status, .stopped)
        XCTAssertEqual(durable.stoppedReason, LoopState.founderStoppedReason)

        let turn = try XCTUnwrap(pmTurnStore.load(kind: .relay, subjectId: "relay_founder_stop"))
        XCTAssertEqual(turn.reason, "stopped")
        XCTAssertEqual(turn.lifecycleStatus, "stopped")
        XCTAssertTrue(turn.nextCommands.contains { $0.contains("loop status") })
    }

    func testFounderStopIdempotentOnDoneAndStoppedDoesNotRewriteReasonOrSecondPMTurn() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmTurnStore = PMTurnStore(loopsRootDirectory: stateStore.rootDirectory)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore, pmTurnStore: pmTurnStore
        )

        let done = LoopState(
            id: "relay_stop_done", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .done,
            createdAt: Self.flooredNow(), note: "shipped"
        )
        try stateStore.save(done)
        let doneAgain = try coordinator.stop(loopId: "relay_stop_done").get()
        XCTAssertEqual(doneAgain.status, .done)
        XCTAssertNil(doneAgain.stoppedReason)
        XCTAssertNil(try pmTurnStore.load(kind: .relay, subjectId: "relay_stop_done"), "no PM Turn on idempotent done")

        let ceiling = LoopState(
            id: "relay_stop_ceiling", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .stopped,
            createdAt: Self.flooredNow(), stoppedReason: "reached --max-rounds (3)"
        )
        try stateStore.save(ceiling)
        // Pre-seed a ceiling PM Turn so we can assert sequence does not advance.
        try pmTurnStore.save(PMTurnJSON(
            kind: .relay, subjectId: "relay_stop_ceiling", sequence: 1,
            createdAt: PMTurnJSON.isoTimestamp(Self.flooredNow()), reason: "stopped", lifecycleStatus: "stopped",
            nextCommands: ["alln pair relay-status --relay relay_stop_ceiling --json"]
        ))
        let ceilingAgain = try coordinator.stop(loopId: "relay_stop_ceiling").get()
        XCTAssertEqual(ceilingAgain.stoppedReason, "reached --max-rounds (3)", "leave existing reason alone")
        let turnAfter = try XCTUnwrap(pmTurnStore.load(kind: .relay, subjectId: "relay_stop_ceiling"))
        XCTAssertEqual(turnAfter.sequence, 1, "no second PM Turn on idempotent stopped")
    }

    func testFounderStopOnEscalatedAbandonsAndIsNotResumable() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmTurnStore = PMTurnStore(loopsRootDirectory: stateStore.rootDirectory)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore, pmTurnStore: pmTurnStore
        )
        let escalated = LoopState(
            id: "relay_stop_escalated", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .escalated,
            createdAt: Self.flooredNow(), note: "which env?"
        )
        try stateStore.save(escalated)

        let stopped = try coordinator.stop(loopId: "relay_stop_escalated").get()
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertEqual(stopped.stoppedReason, LoopState.founderStoppedReason)
        XCTAssertFalse(stopped.isResumable)

        let config = LoopCoordinator.Config(
            projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev"
        )
        let resume = await coordinator.resume(
            loopId: "relay_stop_escalated", founderAnswer: "staging", config: config
        )
        guard case .failure(let error) = resume else { return XCTFail("resume must refuse founder-stopped") }
        XCTAssertEqual(error, .notResumable(status: "stopped"))
        XCTAssertNotNil(try pmTurnStore.load(kind: .relay, subjectId: "relay_stop_escalated"))
    }

    func testFounderStopNotFound() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let result = coordinator.stop(loopId: "relay_nope")
        XCTAssertEqual(result, .failure(.relayNotFound))
    }

    func testFounderStopRefusesToLieWhenTurnOwnerStillAlive() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmTurnStore = PMTurnStore(loopsRootDirectory: stateStore.rootDirectory)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore, pmTurnStore: pmTurnStore
        )

        var state = LoopState(
            id: "relay_stop_live_turn", projectRoot: tmp.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running,
            createdAt: Self.flooredNow()
        )
        state.rounds.append(RelayRound(
            roundNumber: 1, baselineHead: "abc", startedAt: Self.flooredNow()
        ))
        try stateStore.save(state)
        // Dead owner so step 3 is a no-op; live turn-owner forces honesty fail at step 4.
        let dir = try stateStore.directory(for: state.id)
        try Data("2000000".utf8).write(to: dir.appendingPathComponent("owner.pid"))
        let live = try XCTUnwrap(ProcessOwnership.OwnerIdentity.current(kind: .devTurn))
        try ProcessOwnership.writeTurnOwner(live, in: dir)

        var signals: [Int32] = []
        ProcessOwnership.terminateSignalHook = { pgid in signals.append(pgid) }
        defer { ProcessOwnership.terminateSignalHook = nil }

        let result = coordinator.stop(loopId: "relay_stop_live_turn")
        guard case .failure(let error) = result else { return XCTFail("must not stamp stopped over live work") }
        if case .stopFailed = error {} else { return XCTFail("expected stopFailed, got \(error)") }
        XCTAssertFalse(signals.isEmpty, "must attempt identity-checked terminate")
        let durable = try XCTUnwrap(stateStore.load(id: "relay_stop_live_turn"))
        XCTAssertEqual(durable.status, .running, "left non-terminal")
        XCTAssertNil(durable.stoppedReason)
        XCTAssertNil(try pmTurnStore.load(kind: .relay, subjectId: "relay_stop_live_turn"))
    }

    // MARK: - RSC-HF: guard flips durable state

    /// `resumeGuard` must flip + persist EXACTLY what `resume` itself would before
    /// the round loop runs — the detached child now runs the same registered verb and
    /// re-enters through `resume`, so this test proves the guard half alone.
    func testResumeGuardFlipsStateMatchingResumeMutation() throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let state = LoopState(
            id: "relay_guard_resume", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .escalated,
            createdAt: Date(), note: "which env?"
        )
        try stateStore.save(state)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )

        let guardResult = coordinator.resumeGuard(loopId: "relay_guard_resume", founderAnswer: "use staging", config: config)
        guard case .success(let (flipped, resumedConfig)) = guardResult else { return XCTFail("expected guard success") }
        XCTAssertEqual(flipped.status, .running, "the guard's own mutation, before any child exists")
        XCTAssertEqual(flipped.founderNote, "use staging")
        XCTAssertEqual(resumedConfig.projectRoot, repo.path)
        XCTAssertEqual(stateStore.load(id: "relay_guard_resume")?.status, .running, "durable, not just in-memory")
        XCTAssertEqual(stateStore.load(id: "relay_guard_resume")?.founderNote, "use staging")
    }

    /// The `--no-wait` foreground guard must refuse identically to `resume` when
    /// another process already holds the dispatch lock — same `.roundInFlight`
    /// failure channel, and durable state stays untouched (no ack can ever precede
    /// a refusal because the guard never got far enough to flip anything).
    func testResumeGuardRefusesRoundInFlightAndLeavesStateUntouched() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let state = LoopState(
            id: "relay_guard_locked", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .escalated,
            createdAt: Date(), note: "which env?"
        )
        try stateStore.save(state)

        var heldLock = LoopDispatchLock.tryAcquire(loopId: "relay_guard_locked", loopsRoot: stateStore.rootDirectory)
        XCTAssertNotNil(heldLock, "precondition: lock must be free before the simulated race")

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let guardResult = coordinator.resumeGuard(loopId: "relay_guard_locked", founderAnswer: "use staging", config: config)
        guard case .failure(let error) = guardResult else { return XCTFail("expected guard failure while the lock is held") }
        XCTAssertEqual(error, .roundInFlight)
        XCTAssertEqual(stateStore.load(id: "relay_guard_locked")?.status, .escalated, "a refused guard must never mutate durable state")
        heldLock = nil
    }

    /// RSC-HF: a stray duplicate `pair relay --no-wait` start racing a genuinely live
    /// relay on the same root+doc is refused by the pre-existing RSC-S02 guard even
    /// when it names a DIFFERENT id than the live relay's — the child re-runs the full
    /// guarded `run(config:id:)` path every time.
    func testRunWithSuppliedIdRefusesDuplicateStartOnSameRootAndDoc() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        // A genuinely live relay already occupies this root+doc — `save()` stamps
        // owner.pid with THIS test process's own pid, so `isOwnerDead` reads it alive.
        let live = LoopState(
            id: "relay_legit_start", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(live)

        let (service, runner) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev", maxRounds: 5
        )

        // A stray `pair relay --no-wait` duplicate start racing the same root+doc as
        // the live relay above.
        let strayResult = await coordinator.run(config: config, id: "relay_stray_duplicate_start")
        guard case .failure(let refusal) = strayResult else { return XCTFail("expected the stray duplicate start to be refused") }
        XCTAssertEqual(refusal, .alreadyActive(loopId: "relay_legit_start"))
        XCTAssertNil(stateStore.load(id: "relay_stray_duplicate_start"), "the refused duplicate must never have been created")
        XCTAssertEqual(runner.callCount(for: "pm_cli"), 0)
        XCTAssertEqual(stateStore.list().count, 1, "no second relay landed on disk")
    }

    /// `run(config:id:)` — RSC-S03's pre-minted id for `pair relay --no-wait` — uses
    /// the SUPPLIED id verbatim instead of `idFactory()`, so a foreground caller's
    /// dispatch ack names the exact id the (detached) real dispatch is about to create.
    func testRunWithPreMintedIdUsesSuppliedIdInsteadOfIdFactory() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let pmScripts: [MockCommandRunner.Script] = [.init(stdout: "Done.\n\n" + verdictJSON("done", note: "ok"))]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        // idFactory would produce a DIFFERENT id than the one explicitly supplied —
        // proving `id:` wins, not merely that idFactory happens to agree with it.
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_from_factory_should_not_be_used" }
        )
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let result = await coordinator.run(config: config, id: "relay_preminted")
        guard case .success(let state) = result else { return XCTFail("expected success") }
        XCTAssertEqual(state.id, "relay_preminted")
        XCTAssertNotNil(stateStore.load(id: "relay_preminted"))
        XCTAssertNil(stateStore.load(id: "relay_from_factory_should_not_be_used"))
    }

    /// `LoopCoordinator.mintLoopId()` — the format `pair relay --no-wait`'s
    /// foreground pre-mint step uses — matches the coordinator's own default
    /// `idFactory` format (`"relay_" + lowercase UUID`), so a caller minting one
    /// externally can never drift from what `run(config:)` would have generated on
    /// its own.
    func testMintRelayIdMatchesDefaultIdFactoryFormat() {
        let minted = LoopCoordinator.mintLoopId()
        XCTAssertTrue(minted.hasPrefix("relay_"))
        let uuidPart = String(minted.dropFirst("relay_".count))
        XCTAssertEqual(uuidPart, uuidPart.lowercased())
        XCTAssertNotNil(UUID(uuidString: uuidPart))
    }

    // MARK: - RSC-S01: cross-process dispatch lock

    /// Two concurrent `resume` calls on the same relay id: exactly one dispatches a
    /// dev turn (via the PM's `done` verdict), the other is refused with
    /// `.roundInFlight` because it cannot take the dispatch lock. Simulates the second
    /// caller by holding the lock directly (`LoopDispatchLock.tryAcquire`) — the same
    /// primitive `LoopCoordinator.resume` itself contends on — while the first
    /// `resume` is in its read-check-write window.
    func testConcurrentResumeCallsYieldExactlyOneDispatchTheOtherRoundInFlight() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let state = LoopState(
            id: "relay_concurrent_resume", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .escalated,
            createdAt: Date(), note: "which env?"
        )
        try stateStore.save(state)

        // Hold the SAME lock a real racing `resume` call would contend on.
        var heldLock = LoopDispatchLock.tryAcquire(loopId: "relay_concurrent_resume", loopsRoot: stateStore.rootDirectory)
        XCTAssertNotNil(heldLock, "precondition: lock must be free before the simulated race")

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let racedResult = await coordinator.resume(loopId: "relay_concurrent_resume", founderAnswer: "use staging", config: config)
        guard case .failure(let error) = racedResult else { return XCTFail("expected failure while the lock is held") }
        XCTAssertEqual(error, .roundInFlight)
        // The lock loser must never have mutated durable state.
        XCTAssertEqual(stateStore.load(id: "relay_concurrent_resume")?.status, .escalated)

        // Release the simulated holder — dropping the last reference triggers
        // `ThreadFlockLock.Handle.deinit` (`flock(LOCK_UN)` + `close`).
        heldLock = nil

        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Using staging.\n\n" + verdictJSON("done", note: "Shipped to staging.")),
        ]
        let (service2, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator2 = LoopCoordinator(runService: service2, stateStore: stateStore, runStore: runStore)
        let secondResult = await coordinator2.resume(loopId: "relay_concurrent_resume", founderAnswer: "use staging", config: config)
        guard case .success(let resumed) = secondResult else { return XCTFail("expected success once the lock is released") }
        XCTAssertEqual(resumed.status, .done)
    }

    /// A stale lock file left by a process that has since died does not block a fresh
    /// acquire — a real child process (`python3`, always present on macOS, no compile
    /// step) `flock`s the SAME lock file `LoopDispatchLock` uses, is `kill -9`'d, and a
    /// fresh `resume` on the same relay id then succeeds. This is the host-boundary
    /// claim the spec calls out as needing a real process, not a mock: `flock`
    /// releases automatically when the holding process dies, with no cooperative
    /// unlock — exactly why a crashed dispatcher can never wedge a relay.
    func testStaleLockFromADeadProcessDoesNotBlockAFreshAcquire() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let state = LoopState(
            id: "relay_stale_lock", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .escalated,
            createdAt: Date(), note: "which env?"
        )
        try stateStore.save(state)

        let lockURL = LoopDispatchLock.lockURL(loopId: "relay_stale_lock", loopsRoot: stateStore.rootDirectory)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let holderScript = """
        import os, fcntl, time
        fd = os.open(\(pythonStringLiteral(lockURL.path)), os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        while True:
            time.sleep(3600)
        """
        let scriptURL = tmp.appendingPathComponent("hold_lock.py")
        try holderScript.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        // Poll (in-process) with the SAME primitive `resume` contends on, until the
        // child has actually taken the flock — no IPC readiness signal needed.
        var childHoldsLock = false
        for _ in 0..<200 {
            if let probe = LoopDispatchLock.tryAcquire(loopId: "relay_stale_lock", loopsRoot: stateStore.rootDirectory) {
                _ = probe // free — child hasn't locked yet; release and retry
                try await Task.sleep(nanoseconds: 15_000_000)
                continue
            }
            childHoldsLock = true
            break
        }
        XCTAssertTrue(childHoldsLock, "precondition: the child process must actually hold the flock")

        // While held, a resume attempt is refused.
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let blockedResult = await coordinator.resume(loopId: "relay_stale_lock", founderAnswer: "use staging", config: config)
        guard case .failure(let blockedError) = blockedResult else { return XCTFail("expected failure while the child holds the lock") }
        XCTAssertEqual(blockedError, .roundInFlight)

        // Kill -9 the holder — the kernel releases its flock immediately, no cooperative unlock.
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()

        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Using staging.\n\n" + verdictJSON("done", note: "Shipped to staging.")),
        ]
        let (service2, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator2 = LoopCoordinator(runService: service2, stateStore: stateStore, runStore: runStore)

        // The stale flock releases the instant the process dies, but give the reaped
        // process table a brief moment to settle; poll rather than assert on one tick.
        var settled: LoopState?
        for _ in 0..<50 {
            let result = await coordinator2.resume(loopId: "relay_stale_lock", founderAnswer: "use staging", config: config)
            if case .success(let resumedState) = result { settled = resumedState; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(settled?.status, .done, "a stale lock from a dead process must never wedge the relay")
    }

    // MARK: - RSC-S02: duplicate start guard

    /// `preflightStart` in isolation (no lock, no coordinator, mirrors how
    /// `preflightExternalRound` is unit-tested directly) — the three shapes a bare scan
    /// must get right: a live `.running` match refuses; a non-matching doc on the same
    /// root does not; a dead-owner `.running` relay does not.
    func testPreflightStartDirectScanShapes() throws {
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        try stateStore.save(LoopState(
            id: "relay_live", projectRoot: "/repo/a", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        ))

        let liveMatch = LoopCoordinator.preflightStart(
            projectRoot: "/repo/a", docPath: "docs/spec.md", stateStore: stateStore
        )
        guard case .failure(.alreadyActive(let id)) = liveMatch else { return XCTFail("expected alreadyActive") }
        XCTAssertEqual(id, "relay_live")

        let differentDoc = LoopCoordinator.preflightStart(
            projectRoot: "/repo/a", docPath: "docs/other.md", stateStore: stateStore
        )
        guard case .success = differentDoc else { return XCTFail("expected success for a non-matching doc") }

        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let projector = LoopThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(id: "relay_dead_owner", projectRoot: "/repo/b", stateStore: stateStore, projector: projector)
        let deadOwnerMatch = LoopCoordinator.preflightStart(
            projectRoot: "/repo/b", docPath: "docs/spec.md", stateStore: stateStore
        )
        guard case .success = deadOwnerMatch else { return XCTFail("expected success — a dead-owner .running relay is not a live duplicate") }

        let dotSlashMatch = LoopCoordinator.preflightStart(
            projectRoot: "/repo/a", docPath: "./docs/spec.md", stateStore: stateStore
        )
        guard case .failure(.alreadyActive(let id)) = dotSlashMatch else { return XCTFail("expected alreadyActive for ./docs prefix") }
        XCTAssertEqual(id, "relay_live")
    }

    /// A second `pair relay` start on the SAME normalized root + doc while the first is
    /// genuinely live (`.running`, owner alive) is refused with `.alreadyActive` naming
    /// the existing relay id — never a second, independently-dispatching relay against
    /// the same repo.
    func testSecondStartOnSameRootAndDocWhileFirstIsLiveIsRefused() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        // `save()` stamps owner.pid with THIS test process's own pid for a `.running`
        // save — `isOwnerDead` reads that as alive, exactly like a genuinely live relay.
        let existing = LoopState(
            id: "relay_first", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(existing)

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let result = await coordinator.run(config: config)
        guard case .failure(let refusal) = result else { return XCTFail("expected failure while a live relay is active") }
        XCTAssertEqual(refusal, .alreadyActive(loopId: "relay_first"))
        // The refused start must never have created (or mutated) a second relay.
        XCTAssertEqual(stateStore.list().count, 1)
        XCTAssertEqual(stateStore.load(id: "relay_first")?.status, .running)
    }

    /// A `.running` relay whose owner process has died (an orphan — `reconcileOrphan`'s
    /// job, not this guard's) must NEVER block a new start; it is not a live duplicate.
    func testDeadOwnerRunningRelayDoesNotBlockANewStart() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = LoopThreadProjector(store: threadStore, runStore: runStore)
        try makeOrphanedRunningRelay(id: "relay_orphan_start", projectRoot: repo.path, stateStore: stateStore, projector: projector)

        let pmScripts: [MockCommandRunner.Script] = [
            .init(stdout: "Fresh start beside an orphan.\n\n" + verdictJSON("done", note: "Shipped.")),
        ]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_new_after_orphan" }
        )
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let result = await coordinator.run(config: config)
        guard case .success(let state) = result else {
            return XCTFail("expected success — a dead-owner .running relay is an orphan, not a live duplicate")
        }
        XCTAssertEqual(state.id, "relay_new_after_orphan")
        XCTAssertEqual(state.status, .done)
    }

    /// Two relays against the SAME root but DIFFERENT docs never contend — the guard
    /// keys on root + doc together, not root alone.
    func testDifferentDocPathSameRootIsAllowed() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let existing = LoopState(
            id: "relay_doc_a", projectRoot: repo.path, docPath: "docs/a.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(existing)

        let pmScripts: [MockCommandRunner.Script] = [.init(stdout: "Different doc.\n\n" + verdictJSON("done", note: "ok"))]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = LoopCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            idFactory: { "relay_doc_b" }
        )
        let config = LoopCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/b.md", pmModelId: "model_pm", devModelId: "model_dev"
        )
        let result = await coordinator.run(config: config)
        guard case .success(let state) = result else {
            return XCTFail("expected success — different doc, same root, must never be treated as a duplicate")
        }
        XCTAssertEqual(state.status, .done)
    }

    /// A parked relay (`awaitingPM` — a Pilot relay between rounds, or `escalated` — a
    /// real founder question) on the SAME root + doc must never block a new start:
    /// parked relays need `resume`/`adopt`, and Pilot relays can sit `awaitingPM` for
    /// days by design.
    func testParkedRelayAwaitingPMOrEscalatedDoesNotBlockANewStart() async throws {
        let repo = try makeGitRepo()
        for (label, status, isCallerChair) in [
            ("awaiting_pm", LoopState.Status.awaitingPM, true),
            ("escalated", LoopState.Status.escalated, false),
        ] {
            let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-\(label)"))
            let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("relays-\(label)"))
            let parked = LoopState(
                id: "relay_parked_\(label)", projectRoot: repo.path, docPath: "docs/spec.md",
                pmModelId: isCallerChair ? LoopState.callerPMModelId : "model_pm",
                devModelId: "model_dev", status: status, createdAt: Date(),
                note: status == .escalated ? "which env?" : nil
            )
            try stateStore.save(parked)

            let pmScripts: [MockCommandRunner.Script] = [
                .init(stdout: "New start beside a parked relay.\n\n" + verdictJSON("done", note: "ok")),
            ]
            let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
            let coordinator = LoopCoordinator(
                runService: service, stateStore: stateStore, runStore: runStore,
                idFactory: { "relay_new_beside_\(label)" }
            )
            let config = LoopCoordinator.Config(
                projectRoot: repo.path, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
            )
            let result = await coordinator.run(config: config)
            guard case .success(let state) = result else {
                return XCTFail("expected success — a parked (\(label)) relay must never block a new start")
            }
            XCTAssertEqual(state.status, .done)
        }
    }

    /// Root normalization actually matters: a live relay saved against the repo's
    /// canonical path is still caught when the NEW start's `projectRoot` is spelled
    /// with a trailing slash, a `..` component, or a symlink that resolves to the same
    /// key — never a bare exact-string comparison.
    func testRootNormalizationCatchesTrailingSlashDotDotAndSymlinkSpellings() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let existing = LoopState(
            id: "relay_canonical", projectRoot: repo.path, docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(existing)

        let symlink = tmp.appendingPathComponent("repo-symlink")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: repo)

        // Every component along this path actually exists (`repo`, then back up via
        // `..` into `repo`'s own parent, then forward into `repo` again) — a `..`
        // segment through a NON-existent directory is not a reliable normalization
        // probe (`resolvingSymlinksInPath` only promises to resolve what is really
        // there), so this stays inside real, already-created directories.
        let sneakyDotDot = repo
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(repo.lastPathComponent, isDirectory: true)

        let spellings: [String] = [
            repo.path + "/",
            sneakyDotDot.path,
            symlink.path,
        ]
        for spelling in spellings {
            let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
            let coordinator = LoopCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
            let config = LoopCoordinator.Config(
                projectRoot: spelling, docPath: "docs/spec.md", pmModelId: "model_pm", devModelId: "model_dev"
            )
            let result = await coordinator.run(config: config)
            guard case .failure(let refusal) = result else {
                return XCTFail("spelling '\(spelling)' must normalize to the SAME key as the canonical root and be refused")
            }
            XCTAssertEqual(refusal, .alreadyActive(loopId: "relay_canonical"), "spelling: \(spelling)")
        }
        XCTAssertEqual(stateStore.list().count, 1, "none of the differently-spelled attempts may have created a new relay")
    }
}

/// Minimal Python string-literal escaping for the one path we splice into the
/// spawned holder script above (test-only; not a general-purpose escaper).
private func pythonStringLiteral(_ raw: String) -> String {
    "r\"\"\"\(raw)\"\"\""
}

// MARK: - LoopStateStore

final class LoopStateStoreTests: HermeticSupportTestCase {
    func testSaveLoadRoundTripAndList() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LoopStateStore(rootDirectory: tmp)
        let fixedNow = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var round = RelayRound(roundNumber: 1, baselineHead: "abc123", startedAt: fixedNow)
        round.verdict = LoopVerdict(verdict: .continueRelay, handover: "do it")
        round.gate = RelayGateSummary(allowed: true)
        var state = LoopState(
            id: "relay_roundtrip", projectRoot: "/tmp/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running,
            rounds: [round], createdAt: fixedNow
        )
        try store.save(state)

        let loaded = store.load(id: "relay_roundtrip")
        XCTAssertEqual(loaded, state)

        state.status = .done
        state.note = "closing"
        try store.save(state)
        XCTAssertEqual(store.load(id: "relay_roundtrip")?.note, "closing")

        XCTAssertEqual(store.list().map(\.id), ["relay_roundtrip"])
    }

    func testLoadMissingReturnsNil() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-missing-\(UUID().uuidString)")
        let store = LoopStateStore(rootDirectory: tmp)
        XCTAssertNil(store.load(id: "does_not_exist"))
        XCTAssertEqual(store.list(), [])
    }

    // MARK: - owner.pid liveness marker (works-test hazard #1; mirrors RunStore)

    func testRunningSaveWritesOwnerPidThenTerminalSaveClearsIt() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LoopStateStore(rootDirectory: tmp)
        let ownerURL = tmp.appendingPathComponent("relay_owner").appendingPathComponent("owner.pid")
        var state = LoopState(
            id: "relay_owner", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try store.save(state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerURL.path), "a running relay records its owner pid")
        XCTAssertEqual(String(decoding: (try? Data(contentsOf: ownerURL)) ?? Data(), as: UTF8.self),
                       "\(ProcessInfo.processInfo.processIdentifier)")

        state.status = .done
        try store.save(state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerURL.path), "a terminal save clears the marker")
    }

    func testIsOwnerDeadTrueWhenMarkerMissingOrDeadFalseWhenAlive() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relaystore-dead-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = LoopStateStore(rootDirectory: tmp)

        // No relay folder at all — missing counts as dead (never assumed alive without proof).
        XCTAssertTrue(store.isOwnerDead(id: "relay_never_saved"))

        // A live owner (this test process) is not dead.
        let live = LoopState(
            id: "relay_live", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running, createdAt: Date()
        )
        try store.save(live)
        XCTAssertFalse(store.isOwnerDead(id: "relay_live"))

        // A marker naming a pid well above macOS's max — dead (mirrors
        // RunStoreJournalTests' `testOrphanWithDeadPidResolvesToInterrupted`).
        try Data("2000000".utf8).write(to: tmp.appendingPathComponent("relay_live").appendingPathComponent("owner.pid"))
        XCTAssertTrue(store.isOwnerDead(id: "relay_live"))
    }
}

// MARK: - LoopTurnClassifier

final class LoopTurnClassifierTests: HermeticSupportTestCase {
    func testDeliveredOnDoneWithOutput() {
        let outcome = WorkerRunOutcome(status: .done, output: "the answer")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .delivered(output: "the answer"))
    }

    func testEmptyResultOnDoneWithBlankOutput() {
        let outcome = WorkerRunOutcome(status: .done, output: "   \n")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .emptyResult)
    }

    func testCompactionNeverClassifiedAsStalled() {
        let outcome = WorkerRunOutcome(status: .failed, output: "context compaction in progress, please retry")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .compacting)
    }

    func testCompactionMarkerInReasoningAlsoWins() {
        let outcome = WorkerRunOutcome(status: .timedOut, reasoning: "running compaction now")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .compacting)
    }

    func testInfraBackoffFromStructuredCapacityFact() {
        let observation = CapacityObservation(
            kind: .accountRateLimit, source: "pm_cli", sourceConfidence: .structured,
            rawSnippet: "rate limited", observedAt: Date())
        let outcome = WorkerRunOutcome(status: .failed, capacityObservation: observation)
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .infraBackoff)
    }

    func testInfraBackoffFromTextSniff() {
        let outcome = WorkerRunOutcome(status: .failed, errorReason: "429 rate limit exceeded")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .infraBackoff)
    }

    func testStalledOnNotDoneWithoutInfraOrCompactionMarker() {
        let outcome = WorkerRunOutcome(status: .failed, errorReason: "unexpected exit")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .stalled)
    }

    /// SR-7 (Sol F23): a bare `"busy"` in an application error must NOT be read as provider
    /// backoff — otherwise a mutating dev turn is retried up to 10× and can repeat side
    /// effects. This one is `.stalled` (escalates), not `.infraBackoff` (retries).
    func testDatabaseBusyIsNotInfraBackoff() {
        let outcome = WorkerRunOutcome(status: .failed, errorReason: "sqlite: database is busy")
        XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .stalled)
    }

    /// SR-7 guard: genuine provider backoff phrasings still classify as `.infraBackoff`.
    func testProviderBusyPhrasingsStillInfraBackoff() {
        for reason in ["server is busy, try again", "the model is busy", "service temporarily unavailable", "overloaded_error"] {
            let outcome = WorkerRunOutcome(status: .failed, errorReason: reason)
            XCTAssertEqual(LoopTurnClassifier.classify(.init(outcome: outcome)), .infraBackoff, "reason: \(reason)")
        }
    }
}

/// Trivial `Sendable` mutable box for capturing a value inside an `@Sendable` events
/// closure (the events sink runs synchronously on whatever task calls it, but the
/// compiler can't see that without a lock).
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ initial: T) { stored = initial }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

// MARK: - Test double

/// A `CommandRunner` double keyed by command name, extending `MockCommandRunner`'s shape
/// (reuses its `Script`) with two things a relay's multi-turn-per-command loop needs that
/// a single static script can't express: (1) a DIFFERENT scripted answer per successive
/// call to the same command (`queues[command]` is consumed in order, repeating the last
/// entry once exhausted — mirrors `PairCoordinatorTests`' bespoke counting runners), and
/// (2) captured args per call, so a test can assert on the ACTUAL prompt text a turn
/// received (e.g. a resumed relay's founder note reaching the PM prompt).
final class SequencedCommandRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: [MockCommandRunner.Script]]
    private var counts: [String: Int] = [:]
    private var captured: [String: [[String]]] = [:]

    init(queues: [String: [MockCommandRunner.Script]]) {
        self.queues = queues
    }

    func enqueue(command: String, _ script: MockCommandRunner.Script) {
        lock.withLock { queues[command, default: []].append(script) }
    }

    func callCount(for command: String) -> Int {
        lock.withLock { counts[command, default: 0] }
    }

    func capturedArgs(for command: String) -> [[String]] {
        lock.withLock { captured[command, default: []] }
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        let script: MockCommandRunner.Script = lock.withLock {
            let index = counts[command, default: 0]
            counts[command] = index + 1
            captured[command, default: []].append(args)
            let scripts = queues[command] ?? []
            return scripts.isEmpty ? MockCommandRunner.Script() : scripts[min(index, scripts.count - 1)]
        }

        if let launchError = script.launchError {
            return CommandResult(launchError: launchError)
        }
        try? await Task.sleep(for: script.delay)
        if script.forcesTimeout { return CommandResult(timedOut: true) }
        return CommandResult(stdout: script.stdout, stderr: script.stderr, exitCode: script.exitCode)
    }
}

/// Routes PM vs dev CLI invocations in relay coordinator tests.
final class LoopTestCommandRouter: CommandRunner, @unchecked Sendable {
    private let pm: CommandRunner
    private let dev: CommandRunner

    init(pm: CommandRunner, dev: CommandRunner) {
        self.pm = pm
        self.dev = dev
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        switch command {
        case "pm_cli":
            return await pm.run(command: command, args: args, stdin: stdin, env: env, workingDirectory: workingDirectory, timeout: timeout)
        case "dev_cli":
            return await dev.run(command: command, args: args, stdin: stdin, env: env, workingDirectory: workingDirectory, timeout: timeout)
        default:
            return CommandResult(stdout: "", stderr: "unknown command", exitCode: 1)
        }
    }
}

/// PO-F7: wraps a `CommandRunner` and records the `timeout` passed to its last call —
/// proves `Config.devTurnIdleTimeoutSeconds` reaches `RunRequest.workerTimeoutSeconds`
/// on the actual dev-turn dispatch (mirrors `RunIdleTimeoutTests.TimeoutCapturingStreamingRunner`).
final class TimeoutCapturingCommandRunner: CommandRunner, @unchecked Sendable {
    private let inner: CommandRunner
    private let lock = NSLock()
    private var captured: Duration?

    init(inner: CommandRunner) {
        self.inner = inner
    }

    var lastTimeout: Duration? { lock.withLock { captured } }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        lock.withLock { captured = timeout }
        return await inner.run(command: command, args: args, stdin: stdin, env: env, workingDirectory: workingDirectory, timeout: timeout)
    }
}

/// Fake mutating dev worker: commits in the repo, then returns a non-zero exit so the
/// relay classifier sees `.stalled` even though delivery already happened.
final class CommittingThenStallingCommandRunner: CommandRunner, @unchecked Sendable {
    private let repoRoot: URL
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int { lock.withLock { calls } }

    init(repoRoot: URL) {
        self.repoRoot = repoRoot
    }

    func run(
        command: String, args: [String], stdin: String?, env: [String: String],
        workingDirectory: String?, timeout: Duration
    ) async -> CommandResult {
        _ = command
        _ = args
        _ = stdin
        _ = env
        _ = workingDirectory
        _ = timeout
        lock.withLock { calls += 1 }
        let file = repoRoot.appendingPathComponent("worker-change.txt")
        try? "worker change".write(to: file, atomically: true, encoding: .utf8)
        runGit(["add", "worker-change.txt"], cwd: repoRoot)
        runGit(["commit", "-q", "-m", "worker: test change"], cwd: repoRoot)
        return CommandResult(stdout: "committed but stalled", stderr: "", exitCode: 1)
    }

    private func runGit(_ args: [String], cwd: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd.path] + args
        p.standardOutput = Pipe(); p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}
