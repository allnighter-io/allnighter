import XCTest
@testable import AllnighterCore

/// CD-S01a Works Tests — shared dev-leg projection for pilot status + relay-status.
/// Distinguishes running / settling / parked so aggregate relay `running` never
/// stands in for a terminal linked dev worker.
final class RelayDevLegProjectionTests: XCTestCase {

    // MARK: - CD-WT-02: one-shot never presents pure "running" for a dead dev leg

    func testSettlingWhenRelayRunningAndDevJournalTerminal() {
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-300))
        round.devRunId = "run_dev_settling"
        round.headAfterDev = "abc123def"
        round.devTurnEndReason = .reported

        var state = RelayState(
            id: "relay_settle", projectRoot: "/tmp/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.externalPMModelId, devModelId: "model_dev",
            status: .running, pmMode: .external, createdAt: Date()
        )
        state.rounds = [round]

        var run = TeamRun(
            id: "run_dev_settling", prompt: "implement", status: .done,
            createdAt: Date().addingTimeInterval(-280), repoRoot: "/tmp/repo"
        )
        run.endReason = .completed
        run.lastActivityAt = Date().addingTimeInterval(-60)

        let store = FakeRunStore(runs: ["run_dev_settling": run])
        let leg = StreamLiveness.devLegProjection(state: state, runStore: store)

        XCTAssertEqual(leg.phase, .settling, "worker terminal + relay still running → settling")
        XCTAssertEqual(leg.devRunId, "run_dev_settling")
        XCTAssertEqual(leg.devRunStatus, RunStatus.done.rawValue)
        XCTAssertEqual(leg.devEndReason, RunEndReason.completed.rawValue)
        XCTAssertEqual(leg.commit, "abc123def")
        XCTAssertNotEqual(leg.phase, .running, "must not look like live dev progress")
    }

    // MARK: - State 1 vs 2 vs 3

    func testRunningWhenDevJournalNonTerminal() {
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = "run_dev_live"
        var state = RelayState(
            id: "relay_live", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: "pm", devModelId: "dev", status: .running, createdAt: Date()
        )
        state.rounds = [round]
        var run = TeamRun(id: "run_dev_live", prompt: "p", status: .running, createdAt: Date())
        run.lastActivityAt = Date()
        let store = FakeRunStore(runs: ["run_dev_live": run])

        let leg = StreamLiveness.devLegProjection(state: state, runStore: store)
        XCTAssertEqual(leg.phase, .running)
        XCTAssertEqual(leg.devRunStatus, "running")
        XCTAssertNil(leg.devEndReason)
    }

    func testParkedWhenAwaitingPMAndDevTerminal() {
        var round = RelayRound(roundNumber: 1, startedAt: Date().addingTimeInterval(-600))
        round.devRunId = "run_dev_parked"
        round.headAfterDev = "deadbeef"
        round.devTurnEndReason = .reported
        round.finishedAt = Date().addingTimeInterval(-30)
        round.outcome = .continued

        var state = RelayState(
            id: "relay_parked", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: RelayState.externalPMModelId, devModelId: "dev",
            status: .awaitingPM, pmMode: .external, createdAt: Date()
        )
        state.rounds = [round]

        var run = TeamRun(id: "run_dev_parked", prompt: "p", status: .done, createdAt: Date())
        run.endReason = .completed
        let store = FakeRunStore(runs: ["run_dev_parked": run])

        let leg = StreamLiveness.devLegProjection(state: state, runStore: store)
        XCTAssertEqual(leg.phase, .parked)
        XCTAssertEqual(leg.devRunId, "run_dev_parked")
        XCTAssertEqual(leg.devRunStatus, "done")
        XCTAssertEqual(leg.devEndReason, "completed")
        XCTAssertEqual(leg.commit, "deadbeef")
    }

    /// CD-WT-06 shape: failed terminal still parks with failure facts visible.
    func testParkedSurfacesFailedDevEndReason() {
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = "run_dev_fail"
        round.devTurnEndReason = .reported
        var state = RelayState(
            id: "relay_fail", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: RelayState.externalPMModelId, devModelId: "dev",
            status: .awaitingPM, pmMode: .external, createdAt: Date()
        )
        state.rounds = [round]
        var run = TeamRun(id: "run_dev_fail", prompt: "p", status: .failed, createdAt: Date())
        run.endReason = .failed
        let store = FakeRunStore(runs: ["run_dev_fail": run])

        let leg = StreamLiveness.devLegProjection(state: state, runStore: store)
        XCTAssertEqual(leg.phase, .parked)
        XCTAssertEqual(leg.devRunStatus, "failed")
        XCTAssertEqual(leg.devEndReason, "failed")
    }

    func testNoneWhenNoDevRunIdWhileRunning() {
        let state = RelayState(
            id: "relay_no_dev", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: "pm", devModelId: "dev", status: .running,
            rounds: [RelayRound(roundNumber: 1, startedAt: Date())],
            createdAt: Date()
        )
        let leg = StreamLiveness.devLegProjection(state: state, runStore: FakeRunStore(runs: [:]))
        XCTAssertEqual(leg.phase, .none)
        XCTAssertNil(leg.devRunId)
    }

    func testSettlingFallsBackToRoundEndReasonWhenJournalMissing() {
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = "run_missing"
        round.devTurnEndReason = .stalled
        round.headAfterDev = "cafebabe"
        var state = RelayState(
            id: "relay_missing", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: "pm", devModelId: "dev", status: .running, createdAt: Date()
        )
        state.rounds = [round]
        let leg = StreamLiveness.devLegProjection(state: state, runStore: FakeRunStore(runs: [:]))
        XCTAssertEqual(leg.phase, .settling)
        XCTAssertEqual(leg.devEndReason, "stalled")
        XCTAssertEqual(leg.commit, "cafebabe")
        XCTAssertNil(leg.devRunStatus)
    }

    // MARK: - CD-WT-03: pilot / relay-status pair-equality (same helper)

    func testPilotAndRelayJSONShareDevLegFacts() {
        var round = RelayRound(roundNumber: 1, startedAt: Date())
        round.devRunId = "run_pair"
        round.headAfterDev = "111aaa"
        var state = RelayState(
            id: "relay_pair", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: RelayState.externalPMModelId, devModelId: "dev",
            status: .running, pmMode: .external, createdAt: Date()
        )
        state.rounds = [round]
        var run = TeamRun(id: "run_pair", prompt: "p", status: .done, createdAt: Date())
        run.endReason = .completed
        let store = FakeRunStore(runs: ["run_pair": run])

        let fromHelper = StreamLiveness.devLegProjection(state: state, runStore: store)
        let relayJSON = RelayJSON.project(
            state, contractVersion: ContractRegistry.contractVersion, runStore: store
        )

        XCTAssertEqual(relayJSON.devLeg, fromHelper)
        XCTAssertEqual(relayJSON.devLeg?.phase, .settling)
        XCTAssertEqual(relayJSON.devLeg?.devRunId, "run_pair")
        XCTAssertEqual(relayJSON.devLeg?.devEndReason, "completed")
        XCTAssertEqual(relayJSON.devLeg?.commit, "111aaa")
        // Durable relay status remains running; operational phase is settling.
        XCTAssertEqual(relayJSON.status, "running")
        XCTAssertNotEqual(relayJSON.devLeg?.phase.rawValue, "running")
    }

    func testRelayJSONOmitsDevLegWithoutRunStore() {
        let state = RelayState(
            id: "r", projectRoot: "/tmp", docPath: "d.md",
            pmModelId: "pm", devModelId: "dev", status: .awaitingPM, createdAt: Date()
        )
        let json = RelayJSON.project(state, contractVersion: "test")
        XCTAssertNil(json.devLeg)
    }
}

// MARK: - Fake store (mirrors StreamLivenessTests)

private struct FakeRunStore: RunStoreReading {
    var runs: [String: TeamRun]
    func load(runId: String) -> TeamRun? { runs[runId] }
}
