import XCTest
import AgentOSTeam
@testable import AllnighterCore

final class BenchReadinessTests: XCTestCase {

    private func model(_ id: String, driver: String, enabled: Bool = true) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driver, role: .answerer, enabled: enabled)
    }

    private func readyProbe(_ driver: String) -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: driver,
            status: .ready(version: "1.0"),
            invocation: nil,
            version: "1.0",
            lastProbeAt: Date()
        )
    }

    func testExcludesCoolingDriversEvenWhenProbeReady() {
        let models = [
            model("model_opus", driver: "claude_code"),
            model("model_gpt_sol", driver: "codex"),
        ]
        let ready = BenchReadiness.readyModels(
            models: models,
            probeRecords: [readyProbe("claude_code"), readyProbe("codex")],
            coolingDriverIds: ["claude_code"]
        )
        XCTAssertEqual(ready.map(\.id), ["model_gpt_sol"])
    }

    func testDisabledModelsNeverReady() {
        let models = [model("model_opus", driver: "claude_code", enabled: false)]
        let ready = BenchReadiness.readyModels(
            models: models,
            probeRecords: [readyProbe("claude_code")]
        )
        XCTAssertTrue(ready.isEmpty)
    }

    func testFutureWeeklyCooldownSurvivesRunOriginLookback() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "weekly limit",
            observedAt: now.addingTimeInterval(-2 * 24 * 60 * 60),
            observedResetAt: now.addingTimeInterval(5 * 24 * 60 * 60)
        )
        let run = TeamRun(
            id: "old-run",
            prompt: "p",
            status: .failed,
            workers: [Agent(id: "w", modelId: "m", instanceIndex: 0)],
            answers: [
                TeamAnswer(
                    memberId: "w",
                    modelId: "m",
                    role: "answer",
                    result: WorkerRunResult(
                        status: .failed,
                        capacityObservation: observation
                    )
                ),
            ],
            createdAt: now.addingTimeInterval(-2 * 24 * 60 * 60)
        )

        XCTAssertEqual(
            BenchReadiness.recentObservations(from: [run], now: now),
            [observation]
        )
    }
}

final class SeatReseatTests: XCTestCase {

    private func model(_ id: String, driver: String) -> Model {
        Model(id: id, displayName: id, modelLabel: id, driverId: driver, role: .both)
    }

    func testRateLimitTextIsEligible() {
        let result = WorkerRunResult(
            status: .failed,
            errorReason: "You've hit your session limit · resets 10:50am"
        )
        XCTAssertTrue(SeatReseat.isEligible(result))
    }

    func testAccountRateLimitObservationIsEligible() {
        let obs = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "rate limited",
            observedAt: Date(),
            observedResetAt: nil,
            retryAfterSeconds: 100,
            wakeAfter: Date().addingTimeInterval(100)
        )
        let result = WorkerRunResult(status: .failed, capacityObservation: obs)
        XCTAssertTrue(SeatReseat.isEligible(result))
    }

    func testAuthRequiredIsNotEligible() {
        let obs = CapacityObservation(
            kind: .authRequired,
            source: "claude_code",
            sourceConfidence: .messageFallback,
            rawSnippet: "not signed in",
            observedAt: Date(),
            observedResetAt: nil,
            retryAfterSeconds: nil,
            wakeAfter: nil
        )
        let result = WorkerRunResult(status: .failed, capacityObservation: obs)
        XCTAssertFalse(SeatReseat.isEligible(result))
    }

    func testGrokPaymentRequiredTextIsEligible() {
        let result = WorkerRunResult(
            status: .failed,
            errorReason: "402 Payment Required: Grok Build usage balance exhausted"
        )
        XCTAssertTrue(SeatReseat.isEligible(result))
    }

    func testDeclaredFallbackMakesFailedSeatEligible() {
        let result = WorkerRunResult(
            status: .failed,
            errorReason: "Unknown subprocess exit 1"
        )
        XCTAssertFalse(SeatReseat.isEligible(result, hasDeclaredFallbacks: false))
        XCTAssertTrue(SeatReseat.isEligible(result, hasDeclaredFallbacks: true))
    }

    func testAuthRequiredIsNotEligibleEvenWithDeclaredFallback() {
        let obs = CapacityObservation(
            kind: .authRequired,
            source: "claude_code",
            sourceConfidence: .messageFallback,
            rawSnippet: "not signed in",
            observedAt: Date()
        )
        let result = WorkerRunResult(status: .failed, capacityObservation: obs)
        XCTAssertFalse(SeatReseat.isEligible(result, hasDeclaredFallbacks: true))
    }

    func testLeadReseatSkipsFailedDriverAndPicksCodexSol() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let fable = model("model_fable", driver: "claude_code")
        let chatgpt = model("model_gpt_sol", driver: "codex")
        let opus = model("model_opus", driver: "claude_code")
        let writer = Agent(
            id: "model_fable#0", modelId: "model_fable", instanceIndex: 0,
            skillId: team.lead.skillId, purpose: .plan)
        let chain = SeatReseat.chain(for: writer, team: team, isLead: true)
        let next = SeatReseat.nextModel(
            failedModelId: fable.id,
            failedDriverId: fable.driverId,
            preferredModelId: chain.preferred,
            fallbackModelIds: chain.fallbacks,
            requiredTags: chain.tags,
            fallback: chain.policy,
            lane: .code,
            ready: [fable, chatgpt, opus]
        )
        XCTAssertEqual(next?.id, "model_gpt_sol",
                       "Lead reseat must land on Codex Sol, not another Claude seat")
    }

    func testNeedRowReseatDoesNotPickCursorSol() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let opus = model("model_opus", driver: "claude_code")
        let chatgpt = model("model_gpt_sol", driver: "codex")
        let cursorSol = model("model_cursor_gpt_sol", driver: "cursor_agent")
        let worker = Agent(
            id: "model_opus#0", modelId: "model_opus", instanceIndex: 0,
            skillId: "spec_scope_steward", purpose: .answer)
        let chain = SeatReseat.chain(for: worker, team: team, isLead: false)
        let next = SeatReseat.nextModel(
            failedModelId: opus.id,
            failedDriverId: opus.driverId,
            preferredModelId: chain.preferred,
            fallbackModelIds: chain.fallbacks,
            requiredTags: chain.tags,
            fallback: chain.policy,
            lane: .code,
            ready: [opus, chatgpt, cursorSol]
        )
        XCTAssertEqual(next?.id, "model_gpt_sol")
        XCTAssertNotEqual(next?.id, "model_cursor_gpt_sol")
    }

    func testBuildSliceDevReseatFallsBackToLaneCapableModelWhenPreferredDriverFails() {
        let team = BuiltInTeams.team("build_slice")!
        let composer = model("model_cursor_composer_25", driver: "cursor_agent")
        let grok = model("model_grok", driver: "grok")
        let chatgpt = model("model_gpt_sol", driver: "codex")

        // Relay dev worker pinned on Grok fails
        let worker = Agent(
            id: "model_grok#0", modelId: "model_grok", instanceIndex: 0,
            skillId: "execution_playbook", purpose: .answer)
        let chain = SeatReseat.chain(for: worker, team: team, isLead: false)
        let next = SeatReseat.nextModel(
            failedModelId: grok.id,
            failedDriverId: grok.driverId,
            preferredModelId: chain.preferred,
            fallbackModelIds: chain.fallbacks,
            requiredTags: chain.tags,
            fallback: chain.policy,
            lane: .code,
            ready: [composer, grok, chatgpt]
        )
        XCTAssertNotNil(next, "Relay dev seat must find a substitute when Grok driver fails")
        XCTAssertEqual(next?.id, "model_cursor_composer_25")
    }
}
