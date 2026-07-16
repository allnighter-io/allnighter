import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PN-S05 works test: `PanelThreadProjector` wired into `PanelCoordinator` via the
/// optional-collaborator seam — one `WorkThread` per panel, brief = user turn, each
/// seat report = worker turn, awaitingPM parked-calm, done settles
/// (`docs/phases/Pilot_Panel.md` decision 12). Mirrors `RelayThreadProjectionTests`.
final class PanelThreadProjectionTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-panel-thread-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures

    private func makeTarget(contents: String = "spec v1") throws -> (root: URL, path: String) {
        let root = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rel = "docs/phases/Pilot_Panel.md"
        let full = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: full.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: full, atomically: true, encoding: .utf8)
        return (root, rel)
    }

    private func seats() -> [PanelSeat] {
        [
            PanelSeat(workerId: "model_a", lens: "adversary"),
            PanelSeat(workerId: "model_b", lens: "simplicity"),
        ]
    }

    /// RO-capable models so `PanelCoordinator.start` isolation check passes.
    private func roModels() -> [Model] {
        [
            Model(id: "model_a", displayName: "A", modelLabel: "a", driverId: "claude_code"),
            Model(id: "model_b", displayName: "B", modelLabel: "b", driverId: "claude_code"),
        ]
    }

    private func roRegistry() -> DriverRegistry {
        DriverRegistry([
            DriverManifest(
                id: "claude_code", displayName: "Claude Code", kind: .headlessCLI,
                invoke: .init(command: "claude", args: ["-p", "{{prompt}}", "--model", "{{model}}"])
            ),
        ])
    }

    private func fakeDispatch(
        reports: [String: String] = [:],
        statuses: [String: SeatResult.Status] = [:],
        runIds: [String: String] = [:],
        reasons: [String: String] = [:]
    ) -> PanelCoordinator.SeatDispatch {
        { seats, brief, targetPath, projectRoot, _panelId in
            seats.map { seat in
                let report = reports[seat.workerId] ?? """
                Seat \(seat.workerId) report on \(targetPath)

                ```json
                {"findings":[{"claim":"c-\(seat.workerId)","severity":"low","evidence":"e"}],"noMaterialFindings":false}
                ```
                """
                let status = statuses[seat.workerId] ?? .done
                if status != .done {
                    return SeatResult(
                        workerId: seat.workerId, lens: seat.lens, status: status,
                        reason: reasons[seat.workerId] ?? "induced \(status.rawValue)",
                        report: report, runId: runIds[seat.workerId]
                    )
                }
                var result = PanelFindingsParser.seatResult(
                    workerId: seat.workerId, lens: seat.lens, report: report
                )
                result.runId = runIds[seat.workerId] ?? "run_\(seat.workerId)"
                return result
            }
        }
    }

    private struct Rig {
        let coordinator: PanelCoordinator
        let threadStore: ThreadStore
        let stateStore: PanelStateStore
        let models: [Model]
        let registry: DriverRegistry
    }

    private func makeRig(
        dispatch: PanelCoordinator.SeatDispatch? = nil,
        id: String = "panel_thread_test",
        withProjector: Bool = true
    ) -> Rig {
        let stateStore = PanelStateStore(rootDirectory: tmp.appendingPathComponent("panels"))
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads"))
        let projector: PanelThreadProjector? = withProjector
            ? PanelThreadProjector(store: threadStore)
            : nil
        let coordinator = PanelCoordinator(
            stateStore: stateStore,
            seatDispatch: dispatch ?? fakeDispatch(),
            threadProjector: projector,
            idFactory: { id }
        )
        return Rig(
            coordinator: coordinator,
            threadStore: threadStore,
            stateStore: stateStore,
            models: roModels(),
            registry: roRegistry()
        )
    }

    private func startPanel(
        rig: Rig,
        root: URL,
        path: String,
        projectId: String = "proj_panel_1",
        maxRounds: Int = 10
    ) throws -> PanelState {
        let result = rig.coordinator.start(
            config: .init(
                projectRoot: root.path,
                projectId: projectId,
                targetPath: path,
                teamId: "t",
                seats: seats(),
                maxRounds: maxRounds
            ),
            models: rig.models,
            registry: rig.registry
        )
        guard case .success(let state) = result else {
            XCTFail("start failed: \(result)")
            throw NSError(domain: "PanelThreadProjectionTests", code: 1)
        }
        return state
    }

    // MARK: - start creates a bound thread

    func testPanelStartCreatesThreadBoundToProject() throws {
        let (root, path) = try makeTarget()
        let rig = makeRig()
        let state = try startPanel(rig: rig, root: root, path: path, projectId: "proj_panel_1")

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        XCTAssertEqual(thread.id, state.id, "thread id must equal the panel id")
        XCTAssertEqual(thread.projectId, "proj_panel_1")
        XCTAssertEqual(thread.title, "Panel: Pilot Panel")
        XCTAssertEqual(thread.workingDir, root.path)
        XCTAssertTrue(thread.turns.isEmpty, "nothing to show before the first round")
        XCTAssertFalse(thread.isRunning)
        XCTAssertFalse(thread.needsAttention, "awaitingPM is parked-calm")
    }

    // MARK: - Settled round appends brief + N seat turns verbatim

    func testSettledRoundAppendsBriefAndSeatTurnsVerbatimWithRunIds() async throws {
        let (root, path) = try makeTarget()
        let reportA = "Adversary findings for panel.\n\n```json\n{\"findings\":[{\"claim\":\"gap\",\"severity\":\"high\",\"evidence\":\"L10\"}],\"noMaterialFindings\":false}\n```"
        let reportB = "Simplicity says: no material findings.\n\n```json\n{\"findings\":[],\"noMaterialFindings\":true,\"reason\":\"clean\"}\n```"
        let rig = makeRig(dispatch: fakeDispatch(
            reports: ["model_a": reportA, "model_b": reportB],
            runIds: ["model_a": "run_a_1", "model_b": "run_b_1"]
        ))
        let state = try startPanel(rig: rig, root: root, path: path)

        let result = await rig.coordinator.runRound(panelId: state.id)
        guard case .success(let payload) = result else {
            return XCTFail("round failed: \(result)")
        }
        XCTAssertEqual(payload.state.status, .awaitingPM)

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        let brief = try XCTUnwrap(thread.turn(id: "\(state.id)_r1_brief"))
        XCTAssertEqual(brief.status, .done)
        XCTAssertEqual(brief.author, .user)
        XCTAssertEqual(brief.kind, .userMessage)
        XCTAssertEqual(brief.text, PanelSeatPrompt.builtinBrief, "brief is verbatim, not summarized")

        let seatA = try XCTUnwrap(thread.turn(id: "\(state.id)_r1_seat_model_a"))
        XCTAssertEqual(seatA.status, .done)
        XCTAssertEqual(seatA.author, .worker)
        XCTAssertEqual(seatA.workerId, "model_a")
        XCTAssertEqual(seatA.kind, .workerChat)
        XCTAssertEqual(seatA.runId, "run_a_1")
        XCTAssertEqual(seatA.text, reportA, "seat report is verbatim")

        let seatB = try XCTUnwrap(thread.turn(id: "\(state.id)_r1_seat_model_b"))
        XCTAssertEqual(seatB.status, .done)
        XCTAssertEqual(seatB.workerId, "model_b")
        XCTAssertEqual(seatB.runId, "run_b_1")
        XCTAssertEqual(seatB.text, reportB)

        XCTAssertFalse(thread.isRunning, "awaitingPM: no running turns")
        XCTAssertFalse(thread.needsAttention, "successful round is parked-calm")
        XCTAssertEqual(thread.turns.count, 3, "brief + 2 seats")
    }

    // MARK: - Partial round settles honestly

    func testPartialRoundSettlesHonestlyPerSeatStatus() async throws {
        let (root, path) = try makeTarget()
        let rig = makeRig(dispatch: fakeDispatch(
            statuses: ["model_a": .done, "model_b": .failed],
            runIds: ["model_a": "run_ok"],
            reasons: ["model_b": "timeout-ish fail"]
        ))
        let state = try startPanel(rig: rig, root: root, path: path)

        let result = await rig.coordinator.runRound(panelId: state.id)
        guard case .success = result else { return XCTFail("expected settle: \(result)") }

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        let seatA = try XCTUnwrap(thread.turn(id: "\(state.id)_r1_seat_model_a"))
        XCTAssertEqual(seatA.status, .done)
        let seatB = try XCTUnwrap(thread.turn(id: "\(state.id)_r1_seat_model_b"))
        XCTAssertEqual(seatB.status, .failed, "failed seats project honestly")
        XCTAssertTrue(seatB.text?.contains("induced") == true || seatB.text?.isEmpty == false)
        XCTAssertFalse(thread.isRunning, "round still parks — no running turns")
        XCTAssertTrue(thread.needsAttention, "a failed seat surfaces attention via turn status")
    }

    // MARK: - Rerun REPLACE (not append) seat turns

    /// Decision: REPLACE. `--seats` is a new attempt on the same round that replaces
    /// those seats in merged `seatResults`. Turn ids are keyed by round + workerId
    /// only (not attempt), so sync rewrites the same seat turn. Attempt history stays
    /// run-truth on `PanelRound.attempts` — the thread shows the current jury answer.
    func testRerunReplacesRerunSeatTurnsNotAppend() async throws {
        let (root, path) = try makeTarget()
        final class AttemptCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next() -> Int {
                lock.lock(); defer { lock.unlock() }
                value += 1
                return value
            }
        }
        let counter = AttemptCounter()
        let dispatch: PanelCoordinator.SeatDispatch = { seats, _, _, _, _ in
            let attempt = counter.next()
            return seats.map { seat in
                var result = PanelFindingsParser.seatResult(
                    workerId: seat.workerId,
                    lens: seat.lens,
                    report: "attempt-\(attempt)-\(seat.workerId)-report"
                )
                result.runId = "run_attempt\(attempt)_\(seat.workerId)"
                return result
            }
        }
        let rig = makeRig(dispatch: dispatch)
        let state = try startPanel(rig: rig, root: root, path: path)

        let first = await rig.coordinator.runRound(panelId: state.id)
        guard case .success(let r1) = first else { return XCTFail("\(first)") }
        let originalB = try XCTUnwrap(
            try XCTUnwrap(rig.threadStore.get(state.id)).turn(id: "\(state.id)_r1_seat_model_b")
        )

        let rerun = await rig.coordinator.runRound(panelId: state.id, seatFilter: ["model_a"])
        guard case .success(let r2) = rerun else { return XCTFail("\(rerun)") }
        XCTAssertEqual(r2.state.rounds.count, 1)
        XCTAssertEqual(r2.round.attempts.count, 2)

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        // Still one turn per seat for round 1 — no appended second A turn.
        let seatATurns = thread.turns.filter { $0.id == "\(state.id)_r1_seat_model_a" }
        XCTAssertEqual(seatATurns.count, 1, "REPLACE keeps a single turn id per seat per round")
        let seatA = try XCTUnwrap(seatATurns.first)
        XCTAssertEqual(seatA.text, "attempt-2-model_a-report", "rerun rewrote seat A")
        XCTAssertEqual(seatA.runId, "run_attempt2_model_a")

        let seatB = try XCTUnwrap(thread.turn(id: "\(state.id)_r1_seat_model_b"))
        XCTAssertEqual(seatB.text, originalB.text, "untouched seat B not rewritten by A-only rerun")
        XCTAssertEqual(seatB.runId, originalB.runId)

        // Brief still one turn for the round.
        XCTAssertEqual(thread.turns.filter { $0.id.hasSuffix("_r1_brief") }.count, 1)
        XCTAssertEqual(r1.round.seatResults.count, 2)
    }

    // MARK: - Done settles the thread

    func testDoneSettlesThreadCleanly() async throws {
        let (root, path) = try makeTarget()
        let rig = makeRig()
        let state = try startPanel(rig: rig, root: root, path: path)
        _ = await rig.coordinator.runRound(panelId: state.id)

        let done = rig.coordinator.done(panelId: state.id, note: "survivors noted")
        guard case .success = done else { return XCTFail("done failed: \(done)") }

        let thread = try XCTUnwrap(rig.threadStore.get(state.id))
        XCTAssertFalse(thread.isRunning)
        // Successful seats → no failed turns; done adds no open system event.
        XCTAssertFalse(thread.needsAttention)
        XCTAssertTrue(thread.turns.allSatisfy { $0.status.isTerminal })
    }

    // MARK: - In-flight shows running seat turns (projector unit)

    func testInFlightRoundProjectsRunningSeatTurns() throws {
        let (root, path) = try makeTarget()
        let threadStore = ThreadStore(rootDirectory: tmp.appendingPathComponent("threads-inflight"))
        let projector = PanelThreadProjector(store: threadStore)
        let panelId = "panel_inflight_1"
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let state = PanelState(
            id: panelId,
            projectRoot: root.path,
            projectId: "proj",
            targetPath: path,
            seats: seats(),
            status: .running,
            rounds: [
                PanelRound(
                    roundNumber: 1,
                    targetHash: "abc",
                    brief: PanelSeatPrompt.builtinBrief,
                    briefSource: .builtin,
                    seatResults: [
                        SeatResult(workerId: "model_a", lens: "adversary", status: .empty, report: ""),
                        SeatResult(workerId: "model_b", lens: "simplicity", status: .empty, report: ""),
                    ],
                    attempts: [],
                    startedAt: startedAt,
                    finishedAt: nil
                ),
            ],
            createdAt: startedAt
        )
        projector.started(state: state, projectId: "proj")
        projector.sync(state: state, now: startedAt)

        let thread = try XCTUnwrap(threadStore.get(panelId))
        let brief = try XCTUnwrap(thread.turn(id: "\(panelId)_r1_brief"))
        XCTAssertEqual(brief.status, .done)
        XCTAssertEqual(brief.author, .user)
        XCTAssertEqual(brief.text, PanelSeatPrompt.builtinBrief)

        let seatA = try XCTUnwrap(thread.turn(id: "\(panelId)_r1_seat_model_a"))
        XCTAssertEqual(seatA.status, .running)
        XCTAssertEqual(seatA.author, .worker)
        XCTAssertEqual(seatA.workerId, "model_a")
        XCTAssertNil(seatA.text)
        let seatB = try XCTUnwrap(thread.turn(id: "\(panelId)_r1_seat_model_b"))
        XCTAssertEqual(seatB.status, .running)
        XCTAssertTrue(thread.isRunning, "live inbox theater while seats stream")
        XCTAssertFalse(thread.needsAttention, "running seats are not attention blockers")
    }

    // MARK: - No projector: coordinator unaffected

    func testPanelRunsUnchangedWithNoThreadProjectorAttached() async throws {
        let (root, path) = try makeTarget()
        let rig = makeRig(withProjector: false)
        let state = try startPanel(rig: rig, root: root, path: path)
        XCTAssertNil(rig.threadStore.get(state.id), "no projector → no thread")

        let result = await rig.coordinator.runRound(panelId: state.id)
        guard case .success(let payload) = result else {
            return XCTFail("round must not depend on a thread store: \(result)")
        }
        XCTAssertEqual(payload.state.status, .awaitingPM)
        XCTAssertEqual(payload.round.seatResults.count, 2)

        let done = rig.coordinator.done(panelId: state.id, note: "ok")
        guard case .success(let finished) = done else {
            return XCTFail("done must not depend on a thread store: \(done)")
        }
        XCTAssertEqual(finished.status, .done)
        XCTAssertNil(rig.threadStore.get(state.id))
    }

    // MARK: - Title derivation

    func testTitleFromTargetPath() {
        XCTAssertEqual(
            PanelThreadProjector.title(forTargetPath: "docs/phases/Pilot_Panel.md"),
            "Panel: Pilot Panel"
        )
        XCTAssertEqual(
            PanelThreadProjector.title(forTargetPath: "docs/phases/foo-bar.md"),
            "Panel: foo bar"
        )
        XCTAssertEqual(PanelThreadProjector.title(forTargetPath: ""), "Panel")
    }
}
