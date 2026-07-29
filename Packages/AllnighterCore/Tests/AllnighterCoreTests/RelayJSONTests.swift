import XCTest
@testable import AllnighterCore

/// `RelayJSON` is the one wire shape `alln pair relay*` and MCP `pair_relay*` both
/// project (docs/phases/PM_Relay.md §6 R-S05/R-S06, §7 works-test output shape).
/// These tests cover the `RelayState` → `RelayJSON` projection — never a second
/// copy of run-truth, only its wire mapping.
final class RelayJSONTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeRound(
        _ n: Int,
        baseline: String?, head: String?,
        pmRunId: String?, devRunId: String?,
        verdict: RelayVerdict?, gate: RelayGateSummary? = nil,
        outcome: RelayRound.Outcome? = nil
    ) -> RelayRound {
        RelayRound(
            roundNumber: n, baselineHead: baseline, headAfterDev: head,
            pmRunId: pmRunId, devRunId: devRunId, verdict: verdict, gate: gate,
            startedAt: now, finishedAt: now, outcome: outcome
        )
    }

    func testProjectsRunningRelayWithNoVerdictYet() {
        let state = RelayState(
            id: "relay_1", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running,
            rounds: [makeRound(1, baseline: "abc123", head: nil, pmRunId: "run_pm_1", devRunId: nil, verdict: nil)],
            createdAt: now
        )

        let json = RelayJSON.project(state, contractVersion: "1.0.0")

        XCTAssertEqual(json.schemaVersion, 1)
        XCTAssertEqual(json.contractVersion, "1.0.0")
        XCTAssertEqual(json.relayId, "relay_1")
        XCTAssertEqual(json.status, "running")
        XCTAssertEqual(json.rounds, 1)
        XCTAssertNil(json.verdict)
        XCTAssertNil(json.note)
        XCTAssertNil(json.stoppedReason)
        XCTAssertEqual(json.docPath, "docs/spec.md")
        XCTAssertEqual(json.pmModelId, "model_pm")
        XCTAssertEqual(json.devModelId, "model_dev")
        XCTAssertEqual(json.roundLog.count, 1)
        XCTAssertEqual(json.roundLog[0].round, 1)
        XCTAssertEqual(json.roundLog[0].baseline, "abc123")
        XCTAssertNil(json.roundLog[0].head)
        XCTAssertEqual(json.roundLog[0].pmRunId, "run_pm_1")
        XCTAssertNil(json.roundLog[0].devRunId)
        XCTAssertNil(json.roundLog[0].verdict)
    }

    func testProjectsDoneRelayWithFullRoundLog() {
        let round1 = makeRound(
            1, baseline: "aaa111", head: "bbb222", pmRunId: "run_pm_1", devRunId: "run_dev_1",
            verdict: RelayVerdict(verdict: .continueRelay, handover: "Implement the thing."),
            outcome: .continued
        )
        let round2 = makeRound(
            2, baseline: "bbb222", head: "bbb222", pmRunId: "run_pm_2", devRunId: nil,
            verdict: RelayVerdict(verdict: .done, note: "All criteria met."),
            outcome: .done
        )
        let state = RelayState(
            id: "relay_2", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .done,
            rounds: [round1, round2], createdAt: now, finishedAt: now, note: "All criteria met."
        )

        let json = RelayJSON.project(state, contractVersion: "1.0.0")

        XCTAssertEqual(json.status, "done")
        XCTAssertEqual(json.rounds, 2)
        // Top-level `verdict` mirrors the LAST round's verdict class.
        XCTAssertEqual(json.verdict, "done")
        XCTAssertEqual(json.note, "All criteria met.")
        XCTAssertEqual(json.roundLog.map(\.verdict), ["continue", "done"])
        XCTAssertEqual(json.roundLog[0].baseline, "aaa111")
        XCTAssertEqual(json.roundLog[0].head, "bbb222")
        XCTAssertEqual(json.roundLog[0].pmRunId, "run_pm_1")
        XCTAssertEqual(json.roundLog[0].devRunId, "run_dev_1")
    }

    func testProjectsEscalatedRelayWithGateBlock() {
        let gate = RelayGateSummary(
            allowed: false, dangerClass: "destructiveGit", code: "RELAY_HANDOVER_UNSAFE",
            reason: "destructive git instruction", snippet: "git reset --hard"
        )
        let round = makeRound(
            1, baseline: "abc123", head: nil, pmRunId: "run_pm_1", devRunId: nil,
            verdict: RelayVerdict(verdict: .continueRelay, handover: "git reset --hard the branch"),
            gate: gate, outcome: .escalated
        )
        let state = RelayState(
            id: "relay_3", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .escalated,
            rounds: [round], createdAt: now, finishedAt: now,
            note: "HandoverGate blocked (destructiveGit, RELAY_HANDOVER_UNSAFE): destructive git instruction"
        )

        let json = RelayJSON.project(state, contractVersion: "1.0.0")

        XCTAssertEqual(json.status, "escalated")
        XCTAssertEqual(json.verdict, "continue")
        XCTAssertEqual(json.roundLog[0].gate?.allowed, false)
        XCTAssertEqual(json.roundLog[0].gate?.dangerClass, "destructiveGit")
        XCTAssertEqual(json.roundLog[0].gate?.code, "RELAY_HANDOVER_UNSAFE")
    }

    func testProjectsStoppedRelayWithStoppedReason() {
        let state = RelayState(
            id: "relay_4", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .stopped,
            rounds: [], createdAt: now, finishedAt: now,
            stoppedReason: "reached --max-rounds (20)"
        )

        let json = RelayJSON.project(state, contractVersion: "1.0.0")

        XCTAssertEqual(json.status, "stopped")
        XCTAssertEqual(json.stoppedReason, "reached --max-rounds (20)")
        XCTAssertEqual(json.rounds, 0)
        XCTAssertTrue(json.roundLog.isEmpty)
        XCTAssertNil(json.verdict)
    }

    // MARK: - Pilot (pmMode, dirtyFilesCount, hasExternalSubmission)

    func testProjectsSpawnedRelayWithSpawnedPMMode() {
        let state = RelayState(
            id: "relay_spawned", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .running,
            createdAt: now
        )
        XCTAssertEqual(RelayJSON.project(state, contractVersion: "1.0.0").pmMode, "spawned")
    }

    func testProjectsPilotRelayWithExternalPMModeAndAwaitingPMStatus() {
        let round = RelayRound(
            roundNumber: 1, baselineHead: "abc123", headAfterDev: "def456", devRunId: "run_dev_1",
            verdict: RelayVerdict(verdict: .continueRelay, handover: "Implement the thing."),
            gate: RelayGateSummary(allowed: true), startedAt: now, finishedAt: now, outcome: .continued,
            externalSubmission: "PM review text.\n\n```json\n{\"verdict\": \"continue\", \"handover\": \"Implement the thing.\"}\n```",
            dirtyFiles: ["a.swift", "b.swift"]
        )
        let state = RelayState(
            id: "relay_pilot", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: RelayState.externalPMWorkerId, devModelId: "model_dev", status: .awaitingPM,
            pmMode: .external, rounds: [round], createdAt: now
        )

        let json = RelayJSON.project(state, contractVersion: "1.0.0")

        XCTAssertEqual(json.pmMode, "external")
        XCTAssertEqual(json.status, "awaitingPM")
        XCTAssertNil(json.roundLog[0].pmRunId, "no PM turn dispatches in Pilot")
        XCTAssertEqual(json.roundLog[0].dirtyFilesCount, 2)
        XCTAssertTrue(json.roundLog[0].hasExternalSubmission)
    }

    func testSpawnedRoundNeverCarriesPilotOnlyFields() {
        let json = RelayJSON.project(
            RelayState(
                id: "relay_spawned_round", projectRoot: "/repo", docPath: "docs/spec.md",
                pmModelId: "model_pm", devModelId: "model_dev", status: .running,
                rounds: [makeRound(1, baseline: "a", head: "b", pmRunId: "p1", devRunId: "d1", verdict: nil)],
                createdAt: now
            ),
            contractVersion: "1.0.0"
        )
        XCTAssertNil(json.roundLog[0].dirtyFilesCount)
        XCTAssertFalse(json.roundLog[0].hasExternalSubmission)
    }

    func testRoundTripsThroughCoreJSON() throws {
        let state = RelayState(
            id: "relay_5", projectRoot: "/repo", docPath: "docs/spec.md",
            pmModelId: "model_pm", devModelId: "model_dev", status: .done,
            rounds: [makeRound(1, baseline: "a", head: "b", pmRunId: "p1", devRunId: "d1",
                                verdict: RelayVerdict(verdict: .done, note: "done"), outcome: .done)],
            createdAt: now, finishedAt: now, note: "done"
        )
        let json = RelayJSON.project(state, contractVersion: "1.0.0")
        let data = try CoreJSON.encode(json)
        let decoded = try CoreJSON.decode(RelayJSON.self, from: data)
        XCTAssertEqual(decoded, json)
    }
}
