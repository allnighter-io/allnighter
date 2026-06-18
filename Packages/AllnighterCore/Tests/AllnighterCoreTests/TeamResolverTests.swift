import XCTest
@testable import AllnighterCore

final class TeamResolverTests: XCTestCase {

    // Real built-in model ids so ModelCatalog capabilities apply.
    private func opus() -> Model { Model(id: "model_opus", displayName: "Opus 4.8", modelLabel: "opus", driverId: "claude_code", role: .both) }
    private func codex() -> Model { Model(id: "model_chatgpt", displayName: "ChatGPT 5.5", modelLabel: "gpt-5.5", driverId: "codex", role: .answerer) }
    private func gemini() -> Model { Model(id: "model_gemini", displayName: "Gemini", modelLabel: "g", driverId: "antigravity", role: .answerer) }

    private func leadSpec(_ skill: String = "plan_writer_build",
                          tags: [ModelCapabilityTag] = [.planner]) -> TeamLeadSpec {
        TeamLeadSpec(skillId: skill, requiredCapabilityTags: tags, fallbackPolicy: .strongestReady)
    }

    private func team(rows: [TeamWorkerSpec],
                      lane: WorkLane = .build,
                      lead: TeamLeadSpec? = nil) -> TeamPreset {
        TeamPreset(
            id: "build_test", displayName: "Test", lane: lane, outputKind: .plan,
            defaultEffort: .med, workerSpecs: rows,
            lead: lead ?? leadSpec()
        )
    }

    // MARK: - Effort gating

    func testEffortGatingChangesActiveWorkersDeterministically() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", minEffort: .low),
            TeamWorkerSpec(id: "r2", skillId: "trace_mapper", minEffort: .med),
            TeamWorkerSpec(id: "r3", skillId: "contrarian_root_cause", purpose: .review, minEffort: .high)
        ])
        let bench = [opus()]
        XCTAssertEqual(TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: bench).answerWorkers.count, 1)
        let med = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .med, readyModels: bench)
        XCTAssertEqual(med.answerWorkers.count, 2)
        XCTAssertEqual(med.reviewWorkers.count, 0)
        let high = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .high, readyModels: bench)
        XCTAssertEqual(high.answerWorkers.count, 2)
        XCTAssertEqual(high.reviewWorkers.count, 1)
    }

    // MARK: - Self-fusion: one model fills many rows

    func testOneModelFillsManyRowsWithDistinctInstanceIndices() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", minEffort: .low),
            TeamWorkerSpec(id: "r2", skillId: "correct_fix_planner", minEffort: .low),
            TeamWorkerSpec(id: "r3", skillId: "regression_guard", minEffort: .low)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.allWorkers.map(\.modelId), Array(repeating: "model_opus", count: 4)) // 3 answer + writer
        XCTAssertEqual(r.allWorkers.map(\.id), ["model_opus#0", "model_opus#1", "model_opus#2", "model_opus#3"])
        XCTAssertEqual(Set(r.allWorkers.map(\.instanceIndex)).count, 4)
        XCTAssertEqual(r.planWriter?.purpose, .plan)
        XCTAssertTrue(r.warnings.contains { $0.contains("Only one ready model") })
    }

    // MARK: - Deterministic fallback when preferred is unavailable

    func testPreferredUnavailableFallsBackAndWarns() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard", minEffort: .low,
                           preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
        ])
        // Codex not ready; Opus is.
        let r = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: [opus()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("preferred model_chatgpt unavailable") })
        XCTAssertTrue(r.isRunnable)
    }

    func testPreferredUsedWhenReady() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard", minEffort: .low,
                           preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: [opus(), codex()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_chatgpt")
        XCTAssertFalse(r.warnings.contains { $0.contains("preferred") })
    }

    // MARK: - Optional disable vs required block

    func testOptionalRowDisablesWithWarningButRuns() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", minEffort: .low),
            TeamWorkerSpec(id: "r2", skillId: "outlier_direction", minEffort: .low,
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: false)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.disabledRows.map(\.skillId), ["outlier_direction"])
        XCTAssertFalse(r.disabledRows[0].required)
        XCTAssertTrue(r.warnings.contains { $0.contains("Optional worker") && $0.contains("disabled") })
    }

    func testRequiredRowUnavailableBlocksTeam() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", minEffort: .low),
            TeamWorkerSpec(id: "r2", skillId: "visual_system_designer", minEffort: .low,
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: true)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertNotNil(r.blockReason)
        XCTAssertTrue(r.blockReason?.contains("required worker") ?? false)
    }

    // MARK: - Plan writer block

    func testPlanWriterUnavailableBlocksRun() {
        let t = team(
            rows: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", minEffort: .low)],
            lead: leadSpec(tags: [.image]) // no ready model has .image
        )
        let r = TeamResolver.resolve(team: t, requestLane: .build, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertEqual(r.blockReason, "plan/output writer could not resolve for Test")
        XCTAssertNil(r.planWriter)
    }

    // MARK: - Lane mismatch rejects before running

    func testLaneMismatchBlocks() {
        let t = team(rows: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer", minEffort: .low)])
        let r = TeamResolver.resolve(team: t, requestLane: .design, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertTrue(r.blockReason?.contains("is a build team") ?? false)
    }

    // MARK: - Image-capable model resolves the design row when ready

    func testImageRowResolvesWhenCapableModelReady() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "visual_system_designer", minEffort: .low,
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: true)
        ], lane: .design, lead: leadSpec("design_board_writer", tags: [.design]))
        let r = TeamResolver.resolve(team: t, requestLane: .design, requestEffort: .low, readyModels: [opus(), gemini()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_gemini")
        XCTAssertTrue(r.isRunnable)
    }
}
