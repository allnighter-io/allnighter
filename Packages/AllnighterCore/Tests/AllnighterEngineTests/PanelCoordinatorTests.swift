import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// PN-S03: `PanelCoordinator.runRound` — blocking settle, partial failure, `--seats`
/// rerun (same-round attempt), maxRounds, done, target-hash pinning
/// (`docs/phases/Pilot_Panel.md`).
/// Thread-safe event sink for Sendable EventSink closures in tests.
private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [PanelCoordinator.PanelEvent] = []
    func append(_ e: PanelCoordinator.PanelEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(e)
    }
    func snapshot() -> [PanelCoordinator.PanelEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

private struct StaggeredFailingPanelRunner: WorkerInvoking {
    func invoke(_ invocation: WorkerInvocation) -> AsyncThrowingStream<WorkerStreamEvent, Error> {
        let modelId = invocation.model.id
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(
                    workerId: modelId,
                    modelId: modelId,
                    sourceId: invocation.manifest.id
                ))
                if modelId == "model_b" {
                    try? await Task.sleep(for: .milliseconds(750))
                }
                continuation.yield(.failed(WorkerRunResult(
                    status: .failed,
                    errorReason: "\(modelId) session directory permission denied"
                )))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

final class PanelCoordinatorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-panel-coord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures

    private func makeTarget(contents: String = "spec v1") throws -> (root: URL, path: String) {
        let root = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rel = "docs/target.md"
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

    private func fakeDispatch(
        reports: [String: String] = [:],
        statuses: [String: SeatResult.Status] = [:]
    ) -> PanelCoordinator.SeatDispatch {
        { seats, brief, targetPath, projectRoot, _panelId in
            seats.map { seat in
                let report = reports[seat.workerId] ?? """
                Seat \(seat.workerId) saw brief=\(brief.prefix(20)) target=\(targetPath)

                ```json
                {"findings":[{"claim":"c-\(seat.workerId)","severity":"low","evidence":"e"}],"noMaterialFindings":false}
                ```
                """
                let status = statuses[seat.workerId] ?? .done
                if status != .done {
                    return SeatResult(
                        workerId: seat.workerId, lens: seat.lens, status: status,
                        reason: "induced \(status.rawValue)", report: report
                    )
                }
                return PanelFindingsParser.seatResult(
                    workerId: seat.workerId, lens: seat.lens, report: report
                )
            }
        }
    }

    private func makeCoordinator(
        dispatch: PanelCoordinator.SeatDispatch? = nil,
        id: String = "panel_test_1"
    ) -> (PanelCoordinator, PanelStateStore) {
        let store = PanelStateStore(rootDirectory: tmp.appendingPathComponent("panels"))
        let coord = PanelCoordinator(
            stateStore: store,
            seatDispatch: dispatch ?? fakeDispatch(),
            idFactory: { id }
        )
        return (coord, store)
    }

    // MARK: - Happy 2-seat round

    func testHappyTwoSeatRoundSettlesWithBuiltinBriefAndFindings() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        // Bypass isolation by writing state directly — start requires RO models.
        // Use a thin start path: save parked panel then runRound.
        let panel = PanelState(
            id: "panel_test_1",
            projectRoot: root.path,
            projectId: "proj_1",
            targetPath: path,
            teamId: "t",
            seats: seats(),
            status: .awaitingPM,
            maxRounds: 10,
            rounds: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(panel)

        let box = EventBox()
        let result = await coord.runRound(panelId: "panel_test_1") { box.append($0) }
        guard case .success(let payload) = result else {
            return XCTFail("expected success, got \(result)")
        }

        XCTAssertEqual(payload.state.status, .awaitingPM, "parks back after settle")
        XCTAssertEqual(payload.state.rounds.count, 1)
        XCTAssertEqual(payload.round.roundNumber, 1)
        XCTAssertEqual(payload.round.briefSource, .builtin)
        XCTAssertEqual(payload.round.brief, PanelSeatPrompt.builtinBrief)
        XCTAssertEqual(payload.round.seatResults.count, 2)
        XCTAssertTrue(payload.round.seatResults.allSatisfy { $0.status == .done })
        XCTAssertEqual(payload.round.seatResults[0].findings?.first?.claim, "c-model_a")
        XCTAssertEqual(payload.round.attempts.count, 1)
        XCTAssertEqual(payload.attempt.attemptNumber, 1)

        // Events: seatStarted x2, seatSettled x2, roundSettled.
        let events = box.snapshot()
        XCTAssertEqual(events.filter {
            if case .seatStarted = $0 { return true }; return false
        }.count, 2)
        XCTAssertEqual(events.filter {
            if case .seatSettled = $0 { return true }; return false
        }.count, 2)
        XCTAssertTrue(events.contains {
            if case .roundSettled(1, 1) = $0 { return true }; return false
        })

        // Durable owner.pid cleared after park.
        let ownerURL = store.rootDirectory
            .appendingPathComponent("panel_test_1", isDirectory: true)
            .appendingPathComponent("owner.pid")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownerURL.path))
    }

    // MARK: - In-flight refusal

    func testInFlightRefusal() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        let panel = PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .running,
            rounds: [], createdAt: Date()
        )
        try store.save(panel)

        let result = await coord.runRound(panelId: "panel_test_1")
        guard case .failure(.roundInFlight) = result else {
            return XCTFail("expected roundInFlight, got \(result)")
        }
    }

    // MARK: - Partial failure settles

    func testPartialFailureSettlesWithPerSeatStatus() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator(dispatch: fakeDispatch(statuses: [
            "model_a": .done,
            "model_b": .failed,
        ]))
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            rounds: [], createdAt: Date()
        ))

        let result = await coord.runRound(panelId: "panel_test_1")
        guard case .success(let payload) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(payload.state.status, .awaitingPM)
        XCTAssertEqual(payload.round.seatResults.count, 2)
        let byId = Dictionary(uniqueKeysWithValues: payload.round.seatResults.map { ($0.workerId, $0) })
        XCTAssertEqual(byId["model_a"]?.status, .done)
        XCTAssertEqual(byId["model_b"]?.status, .failed)
        XCTAssertEqual(byId["model_a"]?.findings?.count, 1, "arrived findings kept")
    }

    func testDefaultDispatchPersistsFastFailureWhileSlowSeatIsStillRunning() async throws {
        let (root, path) = try makeTarget()
        let store = PanelStateStore(rootDirectory: tmp.appendingPathComponent("panels"))
        let models = [
            Model(
                id: "model_a", displayName: "A", modelLabel: "a",
                driverId: "claude_code", role: .both, enabled: true
            ),
            Model(
                id: "model_b", displayName: "B", modelLabel: "b",
                driverId: "codex", role: .both, enabled: true
            ),
        ]
        let registry = DriverRegistry([
            DriverManifest(
                id: "claude_code", displayName: "Claude", kind: .headlessCLI,
                invoke: .init(command: "claude", args: ["--permission-mode", "plan", "-p", "{{prompt}}"])
            ),
            DriverManifest(
                id: "codex", displayName: "Codex", kind: .headlessCLI,
                invoke: .init(command: "codex", args: ["exec", "-m", "{{model}}", "{{prompt}}"])
            ),
        ])
        let coord = PanelCoordinator(
            stateStore: store,
            workerRunner: StaggeredFailingPanelRunner(),
            models: models,
            registry: registry
        )
        try store.save(PanelState(
            id: "panel_incremental", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            rounds: [], createdAt: Date()
        ))

        let roundTask = Task {
            await coord.runRound(panelId: "panel_incremental")
        }

        var observed: [String: SeatResult] = [:]
        for _ in 0..<100 {
            if let round = store.load(id: "panel_incremental")?.rounds.last {
                observed = Dictionary(
                    uniqueKeysWithValues: round.seatResults.map { ($0.workerId, $0) }
                )
                if observed["model_a"]?.status == .failed,
                   observed["model_b"]?.status == .running {
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(observed["model_a"]?.status, .failed)
        XCTAssertEqual(
            observed["model_a"]?.reason,
            "model_a session directory permission denied"
        )
        XCTAssertEqual(observed["model_b"]?.status, .running)

        let settled = await roundTask.value
        guard case .success(let payload) = settled else {
            return XCTFail("expected settled partial round, got \(settled)")
        }
        XCTAssertEqual(payload.state.status, .awaitingPM)
        XCTAssertTrue(payload.round.seatResults.allSatisfy { $0.status == .failed })
        XCTAssertEqual(PanelRoundOutcome.project(from: payload.round), "failed")
        XCTAssertTrue(payload.round.seatResults.allSatisfy {
            $0.reason?.contains("session directory permission denied") == true
        })
    }

    // MARK: - --seats rerun replaces only those seats

    func testSeatsRerunReplacesOnlyRerunSeatsAsNewAttempt() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator(dispatch: { seats, _, _, _, _ in
            seats.map { seat in
                PanelFindingsParser.seatResult(
                    workerId: seat.workerId,
                    lens: seat.lens,
                    report: """
                    attempt-report-\(seat.workerId)
                    ```json
                    {"findings":[{"claim":"claim-\(seat.workerId)-\(UUID().uuidString.prefix(4))","severity":"medium","evidence":"e"}],"noMaterialFindings":false}
                    ```
                    """
                )
            }
        })
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            rounds: [], createdAt: Date()
        ))

        let first = await coord.runRound(panelId: "panel_test_1")
        guard case .success(let r1) = first else { return XCTFail("round 1 failed: \(first)") }
        let originalB = try XCTUnwrap(r1.round.seatResults.first { $0.workerId == "model_b" })

        let rerun = await coord.runRound(panelId: "panel_test_1", seatFilter: ["model_a"])
        guard case .success(let r2) = rerun else { return XCTFail("rerun failed: \(rerun)") }

        XCTAssertEqual(r2.state.rounds.count, 1, "rerun stays on the SAME round")
        XCTAssertEqual(r2.round.roundNumber, 1)
        XCTAssertEqual(r2.round.attempts.count, 2, "new attempt on the round")
        XCTAssertEqual(r2.attempt.attemptNumber, 2)
        XCTAssertEqual(r2.attempt.seatFilter, ["model_a"])
        XCTAssertEqual(r2.attempt.seatResults.count, 1)

        let mergedA = try XCTUnwrap(r2.round.seatResults.first { $0.workerId == "model_a" })
        let mergedB = try XCTUnwrap(r2.round.seatResults.first { $0.workerId == "model_b" })
        XCTAssertNotEqual(mergedA.report, r1.round.seatResults.first { $0.workerId == "model_a" }?.report,
                          "seat A was replaced")
        XCTAssertEqual(mergedB.report, originalB.report, "seat B untouched")
    }

    // MARK: - maxRounds

    func testMaxRoundsRefusesNewRoundButAllowsRerun() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            maxRounds: 1, rounds: [], createdAt: Date()
        ))

        let r1 = await coord.runRound(panelId: "panel_test_1")
        guard case .success = r1 else { return XCTFail("round 1 should succeed: \(r1)") }

        let r2 = await coord.runRound(panelId: "panel_test_1", brief: "focus")
        guard case .failure(.maxRoundsReached(1)) = r2 else {
            return XCTFail("expected maxRounds, got \(r2)")
        }

        // Rerun of current round is exempt from the ceiling.
        let rerun = await coord.runRound(
            panelId: "panel_test_1", brief: "focus-rerun", seatFilter: ["model_a"]
        )
        guard case .success(let payload) = rerun else {
            return XCTFail("rerun should be exempt: \(rerun)")
        }
        XCTAssertEqual(payload.round.roundNumber, 1)
        XCTAssertEqual(payload.attempt.attemptNumber, 2)
    }

    // MARK: - done

    func testDoneDeclaresTerminal() throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            rounds: [], createdAt: Date()
        ))

        let result = coord.done(panelId: "panel_test_1", note: "survivors noted")
        guard case .success(let state) = result else { return XCTFail("done failed: \(result)") }
        XCTAssertEqual(state.status, .done)
        XCTAssertEqual(state.note, "survivors noted")
        XCTAssertNotNil(state.finishedAt)

        let again = coord.done(panelId: "panel_test_1")
        guard case .failure(.alreadyDone) = again else {
            return XCTFail("expected alreadyDone, got \(again)")
        }
    }

    func testDoneRefusesInFlight() throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .running,
            rounds: [], createdAt: Date()
        ))
        let result = coord.done(panelId: "panel_test_1")
        guard case .failure(.roundInFlight) = result else {
            return XCTFail("expected roundInFlight, got \(result)")
        }
    }

    // MARK: - target missing

    func testTargetMissingRefusal() async throws {
        let root = tmp.appendingPathComponent("empty-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: "docs/missing.md", seats: seats(), status: .awaitingPM,
            rounds: [], createdAt: Date()
        ))

        let result = await coord.runRound(panelId: "panel_test_1")
        guard case .failure(.targetMissing) = result else {
            return XCTFail("expected targetMissing, got \(result)")
        }
    }

    // MARK: - hash pinned and changes between rounds

    func testTargetHashPinnedAndChangesBetweenRounds() async throws {
        let (root, path) = try makeTarget(contents: "version-one")
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            maxRounds: 5, rounds: [], createdAt: Date()
        ))

        let r1 = await coord.runRound(panelId: "panel_test_1")
        guard case .success(let first) = r1 else { return XCTFail("\(r1)") }
        let hash1 = first.round.targetHash
        let expected1 = PanelState.contentHash(of: Data("version-one".utf8))
        XCTAssertEqual(hash1, expected1)

        // Session edits the target between rounds (expected).
        try "version-two".write(
            to: root.appendingPathComponent(path), atomically: true, encoding: .utf8
        )

        let r2 = await coord.runRound(panelId: "panel_test_1", brief: "focus: re-attack edited text")
        guard case .success(let second) = r2 else { return XCTFail("\(r2)") }
        let hash2 = second.round.targetHash
        let expected2 = PanelState.contentHash(of: Data("version-two".utf8))
        XCTAssertEqual(hash2, expected2)
        XCTAssertNotEqual(hash1, hash2, "round N+1 must attack the CURRENT text")
        XCTAssertEqual(second.state.rounds.count, 2)
    }

    // MARK: - brief required on round 2+

    func testBriefRequiredOnRound2Plus() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .awaitingPM,
            maxRounds: 5, rounds: [], createdAt: Date()
        ))
        _ = await coord.runRound(panelId: "panel_test_1")
        let r2 = await coord.runRound(panelId: "panel_test_1") // brief nil
        guard case .failure(.briefRequired) = r2 else {
            return XCTFail("expected briefRequired, got \(r2)")
        }
    }

    // MARK: - done panel refuses new rounds

    func testDonePanelRefusesNewRound() async throws {
        let (root, path) = try makeTarget()
        let (coord, store) = makeCoordinator()
        try store.save(PanelState(
            id: "panel_test_1", projectRoot: root.path, projectId: "p",
            targetPath: path, seats: seats(), status: .done,
            rounds: [], createdAt: Date(), finishedAt: Date()
        ))
        let result = await coord.runRound(panelId: "panel_test_1")
        guard case .failure(.notAwaitingPM("done")) = result else {
            return XCTFail("expected notAwaitingPM, got \(result)")
        }
    }
}
