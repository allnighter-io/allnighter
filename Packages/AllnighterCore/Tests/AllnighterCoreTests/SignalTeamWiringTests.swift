import XCTest
@testable import AllnighterCore

/// The built-in Post-to-Project Signal team: Grok scouts, three distinct minds
/// triangulate, the strongest ready flagship leads — and the customize-team
/// scout warning.
final class SignalTeamWiringTests: XCTestCase {

    private func m(_ id: String, _ driver: String, _ role: ModelRole = .answerer) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driver, role: role)
    }
    private func fullBench() -> [Model] {
        [m("model_opus", "claude_code", .both), m("model_chatgpt", "codex"),
         m("model_gemini", "antigravity"), m("model_grok", "grok"),
         m("model_sonnet", "claude_code"), m("model_cursor_auto", "cursor_agent")]
    }

    func testPostToProjectResolvesScoutGrokThreeDistinctMindsFlagshipLead() {
        let team = BuiltInTeams.team("signal_post_to_project")!
        let r = TeamResolver.resolve(team: team, requestLane: .signal, requestEffort: .med, readyModels: fullBench())

        XCTAssertTrue(r.isRunnable)
        // Stage 0: Grok scout.
        XCTAssertEqual(r.scoutWorker?.modelId, "model_grok")
        XCTAssertEqual(r.scoutWorker?.purpose, .scout)
        // Stage 1: three interpreters on three distinct drivers. The Lead reserves
        // the strongest ready flagship (ChatGPT 5.6 Sol, rank 99 — first in the
        // synthesis fallback chain after the absent Fable), so the interpreters are
        // Grok, Gemini, then the strongest remaining distinct-driver seat, Opus.
        XCTAssertEqual(r.answerWorkers.count, 3)
        let drivers = Set(r.answerWorkers.map { w in fullBench().first { $0.id == w.modelId }!.driverId })
        XCTAssertEqual(drivers.count, 3)
        XCTAssertEqual(r.answerWorkers.map(\.modelId), ["model_grok", "model_gemini", "model_opus"])
        // Lead: strongest ready flagship (ChatGPT 5.6 Sol), reserved from the worker pool.
        XCTAssertEqual(r.planWriter?.modelId, "model_chatgpt")
    }

    func testScoutWarningSilentForBuiltInButFiresWhenGrokRemoved() {
        let team = BuiltInTeams.team("signal_post_to_project")!
        XCTAssertNil(SignalScoutPolicy.scoutWarning(for: team))

        var noScout = team.duplicated(newId: "signal_custom_noscout")
        noScout.scout = nil
        XCTAssertTrue(SignalScoutPolicy.scoutWarning(for: noScout)?.contains("No scout") == true)

        var swapped = team.duplicated(newId: "signal_custom_swapped")
        swapped.scout = TeamWorkerSpec(id: "signal_source_reader", skillId: "signal_source_reader",
                                       preferredModelId: "model_chatgpt", fallbackPolicy: .laneCapable)
        XCTAssertTrue(SignalScoutPolicy.scoutWarning(for: swapped)?.contains("Grok removed") == true)

        // Non-signal teams are never warned.
        XCTAssertNil(SignalScoutPolicy.scoutWarning(for: BuiltInTeams.team("code_core")!))
    }
}
