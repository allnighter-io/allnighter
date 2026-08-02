import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// Completion Delivery Works Tests (CD-WT-01, 04, 05, 06).
/// Projection honesty is CD-S01a; this suite locks detached-ack + waiter reflexes.
final class CompletionDeliveryWorksTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-cd-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - CD-WT-04: detached ack has exact parked waiter

    func testPilotHandoffNoWaitAckHasExactParkedWaiter() throws {
        let delivery = DetachedDispatch.waitDelivery(
            kind: "pilot", id: "relay_cd_wt04", commandPrefix: "alln"
        )
        XCTAssertEqual(delivery.path, "wait")
        let command = try XCTUnwrap(delivery.command)
        XCTAssertEqual(
            command,
            "alln loop status relay_cd_wt04 --wait-for parked --timeout 7200 --json"
        )

        let ack = PilotHandoffDispatchJSON(
            loopId: "relay_cd_wt04", status: "dispatched", roundInFlight: false,
            pid: 99, serveAutoLaunch: "alreadyRunning", delivery: delivery
        )
        let data = try XCTUnwrap(AllnighterCLI.jsonLine(ack).data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wire = try XCTUnwrap(json["delivery"] as? [String: Any])
        XCTAssertEqual(wire["path"] as? String, "wait")
        XCTAssertEqual(wire["command"] as? String, command)
    }

    func testRelayDetachedAcksShareWaitDeliverySurface() {
        // Loop/relay keep delivery.wait; run is ORS-S03a nextAction (tested below).
        for kind in ["relay", "pilot"] {
            let d = DetachedDispatch.waitDelivery(kind: kind, id: "id_1", commandPrefix: "alln")
            XCTAssertEqual(d.path, "wait", kind)
            XCTAssertNotNil(d.command, kind)
            XCTAssertTrue(d.command?.contains("--wait-for") == true, kind)
            XCTAssertTrue(d.command?.contains("--json") == true, kind)
        }
        XCTAssertTrue(
            DetachedDispatch.waitDelivery(kind: "relay", id: "r1", commandPrefix: "alln")
                .command?.contains("loop status r1 --wait-for terminal") == true
        )
        XCTAssertTrue(
            DetachedDispatch.waitDelivery(kind: "pilot", id: "r1", commandPrefix: "alln")
                .command?.contains("loop status r1 --wait-for parked") == true
        )
        let runNext = DetachedDispatch.runNextAction(id: "run1")
        XCTAssertEqual(runNext.kind, "showRun")
        XCTAssertEqual(runNext.command, "alln show run1 --stream")
        XCTAssertFalse(runNext.command.contains("team status"))
        XCTAssertFalse(runNext.command.contains("--wait-for"))
    }

    /// Structural: the `relay` no-wait path must attach waitDelivery (no silent omit).
    /// LVC Piece 1/2: `pilot handoff --no-wait`'s background dispatch (`kind: "pilot"`)
    /// was deleted along with the retired raw-args `pilot handoff` CLI entry point —
    /// `alln loop step` has no `--no-wait` in the locked v7 grammar, so there is no
    /// live pilot-side no-wait ack to guard here anymore. `DetachedDispatch.waitDelivery`
    /// itself still answers `kind: "pilot"` (tested above) in case a future caller needs it.
    func testRelayNoWaitSourceEmitsWaitDelivery() throws {
        let cliDir = sourcesRoot().appendingPathComponent("AllnighterCLI")
        let relay = try String(
            contentsOf: cliDir.appendingPathComponent("LoopEngineCLI.swift"), encoding: .utf8
        )
        XCTAssertTrue(relay.contains("DetachedDispatch.waitDelivery"), "relay emitDispatchAck")
        XCTAssertTrue(relay.contains("func emitDispatchAck"), "shared relay ack helper")
        // No second spelling of the waiter (CD non-goal: alln wait alias).
        XCTAssertFalse(relay.contains("alln wait "))
    }

    // MARK: - CD-WT-01: only waiter command → parked + dev terminal facts

    func testWaiterThenStatusShowsParkedWithDevTerminalFacts() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let loopStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("loops"))
        let devRunId = "run_cd_wt01"

        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-500))
        round.devRunId = devRunId
        round.headAfterDev = "wt01c0mm1t"
        round.devTurnEndReason = .reported
        round.finishedAt = Date()
        round.outcome = .continued

        // Simulate: waiter observes transition running → awaitingPM (only that command).
        var liveStatus: LoopState.Status = .running
        let wait = PMTurnStatusWait.wait(
            target: .parked,
            timeout: 1,
            pollInterval: 0.05,
            readStatus: {
                // First poll still running; second poll parked (settlement finished).
                if liveStatus == .running {
                    liveStatus = .awaitingPM
                    return .running
                }
                return .awaitingPM
            },
            now: { Date() },
            sleep: { _ in }
        )
        XCTAssertEqual(wait.outcome, .matched)
        XCTAssertEqual(wait.status, .awaitingPM)

        let state = LoopState(
            id: "relay_wt01", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: LoopState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, rounds: [round], createdAt: Date()
        )
        try loopStore.save(state)
        var run = TeamRun(id: devRunId, prompt: "p", status: .done, createdAt: Date())
        run.endReason = .completed
        try runStore.save(run, models: [])

        var status = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: loopStore, runStore: runStore
        )
        status.waitOutcome = wait.outcome.rawValue

        XCTAssertEqual(status.devLeg?.phase, .parked)
        XCTAssertEqual(status.devLeg?.devRunId, devRunId)
        XCTAssertEqual(status.devLeg?.devEndReason, "completed")
        XCTAssertEqual(status.devLeg?.commit, "wt01c0mm1t")
        XCTAssertEqual(status.waitOutcome, "matched")
        XCTAssertEqual(status.nextActions.first?.kind, "pilotHandoff")
    }

    // MARK: - CD-WT-05: live dev → waiter stays blocked / honest timeout

    func testWaiterTimesOutWhileDevStillLiveAndRelayRunning() {
        final class Clock: @unchecked Sendable {
            var t = Date(timeIntervalSince1970: 1_000_000)
            func tick(_ dt: TimeInterval = 0.06) -> Date {
                t = t.addingTimeInterval(dt)
                return t
            }
        }
        let clock = Clock()
        let wait = PMTurnStatusWait.wait(
            target: .parked,
            timeout: 0.15,
            pollInterval: 0.05,
            readStatus: { .running },
            now: { clock.tick() },
            sleep: { _ in }
        )
        XCTAssertEqual(wait.outcome, .timedOut)
        XCTAssertEqual(wait.status, .running)
        XCTAssertFalse(PMTurnStatusWait.Target.parked.matches(.running))
    }

    // MARK: - CD-WT-06: terminal-failed still parks with failure facts

    func testFailedDevStillParksWithFailureFactsVisible() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-fail"))
        let loopStore = LoopStateStore(rootDirectory: tmp.appendingPathComponent("relays-fail"))
        let devRunId = "run_cd_wt06"
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = devRunId
        round.devTurnEndReason = .reported
        round.headAfterDev = "failc0mm1t"
        let state = LoopState(
            id: "relay_wt06", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: LoopState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, rounds: [round], createdAt: Date()
        )
        var run = TeamRun(id: devRunId, prompt: "p", status: .failed, createdAt: Date())
        run.endReason = .failed
        try runStore.save(run, models: [])

        let pilot = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: loopStore, runStore: runStore
        )
        let relay = LoopJSON.project(
            state, contractVersion: ContractRegistry.contractVersion, runStore: runStore
        )
        XCTAssertEqual(pilot.devLeg, relay.devLeg)
        XCTAssertEqual(pilot.devLeg?.phase, .parked)
        XCTAssertEqual(pilot.devLeg?.devRunStatus, "failed")
        XCTAssertEqual(pilot.devLeg?.devEndReason, "failed")
        XCTAssertEqual(pilot.devLeg?.commit, "failc0mm1t")
    }

    // MARK: - helpers

    private func sourcesRoot() -> URL {
        // Tests/AllnighterEngineTests/ThisFile → …/Sources
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}
