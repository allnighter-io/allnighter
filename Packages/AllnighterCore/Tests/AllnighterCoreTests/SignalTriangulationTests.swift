import XCTest
@testable import AllnighterCore

/// Distinct-driver triangulation: a triangulated worker row spreads its `count`
/// across several CLI drivers (many minds), prefers cheaper models, reserves the
/// strongest for the Lead, and degrades honestly (with a warning) when too few
/// drivers are ready. Real built-in model ids so ModelCatalog capabilities apply.
final class SignalTriangulationTests: XCTestCase {

    private func m(_ id: String, _ driver: String, _ role: ModelRole = .answerer) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driver, role: role)
    }
    private func opus() -> Model { m("model_opus", "claude_code", .both) }
    private func grok() -> Model { m("model_grok", "grok") }
    private func chatgpt() -> Model { m("model_chatgpt", "codex") }
    private func gemini() -> Model { m("model_gemini", "antigravity") }
    private func sonnet() -> Model { m("model_sonnet", "claude_code") }
    private func cursorAuto() -> Model { m("model_cursor_auto", "cursor_agent") }

    /// One triangulated interpreter row (count 3) preferring Grok → GPT → Gemini.
    private func signalTeam(count: Int = 3) -> TeamPreset {
        TeamPreset(
            id: "signal_test", displayName: "Signal Test", lane: .signal, outputKind: .insight,
            defaultEffort: .med,
            workerSpecs: [
                TeamWorkerSpec(
                    id: "interpret", skillId: "signal_project_fit", purpose: .answer,
                    count: count, required: true, triangulate: true,
                    triangulatePreferenceIds: ["model_grok", "model_chatgpt", "model_gemini"])
            ],
            lead: TeamLeadSpec(skillId: "insight_writer", requiredCapabilityTags: [.planner],
                               fallbackPolicy: .strongestReady))
    }

    func testTriangulationPicksDistinctDriversAndReservesStrongestForLead() {
        let bench = [opus(), grok(), chatgpt(), gemini(), sonnet(), cursorAuto()]
        let r = TeamResolver.resolve(
            team: signalTeam(), requestLane: .signal, requestEffort: .med,
            readyModels: bench)
        XCTAssertTrue(r.isRunnable)
        // Strongest ready .planner is ChatGPT 5.6 Sol (rank 99 > Opus 90), so it is
        // reserved for the Lead; the three interpreters spread across the distinct
        // drivers below it: Grok (pref #1), Gemini (pref #3; ChatGPT is reserved),
        // then the strongest remaining distinct-driver seat, Opus.
        XCTAssertEqual(r.answerWorkers.map(\.modelId), ["model_grok", "model_gemini", "model_opus"])
        XCTAssertEqual(Set(r.answerWorkers.map { w -> String in
            bench.first { $0.id == w.modelId }!.driverId }).count, 3)
        XCTAssertEqual(r.planWriter?.modelId, "model_chatgpt")
        XCTAssertFalse(r.answerWorkers.contains { $0.modelId == "model_chatgpt" }) // reserved for Lead
        XCTAssertFalse(r.warnings.contains { $0.contains("degraded") })
    }

    func testDefaultsToWhateverIsAvailableWhenPreferredAbsent() {
        // No GPT/Gemini on the bench — must still fill 3 distinct drivers.
        let r = TeamResolver.resolve(
            team: signalTeam(), requestLane: .signal, requestEffort: .med,
            readyModels: [opus(), grok(), sonnet(), cursorAuto()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.count, 3)
        let drivers = Set(r.answerWorkers.map { w -> String in
            [grok(), sonnet(), cursorAuto()].first { $0.id == w.modelId }!.driverId })
        XCTAssertEqual(drivers.count, 3)
        XCTAssertFalse(r.answerWorkers.contains { $0.modelId == "model_opus" }) // reserved for Lead
    }

    func testDegradesWithWarningWhenTooFewDrivers() {
        // Only Grok available for workers (Opus reserved for the Lead).
        let r = TeamResolver.resolve(
            team: signalTeam(), requestLane: .signal, requestEffort: .med,
            readyModels: [opus(), grok()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.map(\.modelId), ["model_grok"])
        XCTAssertEqual(r.planWriter?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("triangulation degraded") })
    }

    func testSingleModelBenchStillProducesAWorker() {
        // One CLI only: the same model must serve as both worker and Lead.
        let r = TeamResolver.resolve(
            team: signalTeam(), requestLane: .signal, requestEffort: .med,
            readyModels: [grok()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.map(\.modelId), ["model_grok"])
        XCTAssertEqual(r.planWriter?.modelId, "model_grok")
    }
}
