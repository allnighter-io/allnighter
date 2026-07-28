import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PL-S06 works tests (`docs/phases/Pilot_Relay.md` §5 "adopt (unattended handover) is the
/// strategic unlock"): `RelayCoordinator.adopt` converts a PARKED pilot relay to a
/// spawned PM relay and continues the SAME round log; `RelayCoordinator.adoptToPilot` is
/// the trivial reverse flip. Fixtures mirror `RelayCoordinatorTests`/`PilotCoordinatorTests`
/// (real git repo, scripted CLIs only, `SequencedCommandRunner` from
/// `RelayCoordinatorTests.swift` for per-call arg capture).
final class RelayAdoptTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-relay-adopt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures (mirrors RelayCoordinatorTests / PilotCoordinatorTests)

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
        devDriverId: String = "dev_cli"
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
            commandRunner: runner,
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

    /// Starts a pilot relay and runs ONE `continue` round to completion (dev delivers),
    /// leaving it parked `awaitingPM` — the common setup every "adopt from awaitingPM"
    /// test needs.
    private func makePilotedOneRoundRelay(
        id: String, repo: URL, stateStore: RelayStateStore, runStore: RunStore,
        devReport: String = "Implemented the thing. Verified with `pytest`.",
        threadProjector: RelayThreadProjector? = nil
    ) async -> (RelayCoordinator, SequencedCommandRunner) {
        let (service, runner) = makeService(pmScripts: [], devScripts: [.init(stdout: devReport)], runStore: runStore)
        let coordinator = RelayCoordinator(
            runService: service, stateStore: stateStore, runStore: runStore,
            threadProjector: threadProjector, idFactory: { id }
        )
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))
        let submission = "Reviewed the repo myself.\n\n" + verdictJSON("continue", handover: "Implement the thing.")
        _ = await coordinator.runExternalRound(relayId: id, submission: submission)
        return (coordinator, runner)
    }

    // MARK: - adopt: happy path, awaitingPM → spawned, loop continues

    func testAdoptConvertsAwaitingPMPilotRelayAndContinuesSpawnedLoop() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (_, devRunner) = await makePilotedOneRoundRelay(id: "relay_adopt_happy", repo: repo, stateStore: stateStore, runStore: runStore)
        XCTAssertEqual(stateStore.load(id: "relay_adopt_happy")?.status, .awaitingPM)

        // Re-point the SAME coordinator's underlying service at a fresh PM script queue
        // by building a new coordinator sharing the same stores — mirrors how a real
        // `alln pair relay adopt` invocation is a brand-new process each time.
        let (adoptedService, adoptedRunner) = makeService(
            pmScripts: [.init(stdout: "Reviewed the adopted round.\n\n" + verdictJSON("done", note: "All criteria met."))],
            devScripts: [], runStore: runStore
        )
        let adoptCoordinator = RelayCoordinator(runService: adoptedService, stateStore: stateStore, runStore: runStore)

        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "ignored-overridden", devWorkerId: "ignored-overridden", maxRounds: 5
        )
        let result = await adoptCoordinator.adopt(relayId: "relay_adopt_happy", pmWorkerId: "model_pm", config: config)
        guard case .success(let state) = result else { return XCTFail("expected success") }

        XCTAssertEqual(state.pmMode, .spawned)
        XCTAssertEqual(state.pmWorkerId, "model_pm")
        XCTAssertEqual(state.status, .done)
        XCTAssertEqual(state.note, "All criteria met.")
        XCTAssertEqual(state.rounds.count, 2, "the piloted round is never discarded")

        let pilotedRound = state.rounds[0]
        XCTAssertNotNil(pilotedRound.externalSubmission, "piloted round's run-truth stays verbatim")
        XCTAssertNil(pilotedRound.pmRunId, "no PM dispatch ever happened for the piloted round")
        XCTAssertEqual(pilotedRound.outcome, .continued)

        let spawnedRound = state.rounds[1]
        XCTAssertNotNil(spawnedRound.pmRunId, "the adopted round dispatched a real PM turn")
        XCTAssertNil(spawnedRound.externalSubmission, "a spawned round carries no external submission")
        XCTAssertEqual(spawnedRound.outcome, .done)

        XCTAssertEqual(adoptedRunner.callCount(for: "pm_cli"), 1)
        XCTAssertEqual(adoptedRunner.callCount(for: "dev_cli"), 0, "done never dispatches a dev turn")
        XCTAssertEqual(devRunner.callCount(for: "dev_cli"), 1, "the piloted round's own dev turn, from setup")

        // Durable: reloading from disk agrees.
        let reloaded = stateStore.load(id: "relay_adopt_happy")
        XCTAssertEqual(reloaded?.pmMode, .spawned)
        XCTAssertEqual(reloaded?.status, .done)
    }

    // MARK: - adopt: the first spawned PM prompt carries adoptionNote + round-N context

    func testAdoptionPromptCarriesAdoptionNoteAndLastDevReport() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        _ = await makePilotedOneRoundRelay(
            id: "relay_adopt_context", repo: repo, stateStore: stateStore, runStore: runStore,
            devReport: "Wired the widget. Verified with `swift test`."
        )

        let (adoptedService, adoptedRunner) = makeService(
            pmScripts: [.init(stdout: "Looks good.\n\n" + verdictJSON("done", note: "Shipped."))],
            devScripts: [], runStore: runStore
        )
        let adoptCoordinator = RelayCoordinator(runService: adoptedService, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await adoptCoordinator.adopt(relayId: "relay_adopt_context", pmWorkerId: "model_pm", config: config)
        guard case .success = result else { return XCTFail("expected success") }

        let promptText = adoptedRunner.capturedArgs(for: "pm_cli").first?.joined(separator: " ") ?? ""
        XCTAssertTrue(promptText.contains("ran in Pilot mode"), "adoptionNote must reach the first spawned PM turn")
        XCTAssertTrue(promptText.contains("Wired the widget"), "the existing round-N context threading carries the last dev report over, unchanged")
    }

    func testAdoptFromEscalatedCarriesThePriorQuestionIntoTheAdoptionNote() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_adopt_escalated" })
        _ = coordinator.startPilot(config: .init(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "model_dev"))
        let submission = "Need to know which env.\n\n" + verdictJSON("escalate", note: "staging or prod?")
        _ = await coordinator.runExternalRound(relayId: "relay_adopt_escalated", submission: submission)
        XCTAssertEqual(stateStore.load(id: "relay_adopt_escalated")?.status, .escalated)

        let (adoptedService, adoptedRunner) = makeService(
            pmScripts: [.init(stdout: "Going with staging.\n\n" + verdictJSON("done", note: "Resolved and shipped to staging."))],
            devScripts: [], runStore: runStore
        )
        let adoptCoordinator = RelayCoordinator(runService: adoptedService, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await adoptCoordinator.adopt(relayId: "relay_adopt_escalated", pmWorkerId: "model_pm", config: config)
        guard case .success(let state) = result else { return XCTFail("expected success") }
        XCTAssertEqual(state.status, .done)

        let promptText = adoptedRunner.capturedArgs(for: "pm_cli").first?.joined(separator: " ") ?? ""
        XCTAssertTrue(promptText.contains("staging or prod?"), "the open escalation question must reach the adopting PM's first prompt")
    }

    // MARK: - adopt: honest total-round ceiling (piloted rounds count)

    func testAdoptCeilingCountsPilotedRoundsAsPartOfTheTotal() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        _ = await makePilotedOneRoundRelay(id: "relay_adopt_ceiling", repo: repo, stateStore: stateStore, runStore: runStore)

        let (adoptedService, adoptedRunner) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let adoptCoordinator = RelayCoordinator(runService: adoptedService, stateStore: stateStore, runStore: runStore)
        // maxRounds: 1 — but there is ALREADY one piloted round on the log, so the
        // very next round (round 2) already exceeds it. An honest ceiling never grants
        // a fresh budget just because the PM seat changed.
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored", maxRounds: 1)
        let result = await adoptCoordinator.adopt(relayId: "relay_adopt_ceiling", pmWorkerId: "model_pm", config: config)
        guard case .success(let state) = result else { return XCTFail("expected success") }

        XCTAssertEqual(state.status, .stopped)
        XCTAssertEqual(state.stoppedReason, "reached --max-rounds (1)")
        XCTAssertEqual(state.rounds.count, 1, "no second round is even appended once the ceiling fires")
        XCTAssertEqual(adoptedRunner.callCount(for: "pm_cli"), 0, "the ceiling fires before any PM dispatch")
    }

    // MARK: - adopt: refusal matrix

    func testAdoptRefusesRelayNotFound() async throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: "/repo", docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await coordinator.adopt(relayId: "relay_ghost", pmWorkerId: "model_pm", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .relayNotFound)
    }

    func testAdoptRefusesASpawnedRelay() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let spawned = RelayState(
            id: "relay_adopt_already_spawned", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .escalated, createdAt: Date(), note: "x?"
        )
        try stateStore.save(spawned)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await coordinator.adopt(relayId: "relay_adopt_already_spawned", pmWorkerId: "model_pm2", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notPilotRelay)
    }

    func testAdoptRefusesARoundInFlight() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let running = RelayState(
            id: "relay_adopt_inflight", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .running, pmMode: .external, createdAt: Date()
        )
        try stateStore.save(running)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await coordinator.adopt(relayId: "relay_adopt_inflight", pmWorkerId: "model_pm", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAdoptable(status: "running"))
    }

    func testAdoptRefusesADoneRelay() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let done = RelayState(
            id: "relay_adopt_done", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .done, pmMode: .external, createdAt: Date(), note: "Shipped."
        )
        try stateStore.save(done)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await coordinator.adopt(relayId: "relay_adopt_done", pmWorkerId: "model_pm", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAdoptable(status: "done"))
    }

    func testAdoptRefusesACeilingStoppedRelay() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let stopped = RelayState(
            id: "relay_adopt_stopped", projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .stopped, pmMode: .external, createdAt: Date(), stoppedReason: "reached --max-rounds (3)"
        )
        try stateStore.save(stopped)
        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored")
        let result = await coordinator.adopt(relayId: "relay_adopt_stopped", pmWorkerId: "model_pm", config: config)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAdoptable(status: "stopped"))
    }

    // MARK: - Reverse flip: adoptToPilot (spawned → pilot, no dispatch)

    func testAdoptToPilotFlipsAnEscalatedSpawnedRelay() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let pmScripts: [MockCommandRunner.Script] = [.init(stdout: "Need a decision.\n\n" + verdictJSON("escalate", note: "which env?"))]
        let (service, _) = makeService(pmScripts: pmScripts, devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore, idFactory: { "relay_reverse_escalated" })
        let config = RelayCoordinator.Config(projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "model_pm", devWorkerId: "model_dev")
        let state = try await coordinator.run(config: config).get()
        XCTAssertEqual(state.status, .escalated)

        let result = RelayCoordinator.adoptToPilot(relayId: "relay_reverse_escalated", stateStore: stateStore, threadProjector: nil)
        guard case .success(let flipped) = result else { return XCTFail("expected success") }
        XCTAssertEqual(flipped.pmMode, .external)
        XCTAssertEqual(flipped.status, .awaitingPM)
        XCTAssertEqual(flipped.pmWorkerId, RelayState.externalPMWorkerId)
        XCTAssertNil(flipped.finishedAt)
        XCTAssertEqual(flipped.rounds.count, 1, "round log carries over untouched")

        XCTAssertEqual(stateStore.load(id: "relay_reverse_escalated")?.status, .awaitingPM)
    }

    func testAdoptToPilotFlipsAReconciledStoppedSpawnedRelay() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        var orphaned = RelayState(
            id: "relay_reverse_orphan", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        orphaned.rounds.append(RelayRound(roundNumber: 1, baselineHead: "abc", startedAt: Date()))
        try stateStore.save(orphaned)
        // Simulate a dead owner — same convention `RelayCoordinatorTests.
        // makeOrphanedRunningRelay` uses (a PID that can never be this process's own).
        let ownerURL = stateStore.rootDirectory.appendingPathComponent("relay_reverse_orphan", isDirectory: true).appendingPathComponent("owner.pid")
        try Data("2000000".utf8).write(to: ownerURL)

        let result = RelayCoordinator.adoptToPilot(relayId: "relay_reverse_orphan", stateStore: stateStore, threadProjector: nil)
        guard case .success(let flipped) = result else { return XCTFail("expected success — a reconciled-stopped relay is adoptable") }
        XCTAssertEqual(flipped.pmMode, .external)
        XCTAssertEqual(flipped.status, .awaitingPM)
        XCTAssertNil(flipped.stoppedReason, "the ceiling-stop reason is cleared once handed back to Pilot")
    }

    func testAdoptToPilotRefusesAGenuinelyRunningRelay() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        // `stateStore.save` writes owner.pid with THIS (alive) test process's own pid
        // for a `.running` state — a genuinely in-flight relay, not an orphan.
        let running = RelayState(
            id: "relay_reverse_running", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .running, createdAt: Date()
        )
        try stateStore.save(running)

        let result = RelayCoordinator.adoptToPilot(relayId: "relay_reverse_running", stateStore: stateStore, threadProjector: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAdoptable(status: "running"))
    }

    func testAdoptToPilotRefusesADoneRelay() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let done = RelayState(
            id: "relay_reverse_done", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .done, createdAt: Date(), note: "Shipped."
        )
        try stateStore.save(done)
        let result = RelayCoordinator.adoptToPilot(relayId: "relay_reverse_done", stateStore: stateStore, threadProjector: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAdoptable(status: "done"))
    }

    func testAdoptToPilotRefusesACeilingStoppedUnreconciledRelay() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        // A deliberate ceiling stop (not a reconciled orphan) is never resumable —
        // and therefore never adoptable back to Pilot either.
        let stopped = RelayState(
            id: "relay_reverse_ceiling", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: "model_pm", devWorkerId: "model_dev", status: .stopped, createdAt: Date(),
            stoppedReason: "reached --max-rounds (5)"
        )
        try stateStore.save(stopped)
        let result = RelayCoordinator.adoptToPilot(relayId: "relay_reverse_ceiling", stateStore: stateStore, threadProjector: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notAdoptable(status: "stopped"))
    }

    func testAdoptToPilotRefusesAnAlreadyPilotRelay() throws {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let parked = RelayState(
            id: "relay_reverse_already_pilot", projectRoot: "/repo", docPath: "docs/spec.md",
            pmWorkerId: RelayState.externalPMWorkerId, devWorkerId: "model_dev",
            status: .awaitingPM, pmMode: .external, createdAt: Date()
        )
        try stateStore.save(parked)
        let result = RelayCoordinator.adoptToPilot(relayId: "relay_reverse_already_pilot", stateStore: stateStore, threadProjector: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notSpawnedRelay)
    }

    func testAdoptToPilotRefusesRelayNotFound() {
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        let result = RelayCoordinator.adoptToPilot(relayId: "relay_ghost", stateStore: stateStore, threadProjector: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .relayNotFound)
    }

    // MARK: - RSC-S01: cross-process dispatch lock

    /// Two concurrent `adopt` calls on the same relay id: the one that cannot take the
    /// dispatch lock is refused with `.roundInFlight` rather than racing the other into
    /// a double dispatch — same guard `resume` gets (`RelayCoordinatorTests.
    /// testConcurrentResumeCallsYieldExactlyOneDispatchTheOtherRoundInFlight`),
    /// simulated the same way: hold the lock directly with the SAME primitive `adopt`
    /// contends on, then release it and confirm a later legitimate adopt succeeds.
    func testConcurrentAdoptCallsYieldExactlyOneDispatchTheOtherRoundInFlight() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        _ = await makePilotedOneRoundRelay(id: "relay_adopt_concurrent", repo: repo, stateStore: stateStore, runStore: runStore)
        XCTAssertEqual(stateStore.load(id: "relay_adopt_concurrent")?.status, .awaitingPM)

        var heldLock = RelayDispatchLock.tryAcquire(relayId: "relay_adopt_concurrent", relaysRoot: stateStore.rootDirectory)
        XCTAssertNotNil(heldLock, "precondition: lock must be free before the simulated race")

        let (racedService, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let racedCoordinator = RelayCoordinator(runService: racedService, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored", maxRounds: 5
        )
        let racedResult = await racedCoordinator.adopt(relayId: "relay_adopt_concurrent", pmWorkerId: "model_pm", config: config)
        guard case .failure(let error) = racedResult else { return XCTFail("expected failure while the lock is held") }
        XCTAssertEqual(error, .roundInFlight)
        // The lock loser must never have mutated durable state.
        XCTAssertEqual(stateStore.load(id: "relay_adopt_concurrent")?.pmMode, .external)
        XCTAssertEqual(stateStore.load(id: "relay_adopt_concurrent")?.status, .awaitingPM)

        heldLock = nil

        let (adoptedService, adoptedRunner) = makeService(
            pmScripts: [.init(stdout: "Reviewed.\n\n" + verdictJSON("done", note: "All criteria met."))],
            devScripts: [], runStore: runStore
        )
        let adoptCoordinator = RelayCoordinator(runService: adoptedService, stateStore: stateStore, runStore: runStore)
        let secondResult = await adoptCoordinator.adopt(relayId: "relay_adopt_concurrent", pmWorkerId: "model_pm", config: config)
        guard case .success(let state) = secondResult else { return XCTFail("expected success once the lock is released") }
        XCTAssertEqual(state.status, .done)
        XCTAssertEqual(adoptedRunner.callCount(for: "pm_cli"), 1)
    }

    // MARK: - RSC-HF: guard flips durable state

    /// `adoptGuard` must flip + persist EXACTLY what `adopt` itself would before the
    /// round loop runs, and return the one-time `adoptionNote` (never persisted).
    func testAdoptGuardFlipsStateAndReturnsAdoptionNote() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        _ = await makePilotedOneRoundRelay(id: "relay_guard_adopt", repo: repo, stateStore: stateStore, runStore: runStore)
        XCTAssertEqual(stateStore.load(id: "relay_guard_adopt")?.status, .awaitingPM)

        let (adoptedService, _) = makeService(
            pmScripts: [.init(stdout: "Reviewed the adopted round.\n\n" + verdictJSON("done", note: "All criteria met."))],
            devScripts: [], runStore: runStore
        )
        let coordinator = RelayCoordinator(runService: adoptedService, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md",
            pmWorkerId: "ignored-overridden", devWorkerId: "ignored-overridden", maxRounds: 5
        )

        let guardResult = coordinator.adoptGuard(relayId: "relay_guard_adopt", pmWorkerId: "model_pm", config: config)
        guard case .success(let (flipped, adoptedConfig, note)) = guardResult else { return XCTFail("expected guard success") }
        XCTAssertEqual(flipped.pmMode, .spawned)
        XCTAssertEqual(flipped.pmWorkerId, "model_pm")
        XCTAssertEqual(flipped.status, .running, "the guard's own mutation, before any child exists")
        XCTAssertTrue(note.contains("Pilot"), "adoptionNote names the piloted-round handoff")
        XCTAssertEqual(adoptedConfig.pmWorkerId, "model_pm")
        XCTAssertEqual(stateStore.load(id: "relay_guard_adopt")?.status, .running, "durable, not just in-memory")
    }

    /// The `--no-wait` foreground guard must refuse identically to `adopt` when
    /// another process already holds the dispatch lock — same `.roundInFlight`
    /// failure channel, and durable state stays untouched.
    func testAdoptGuardRefusesRoundInFlightAndLeavesStateUntouched() async throws {
        let repo = try makeGitRepo()
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let stateStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))
        _ = await makePilotedOneRoundRelay(id: "relay_guard_adopt_locked", repo: repo, stateStore: stateStore, runStore: runStore)

        var heldLock = RelayDispatchLock.tryAcquire(relayId: "relay_guard_adopt_locked", relaysRoot: stateStore.rootDirectory)
        XCTAssertNotNil(heldLock, "precondition: lock must be free before the simulated race")

        let (service, _) = makeService(pmScripts: [], devScripts: [], runStore: runStore)
        let coordinator = RelayCoordinator(runService: service, stateStore: stateStore, runStore: runStore)
        let config = RelayCoordinator.Config(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devWorkerId: "ignored", maxRounds: 5
        )
        let guardResult = coordinator.adoptGuard(relayId: "relay_guard_adopt_locked", pmWorkerId: "model_pm", config: config)
        guard case .failure(let error) = guardResult else { return XCTFail("expected guard failure while the lock is held") }
        XCTAssertEqual(error, .roundInFlight)
        XCTAssertEqual(stateStore.load(id: "relay_guard_adopt_locked")?.pmMode, .external, "a refused guard must never mutate durable state")
        XCTAssertEqual(stateStore.load(id: "relay_guard_adopt_locked")?.status, .awaitingPM)
        heldLock = nil
    }
}
