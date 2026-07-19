import XCTest
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
            model("model_chatgpt", driver: "codex"),
        ]
        let ready = BenchReadiness.readyModels(
            models: models,
            probeRecords: [readyProbe("claude_code"), readyProbe("codex")],
            coolingDriverIds: ["claude_code"]
        )
        XCTAssertEqual(ready.map(\.id), ["model_chatgpt"])
    }

    func testDisabledModelsNeverReady() {
        let models = [model("model_opus", driver: "claude_code", enabled: false)]
        let ready = BenchReadiness.readyModels(
            models: models,
            probeRecords: [readyProbe("claude_code")]
        )
        XCTAssertTrue(ready.isEmpty)
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

    func testLeadReseatSkipsFailedDriverAndPicksCodexSol() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let fable = model("model_fable", driver: "claude_code")
        let chatgpt = model("model_chatgpt", driver: "codex")
        let opus = model("model_opus", driver: "claude_code")
        let writer = Worker(
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
        XCTAssertEqual(next?.id, "model_chatgpt",
                       "Lead reseat must land on Codex Sol, not another Claude seat")
    }

    func testNeedRowReseatDoesNotPickCursorSol() {
        let team = BuiltInTeams.team("code_spec_review_min")!
        let opus = model("model_opus", driver: "claude_code")
        let chatgpt = model("model_chatgpt", driver: "codex")
        let cursorSol = model("model_chatgpt_sol", driver: "cursor_agent")
        let worker = Worker(
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
        XCTAssertEqual(next?.id, "model_chatgpt")
        XCTAssertNotEqual(next?.id, "model_chatgpt_sol")
    }
}
