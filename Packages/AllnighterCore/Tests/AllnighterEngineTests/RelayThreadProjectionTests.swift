import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// R-S07 works test: `RelayThreadProjector` wired into `RelayCoordinator` via the
/// optional-collaborator seam — one `WorkThread` per relay, rounds as turns, escalation
/// raising `needsAttention` through the thread model's existing derived rules (never a
/// new stored flag). Mirrors `RelayCoordinatorTests`' fixture shape (scripted
/// `CommandRunner`, real git repo) so these tests exercise the SAME dispatch path, just
/// asserting on the projected `WorkThread` instead of (or alongside) `RelayState`.
final class RelayThreadProjectionTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relay-thread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures (mirrors RelayCoordinatorTests)

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

    private func verdictJSON(_ verdict: String, handover: String? = nil, note: String? = nil) -> String {
        var fields = ["\"verdict\": \"\(verdict)\""]
        if let handover { fields.append("\"handover\": \"\(handover)\"") }
        if let note { fields.append("\"note\": \"\(note)\"") }
        return "```json\n{\(fields.joined(separator: ", "))}\n```"
    }

    /// Everything one test needs: a `RelayCoordinator` wired to a real `ThreadStore` +
    /// `RunStore` + `RelayStateStore` under `tmp`, and the projector reading back the
    /// SAME `RunStore`/`ThreadStore` roots — exactly the invariant
    /// `RelayDispatch.makeCoordinator` relies on in production.
    private struct Rig {
        let coordinator: RelayCoordinator
        let threadStore: ThreadStore
        let runner: SequencedCommandRunner
    }

    private func makeRig(
        pmScripts: [MockCommandRunner.Script],
        devScripts: [MockCommandRunner.Script],
        idFactory: @escaping @Sendable () -> String = { "relay_thread_test" }
    ) -> Rig {
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "pm_cli", role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "pm_cli", command: "pm_cli"),
            TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: ["pm_cli": pmScripts, "dev_cli": devScripts])
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
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
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = RelayThreadProjector(store: threadStore, runStore: runStore)
        let coordinator = RelayCoordinator(
            runService: service,
            stateStore: RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays")),
            runStore: runStore,
            threadProjector: projector,
            idFactory: idFactory
        )
        return Rig(coordinator: coordinator, threadStore: threadStore, runner: runner)
    }

    // MARK: - Relay start creates a bound thread

    func testRelayStartCreatesThreadBoundToProject() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(
            pmScripts: [.init(stdout: "Reviewed.\n\n" + verdictJSON("done", note: "Shipped."))],
            devScripts: []
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, projectId: "proj_relay_1", docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let state = try await rig.coordinator.run(config: config).get()

        let thread = rig.threadStore.get(state.id)
        XCTAssertNotNil(thread, "the relay's thread id must equal the relay id")
        XCTAssertEqual(thread?.projectId, "proj_relay_1")
        XCTAssertEqual(thread?.title, "PM Relay: PM Relay")
        XCTAssertEqual(thread?.workingDir, repo.path)
    }

    // MARK: - A completed round appends PM + dev turns verbatim with run refs

    func testCompletedRoundAppendsPMAndDevTurnsVerbatimWithRunIds() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(
            pmScripts: [
                .init(stdout: "Round 1 review text.\n\n" + verdictJSON("continue", handover: "Implement the thing.")),
                .init(stdout: "Round 2 review, all good.\n\n" + verdictJSON("done", note: "Shipped it.")),
            ],
            devScripts: [.init(stdout: "Implemented exactly that. Committed.")]
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 5
        )
        let state = try await rig.coordinator.run(config: config).get()
        XCTAssertEqual(state.status, .done)

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        let pm1 = try XCTUnwrap(thread.turn(id: "\(state.id)_pm1"))
        XCTAssertEqual(pm1.status, .done)
        XCTAssertEqual(pm1.author, .worker)
        XCTAssertEqual(pm1.workerId, "model_pm")
        XCTAssertEqual(pm1.kind, .workerChat)
        XCTAssertEqual(pm1.runId, state.rounds[0].pmRunId)
        XCTAssertTrue(pm1.text?.contains("Round 1 review text.") ?? false, "PM turn text is verbatim, not summarized")
        XCTAssertTrue(pm1.text?.contains("\"verdict\"") ?? false, "verbatim means the raw output, verdict tail included")

        let dev1 = try XCTUnwrap(thread.turn(id: "\(state.id)_dev1"))
        XCTAssertEqual(dev1.status, .done)
        XCTAssertEqual(dev1.workerId, "model_dev")
        XCTAssertEqual(dev1.runId, state.rounds[0].devRunId)
        XCTAssertEqual(dev1.text, "Implemented exactly that. Committed.")

        let pm2 = try XCTUnwrap(thread.turn(id: "\(state.id)_pm2"))
        XCTAssertEqual(pm2.status, .done)
        XCTAssertTrue(pm2.text?.contains("Round 2 review, all good.") ?? false)
        // Round 2's verdict is `done` — no dev turn ever dispatches for that round.
        XCTAssertNil(thread.turn(id: "\(state.id)_dev2"))
    }

    // MARK: - Escalation raises needsAttention; resume clears it

    func testEscalationRaisesNeedsAttentionAndResumeClearsIt() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(
            pmScripts: [
                .init(stdout: "Need input.\n\n" + verdictJSON("escalate", note: "staging or prod?")),
            ],
            devScripts: []
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let escalated = try await rig.coordinator.run(config: config).get()
        XCTAssertEqual(escalated.status, .escalated)

        var thread = try XCTUnwrap(rig.threadStore.get(escalated.id))
        XCTAssertTrue(thread.needsAttention, "an open relay_escalated system event must derive needsAttention")
        let escTurn = try XCTUnwrap(thread.turn(id: "\(escalated.id)_escalate1"))
        XCTAssertEqual(escTurn.kind, .systemEvent)
        XCTAssertEqual(escTurn.systemEvent, .relayEscalated)
        XCTAssertEqual(escTurn.status, .running, "open and blocking, mirroring signInRequired/manualPaste")
        XCTAssertEqual(escTurn.text, "staging or prod?")

        // Resume: PM now delivers `done`.
        rig.runner.enqueue(command: "pm_cli", .init(stdout: "Using staging.\n\n" + verdictJSON("done", note: "Shipped to staging.")))
        let resumedConfig = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", maxRounds: 5
        )
        let resumedResult = await rig.coordinator.resume(
            relayId: escalated.id, founderAnswer: "use staging", config: resumedConfig
        )
        guard case .success(let resumed) = resumedResult else { return XCTFail("expected success") }
        XCTAssertEqual(resumed.status, .done)

        thread = try XCTUnwrap(rig.threadStore.get(resumed.id))
        XCTAssertFalse(thread.needsAttention, "resume must clear the open escalation note")
        let clearedEscTurn = try XCTUnwrap(thread.turn(id: "\(escalated.id)_escalate1"))
        XCTAssertEqual(clearedEscTurn.status, .done, "settled, not deleted — a durable receipt of what was asked")
        XCTAssertFalse(thread.isRunning)
    }

    // MARK: - Done settles the thread cleanly

    func testDoneSettlesThreadCleanlyWithNoExtraSystemEvent() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(
            pmScripts: [.init(stdout: "All good.\n\n" + verdictJSON("done", note: "Nothing left."))],
            devScripts: []
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let state = try await rig.coordinator.run(config: config).get()
        XCTAssertEqual(state.status, .done)

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention)
        XCTAssertEqual(thread.turns.count, 1, "just the settled PM turn — done needs no extra system event")
    }

    // MARK: - Stopped (ceiling) records a system event with the stoppedReason

    func testCeilingStopRecordsSystemEventWithStoppedReason() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(
            pmScripts: [.init(stdout: "Keep going.\n\n" + verdictJSON("continue", handover: "Keep building."))],
            devScripts: [.init(stdout: "Some progress, no commit this time.")]
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev",
            maxRounds: 1, stagnationRoundCap: 10
        )
        let state = try await rig.coordinator.run(config: config).get()
        XCTAssertEqual(state.status, .stopped)

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        let stoppedTurn = try XCTUnwrap(thread.turn(id: "\(state.id)_stopped"))
        XCTAssertEqual(stoppedTurn.kind, .systemEvent)
        XCTAssertEqual(stoppedTurn.systemEvent, .relayStopped)
        XCTAssertEqual(stoppedTurn.status, .done, "terminal ceiling stop is never resumable, so never blocking")
        XCTAssertEqual(stoppedTurn.text, state.stoppedReason)
        XCTAssertFalse(thread.needsAttention)
        XCTAssertFalse(thread.isRunning)
    }

    // MARK: - No thread store attached: relay still runs (headless/tests)

    func testRelayRunsUnchangedWithNoThreadProjectorAttached() async throws {
        let repo = try makeGitRepo()
        let pmModel = Model(id: "model_pm", displayName: "PM", modelLabel: "pm", driverId: "pm_cli", role: .both)
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([
            TestSupport.headlessManifest(id: "pm_cli", command: "pm_cli"),
            TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli"),
        ])
        let runner = SequencedCommandRunner(queues: [
            "pm_cli": [.init(stdout: "Done.\n\n" + verdictJSON("done", note: "ok"))],
        ])
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let service = RunService(
            models: [pmModel, devModel], registry: registry, runStore: runStore,
            commandRunner: runner, writeLock: RunWriteLockRegistry(),
            defaultSettings: { DefaultModelSettings() },
            probeRecords: {
                [
                    ToolProbeRecord(driverId: "pm_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                    ToolProbeRecord(driverId: "dev_cli", status: .ready(version: "1"), lastProbeAt: .distantPast),
                ]
            }
        )
        // No `threadProjector:` argument at all — defaults to nil.
        let coordinator = RelayCoordinator(
            runService: service,
            stateStore: RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays")),
            runStore: runStore
        )
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/phases/PM_Relay.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev"
        )
        let state = try await coordinator.run(config: config).get()
        XCTAssertEqual(state.status, .done, "the relay must not depend on a thread store being attached")
    }

    // MARK: - Title derivation

    func testTitleFromDocPath() {
        XCTAssertEqual(RelayThreadProjector.title(forDocPath: "docs/phases/PM_Relay.md"), "PM Relay: PM Relay")
        XCTAssertEqual(RelayThreadProjector.title(forDocPath: "docs/phases/foo-bar.md"), "PM Relay: foo bar")
        XCTAssertEqual(RelayThreadProjector.title(forDocPath: ""), "PM Relay")
    }
}
