import XCTest
import AllnighterCore
import AllnighterEngine
@testable import AllnighterCLI

/// CD-S01a / CD-WT-03 — `pilot status` and `relay-status` agree on dev-leg facts.
final class PilotRelayStatusParityTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-devleg-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testMakeStatusJSONSettlingMatchesRelayJSONDevLeg() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs"))
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays"))

        let devRunId = "run_parity_settle"
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-200))
        round.devRunId = devRunId
        round.headAfterDev = "parityc0mm1t"
        round.devTurnEndReason = .reported

        let state = RelayState(
            id: "relay_parity", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, rounds: [round], createdAt: Date()
        )
        try relayStore.save(state)

        var run = TeamRun(
            id: devRunId, prompt: "p", status: .done,
            createdAt: Date().addingTimeInterval(-180), repoRoot: "/repo"
        )
        run.endReason = .completed
        try runStore.save(run, models: [])

        let pilot = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: relayStore, runStore: runStore
        )
        let relay = RelayJSON.project(
            state, contractVersion: ContractRegistry.contractVersion, runStore: runStore
        )

        XCTAssertEqual(pilot.devLeg, relay.devLeg)
        XCTAssertEqual(pilot.relay.devLeg, relay.devLeg)
        XCTAssertEqual(pilot.devLeg?.phase, .settling)
        XCTAssertEqual(pilot.devLeg?.devRunId, devRunId)
        XCTAssertEqual(pilot.devLeg?.devEndReason, "completed")
        XCTAssertEqual(pilot.devLeg?.commit, "parityc0mm1t")
        XCTAssertEqual(pilot.nextActions.first?.kind, "waitForSettlement")
        XCTAssertFalse(
            pilot.nextActions.contains { $0.kind == "pilotStatus" && $0.label.lowercased().contains("progress") },
            "settling must not tell the agent the dead dev is still progressing"
        )
    }

    func testMakeStatusJSONParkedSurfacesDevTerminalAndReviewNextAction() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-parked"))
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-parked"))

        let devRunId = "run_parity_parked"
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-400))
        round.devRunId = devRunId
        round.headAfterDev = "parkedc0mm1t"
        round.devTurnEndReason = .reported
        round.finishedAt = Date()
        round.outcome = .continued

        let state = RelayState(
            id: "relay_parked_parity", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .awaitingPM, rounds: [round], createdAt: Date()
        )
        try relayStore.save(state)

        var run = TeamRun(id: devRunId, prompt: "p", status: .done, createdAt: Date())
        run.endReason = .completed
        try runStore.save(run, models: [])

        let pilot = PilotCLI.makeStatusJSON(
            state: state, recovery: .none, stateStore: relayStore, runStore: runStore
        )
        let relay = RelayJSON.project(
            state, contractVersion: ContractRegistry.contractVersion, runStore: runStore
        )

        XCTAssertEqual(pilot.devLeg, relay.devLeg)
        XCTAssertEqual(pilot.devLeg?.phase, .parked)
        XCTAssertEqual(pilot.devLeg?.devEndReason, "completed")
        XCTAssertEqual(pilot.nextActions.first?.kind, "pilotHandoff")
        XCTAssertTrue(pilot.nextActions.contains { $0.kind == "inspectDevRun" })
    }

    /// CD-WT-05 shape: live dev → phase running; next action still wait-for-parked.
    func testLiveDevKeepsRunningPhaseAndWaitAction() throws {
        let runStore = RunStore(rootDirectory: tmp.appendingPathComponent("runs-live"))
        let relayStore = RelayStateStore(rootDirectory: tmp.appendingPathComponent("relays-live"))
        let devRunId = "run_live_dev"
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = devRunId
        let state = RelayState(
            id: "relay_live", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.callerPMModelId, devModelId: "model_dev",
            status: .running, rounds: [round], createdAt: Date()
        )
        var run = TeamRun(id: devRunId, prompt: "p", status: .running, createdAt: Date())
        run.lastActivityAt = Date()
        try runStore.save(run, models: [])

        let pilot = PilotCLI.makeStatusJSON(
            state: state, recovery: .handoffAlive, stateStore: relayStore, runStore: runStore
        )
        XCTAssertEqual(pilot.devLeg?.phase, .running)
        XCTAssertEqual(pilot.nextActions.first?.kind, "pilotStatus")
        XCTAssertTrue(pilot.nextActions.first?.command.contains("--wait-for parked") == true)
    }
}
