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
                      lane: WorkLane = .code,
                      lead: TeamLeadSpec? = nil) -> TeamPreset {
        TeamPreset(
            id: "code_test", displayName: "Test", lane: lane, outputKind: .plan,
            defaultEffort: .med, workerSpecs: rows,
            lead: lead ?? leadSpec()
        )
    }

    // MARK: - Self-fusion: one model fills many rows

    func testOneModelFillsManyRowsWithDistinctInstanceIndices() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "correct_fix_planner"),
            TeamWorkerSpec(id: "r3", skillId: "regression_guard")
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
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
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
        ])
        // Codex not ready; Opus is.
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("preferred model_chatgpt unavailable") })
        // #7: the worker records WHAT it was substituted from, so the UI can say so instead
        // of silently showing a different model than the team was configured with.
        XCTAssertEqual(r.answerWorkers.first?.substitutedFromModelId, "model_chatgpt")
        XCTAssertTrue(r.isRunnable)
    }

    func testPreferredUsedWhenReady() {
        let t = team(
            rows: [
                TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                               preferredModelId: "model_chatgpt", fallbackPolicy: .anyReady)
            ],
            lead: TeamLeadSpec(
                skillId: "plan_writer_build",
                preferredModelId: "model_opus",
                fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus(), codex()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_chatgpt")
        XCTAssertFalse(r.warnings.contains { $0.contains("preferred") })
        XCTAssertNil(r.answerWorkers.first?.substitutedFromModelId, "no substitution → no flag")
    }

    func testOrderedCrossSourceFallbackWinsBeforeGlobalRank() {
        let kimi = Model(id: "model_kimi_k3", displayName: "Kimi K3",
                         modelLabel: "kimi-code/k3", driverId: "kimi", role: .both)
        let t = team(rows: [
            TeamWorkerSpec(
                id: "r1",
                skillId: "regression_guard",
                preferredModelId: "model_chatgpt_sol",
                fallbackModelIds: ["model_kimi_k3", "model_opus"],
                fallbackPolicy: .strongestReady)
        ])
        let r = TeamResolver.resolve(
            team: t,
            requestLane: .code,
            requestEffort: .low,
            readyModels: [opus(), kimi])

        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_kimi_k3",
                       "declared cross-CLI order must beat global strength rank")
        XCTAssertEqual(r.answerWorkers.first?.substitutedFromModelId, "model_chatgpt_sol")
    }

    func testWorkersReserveResolvedFallbackLeadModel() {
        let kimi = Model(id: "model_kimi_k3", displayName: "Kimi K3",
                         modelLabel: "kimi-code/k3", driverId: "kimi", role: .both)
        let t = team(
            rows: [
                TeamWorkerSpec(
                    id: "r1",
                    skillId: "regression_guard",
                    preferredModelId: "missing",
                    fallbackModelIds: ["model_kimi_k3", "model_opus"])
            ],
            lead: TeamLeadSpec(
                skillId: "plan_writer_build",
                preferredModelId: "missing",
                fallbackModelIds: ["model_kimi_k3", "model_opus"]))
        let r = TeamResolver.resolve(
            team: t,
            requestLane: .code,
            requestEffort: .low,
            readyModels: [opus(), kimi])

        XCTAssertEqual(r.planWriter?.modelId, "model_kimi_k3")
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_opus",
                       "the model that actually resolved for Lead should be reserved")
    }

    // MARK: - Optional disable vs required block

    func testOptionalRowDisablesWithWarningButRuns() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "outlier_direction",
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: false)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.disabledRows.map(\.skillId), ["outlier_direction"])
        XCTAssertFalse(r.disabledRows[0].required)
        XCTAssertTrue(r.warnings.contains { $0.contains("Optional worker") && $0.contains("disabled") })
    }

    func testRequiredRowUnavailableBlocksTeam() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "visual_system_designer",
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: true)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertNotNil(r.blockReason)
        XCTAssertTrue(r.blockReason?.contains("required worker") ?? false)
    }

    // MARK: - Plan writer block

    func testPlanWriterUnavailableBlocksRun() {
        let t = team(
            rows: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer")],
            lead: leadSpec(tags: [.image]) // no ready model has .image
        )
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertEqual(r.blockReason, "plan/output writer could not resolve for Test")
        XCTAssertNil(r.planWriter)
    }

    // MARK: - Lane mismatch rejects before running

    func testLaneMismatchBlocks() {
        let t = team(rows: [TeamWorkerSpec(id: "r1", skillId: "bug_reproducer")])
        let r = TeamResolver.resolve(team: t, requestLane: .design, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertTrue(r.blockReason?.contains("is a code team") ?? false)
    }

    // MARK: - Image-capable model resolves the design row when ready

    private func sonnet(enabled: Bool = true) -> Model {
        Model(id: "model_sonnet", displayName: "Sonnet 4.6", modelLabel: "sonnet", driverId: "claude_code", role: .answerer, enabled: enabled)
    }

    func testDisabledPreferredFallsBackWithWarning() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_sonnet", fallbackPolicy: .anyReady)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_opus")
        XCTAssertTrue(r.warnings.contains { $0.contains("model_sonnet") })
    }

    func testExactOnlyBlocksWhenPreferredDisabled() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: "model_sonnet", allowedModelIds: ["model_sonnet"],
                           fallbackPolicy: .exactOnly)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
    }

    func testExactOnlyDoesNotUseOrderedFallbackChain() {
        let t = team(rows: [
            TeamWorkerSpec(
                id: "r1",
                skillId: "regression_guard",
                preferredModelId: "model_sonnet",
                fallbackModelIds: ["model_opus"],
                fallbackPolicy: .exactOnly)
        ])
        let r = TeamResolver.resolve(
            team: t,
            requestLane: .code,
            requestEffort: .low,
            readyModels: [opus()])
        XCTAssertFalse(r.isRunnable)
        XCTAssertTrue(r.answerWorkers.isEmpty)
    }

    func testImageRowResolvesWhenCapableModelReady() {
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "visual_system_designer",
                           requiredCapabilityTags: [.image], fallbackPolicy: .anyReady, required: true)
        ], lane: .design, lead: leadSpec("design_board_writer", tags: [.design]))
        let r = TeamResolver.resolve(team: t, requestLane: .design, requestEffort: .low, readyModels: [opus(), gemini()])
        XCTAssertEqual(r.answerWorkers.first?.modelId, "model_gemini")
        XCTAssertTrue(r.isRunnable)
    }

    func testWorkerRowsReserveLeadModelWhenAlternativesExist() {
        let composer = Model(id: "model_cursor_composer_25", displayName: "Composer 2.5", modelLabel: "composer-2.5",
                             driverId: "cursor_agent", role: .answerer)
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "bug_reproducer"),
            TeamWorkerSpec(id: "r2", skillId: "correct_fix_planner"),
        ], lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus", fallbackPolicy: .strongestReady))
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low,
                                     readyModels: [opus(), codex(), composer])
        XCTAssertEqual(r.planWriter?.modelId, "model_opus")
        XCTAssertFalse(r.answerWorkers.contains { $0.modelId == "model_opus" })
    }

    func testCustomModelOnReadyDriverResolves() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        CatalogRoots.overrideForTesting(
            teams: base.appendingPathComponent("teams", isDirectory: true),
            skills: base.appendingPathComponent("skills", isDirectory: true),
            models: base.appendingPathComponent("models", isDirectory: true))
        ModelCatalog.overrideRosterForTesting(fileURL: base.appendingPathComponent("model_roster.json"))
        defer {
            CatalogRoots.resetTestingOverrides()
            ModelCatalog.resetTestingOverrides()
            try? FileManager.default.removeItem(at: base)
        }
        let registry = DriverRegistry([
            DriverManifest(id: "claude_code", displayName: "Claude", kind: .headlessCLI)
        ])
        let custom = try ModelCatalog.createCustom(
            driverId: "claude_code", displayName: "Fabel", modelLabel: "fabel",
            role: .answerer, enabled: true, registry: registry)
        let customModel = ModelCatalog.resolvedModels(registry: registry).first { $0.id == custom.id }!
        let t = team(rows: [
            TeamWorkerSpec(id: "r1", skillId: "regression_guard",
                           preferredModelId: custom.id, fallbackPolicy: .exactOnly)
        ])
        let r = TeamResolver.resolve(team: t, requestLane: .code, requestEffort: .low, readyModels: [customModel])
        XCTAssertTrue(r.isRunnable)
        XCTAssertEqual(r.answerWorkers.first?.modelId, custom.id)
    }
}
