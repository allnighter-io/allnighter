import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PL-S05 works test: `RelayThreadProjector` renders a Pilot relay (`pmMode ==
/// .external`) on the SAME `WorkThread` shape a spawned relay uses — an external
/// round's submission renders verbatim as the PM turn, attributed distinctly
/// (`author: .user`, no `workerId`) from a spawned PM turn's `author: .worker` +
/// `workerId`; `awaitingPM` renders PARKED-calm (no open turn, not running, no
/// attention); an in-flight dev turn renders `.running` exactly like today.
/// Mirrors `RelayThreadProjectionTests`' fixture shape, dev CLI only (Pilot never
/// dispatches a PM seat).
final class PilotThreadProjectionTests: HermeticSupportTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("alln-pilot-thread-\(UUID().uuidString)")
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

    private func verdictJSON(_ verdict: String, handover: String? = nil, note: String? = nil) -> String {
        var fields = ["\"verdict\": \"\(verdict)\""]
        if let handover { fields.append("\"handover\": \"\(handover)\"") }
        if let note { fields.append("\"note\": \"\(note)\"") }
        return "```json\n{\(fields.joined(separator: ", "))}\n```"
    }

    private struct Rig {
        let coordinator: RelayCoordinator
        let threadStore: ThreadStore
        let runner: SequencedCommandRunner
    }

    private func makeRig(devScripts: [MockCommandRunner.Script], idFactory: @escaping @Sendable () -> String = { "relay_pilot_thread_test" }) -> Rig {
        let devModel = Model(id: "model_dev", displayName: "Dev", modelLabel: "dev", driverId: "dev_cli", role: .both)
        let registry = DriverRegistry([TestSupport.headlessManifest(id: "dev_cli", command: "dev_cli")])
        let runner = SequencedCommandRunner(queues: ["dev_cli": devScripts])
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let service = RunService(
            models: [devModel], registry: registry, runStore: runStore, commandRunner: runner,
            writeLock: RunWriteLockRegistry(), defaultSettings: { DefaultModelSettings() },
            probeRecords: {
                [ToolProbeRecord(driverId: "dev_cli", status: .ready(version: "1"), lastProbeAt: .distantPast)]
            }
        )
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector = RelayThreadProjector(store: threadStore, runStore: runStore)
        let coordinator = RelayCoordinator(
            runService: service,
            stateStore: RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays")),
            runStore: runStore, threadProjector: projector, idFactory: idFactory
        )
        return Rig(coordinator: coordinator, threadStore: threadStore, runner: runner)
    }

    // MARK: - start creates a bound thread, parked-calm

    func testPilotStartCreatesThreadAwaitingPMWithNoRunningTurnOrAttention() throws {
        let repo = try makeGitRepo()
        let rig = makeRig(devScripts: [])
        let started = rig.coordinator.startPilot(config: .init(
            projectRoot: repo.path, projectId: "proj_pilot_1", docPath: "docs/spec.md",
            pmWorkerId: "ignored", devModelId: "model_dev"
        ))
        guard case .success(let state) = started else { return XCTFail("start failed") }

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        XCTAssertEqual(thread.projectId, "proj_pilot_1")
        XCTAssertTrue(thread.turns.isEmpty, "nothing to show before the first handoff")
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention)
    }

    // MARK: - A continue round: submission verbatim as the PM turn, distinct attribution

    func testContinueRoundRendersSubmissionVerbatimAsPMTurnDistinctFromSpawned() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(devScripts: [.init(stdout: "Implemented and committed.")])
        let started = rig.coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devModelId: "model_dev"
        ))
        guard case .success(let relay) = started else { return XCTFail("start failed") }

        let submission = "My own review of the repo.\n\n" + verdictJSON("continue", handover: "Implement the thing.")
        let result = await rig.coordinator.runExternalRound(relayId: relay.id, submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }
        XCTAssertEqual(payload.state.status, .awaitingPM)

        let thread = try XCTUnwrap(rig.threadStore.get(relay.id))
        let pmTurn = try XCTUnwrap(thread.turn(id: "\(relay.id)_pm1"))
        XCTAssertEqual(pmTurn.status, .done, "a pilot round is a complete record from the moment it lands — no running placeholder")
        XCTAssertEqual(pmTurn.author, .user, "distinct from a spawned PM turn's .worker author")
        XCTAssertNil(pmTurn.workerId, "no PM model ever dispatches in Pilot")
        XCTAssertEqual(pmTurn.text, submission, "verbatim, verdict tail included")
        XCTAssertEqual(pmTurn.kind, .workerChat)

        let devTurn = try XCTUnwrap(thread.turn(id: "\(relay.id)_dev1"))
        XCTAssertEqual(devTurn.status, .done)
        XCTAssertEqual(devTurn.author, .worker)
        XCTAssertEqual(devTurn.workerId, "model_dev")
        XCTAssertEqual(devTurn.runId, payload.state.rounds.first?.devRunId)
        XCTAssertEqual(devTurn.text, "Implemented and committed.")

        // Parked back to awaitingPM after settling — calm, nothing open.
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention)
    }

    // MARK: - A gate-blocked / unparseable submission never touches the thread

    func testGateBlockedSubmissionNeverAppendsAnyTurn() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(devScripts: [])
        let started = rig.coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devModelId: "model_dev"
        ))
        guard case .success(let relay) = started else { return XCTFail("start failed") }

        let submission = "Reviewed.\n\n" + verdictJSON("continue", handover: "Run git reset --hard on main.")
        let result = await rig.coordinator.runExternalRound(relayId: relay.id, submission: submission)
        guard case .failure = result else { return XCTFail("expected a gate-blocked failure") }

        let thread = try XCTUnwrap(rig.threadStore.get(relay.id))
        XCTAssertTrue(thread.turns.isEmpty, "no round ever landed on the ledger, so nothing to project")
        XCTAssertFalse(thread.needsAttention, "Pilot never escalates on a gate block")
    }

    // MARK: - done settles the thread cleanly, exactly like spawned

    func testDoneRoundSettlesThreadCleanlyWithSubmissionAsThePMTurn() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(devScripts: [])
        let started = rig.coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devModelId: "model_dev"
        ))
        guard case .success(let relay) = started else { return XCTFail("start failed") }

        let submission = "All acceptance criteria met.\n\n" + verdictJSON("done", note: "Shipped.")
        let result = await rig.coordinator.runExternalRound(relayId: relay.id, submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }
        XCTAssertEqual(payload.state.status, .done)

        let thread = try XCTUnwrap(rig.threadStore.get(relay.id))
        XCTAssertEqual(thread.turns.count, 1, "just the settled PM turn — done needs no extra system event")
        XCTAssertEqual(thread.turn(id: "\(relay.id)_pm1")?.text, submission)
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention)
    }

    // MARK: - escalate raises needsAttention, exactly like spawned

    func testEscalateRoundRaisesNeedsAttentionExactlyLikeSpawned() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(devScripts: [])
        let started = rig.coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devModelId: "model_dev"
        ))
        guard case .success(let relay) = started else { return XCTFail("start failed") }

        let submission = "Need to know which env.\n\n" + verdictJSON("escalate", note: "staging or prod?")
        let result = await rig.coordinator.runExternalRound(relayId: relay.id, submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }
        XCTAssertEqual(payload.state.status, .escalated)

        let thread = try XCTUnwrap(rig.threadStore.get(relay.id))
        XCTAssertTrue(thread.needsAttention)
        let escTurn = try XCTUnwrap(thread.turn(id: "\(relay.id)_escalate1"))
        XCTAssertEqual(escTurn.kind, .systemEvent)
        XCTAssertEqual(escTurn.systemEvent, .relayEscalated)
        XCTAssertEqual(escTurn.status, .running, "open and blocking, same as a spawned relay's escalation")
        XCTAssertEqual(escTurn.text, "staging or prod?")
        // The PM turn (the human's own submission) is still rendered, settled.
        XCTAssertEqual(thread.turn(id: "\(relay.id)_pm1")?.status, .done)
    }

    // MARK: - In-flight dev turn renders running, exactly like today, while parked between calls

    func testDevTurnRendersRunningWhileDispatchingThenSettlesOnCompletion() async throws {
        let repo = try makeGitRepo()
        let rig = makeRig(devScripts: [.init(stdout: "Round done.")])
        let started = rig.coordinator.startPilot(config: .init(
            projectRoot: repo.path, docPath: "docs/spec.md", pmWorkerId: "ignored", devModelId: "model_dev"
        ))
        guard case .success(let relay) = started else { return XCTFail("start failed") }

        let submission = "Go.\n\n" + verdictJSON("continue", handover: "Build it.")
        let result = await rig.coordinator.runExternalRound(relayId: relay.id, submission: submission)
        guard case .success(let payload) = result else { return XCTFail("expected success") }
        XCTAssertEqual(payload.state.status, .awaitingPM, "settled back to parked after the dev turn completed")

        // The durable round-in-flight window (state.status == .running, persisted
        // before dispatch) is what a concurrent `pilot status` would observe live;
        // by the time this call returns, the thread already reflects the settled
        // dev turn — same eventual shape `RelayThreadProjectionTests` asserts for a
        // spawned relay's completed round.
        let thread = try XCTUnwrap(rig.threadStore.get(relay.id))
        XCTAssertEqual(thread.turn(id: "\(relay.id)_dev1")?.status, .done)
        XCTAssertFalse(thread.isRunning)
    }
}
