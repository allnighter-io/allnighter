import XCTest
@testable import AllnighterCore

/// MR-S04 — table-test every identifier flag for honor-or-fail.
final class ExactIdResolverTests: XCTestCase {

    private func models() -> [Model] {
        [
            Model(id: "model_sonnet", displayName: "Sonnet 5", modelLabel: "sonnet",
                  driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_opus", displayName: "Opus 5", modelLabel: "opus",
                  driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_chatgpt", displayName: "ChatGPT", modelLabel: "gpt",
                  driverId: "codex", role: .both, enabled: false),
        ]
    }

    private func teams() -> [TeamPreset] {
        [
            TeamPreset(
                id: "code_growth", displayName: "Growth", lane: .code, outputKind: .plan,
                workerSpecs: [TeamWorkerSpec(id: "w", skillId: "product_architect", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"), builtIn: true
            ),
            TeamPreset(
                id: "code_plan", displayName: "Plan", lane: .code, outputKind: .plan,
                workerSpecs: [TeamWorkerSpec(id: "w", skillId: "product_architect", purpose: .answer)],
                lead: TeamLeadSpec(skillId: "plan_writer_build"), builtIn: true
            ),
        ]
    }

    // MARK: --worker

    func testWorkerHonorsExactId() {
        let result = ExactIdResolver.resolveWorker("model_sonnet", models: models())
        guard case .success(let model) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(model.id, "model_sonnet")
    }

    func testWorkerRejectsDisplayName() {
        let result = ExactIdResolver.resolveWorker("Sonnet 5", models: models())
        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.code, "WORKER_NOT_AVAILABLE")
        XCTAssertEqual(failure.flag, "--worker")
        XCTAssertEqual(failure.provided, "Sonnet 5")
        XCTAssertTrue(failure.message.lowercased().contains("display"))
        XCTAssertFalse(failure.candidates.isEmpty)
        XCTAssertEqual(failure.candidates.first?.id, "model_sonnet")
        XCTAssertTrue(failure.candidates.contains { $0.id == "model_sonnet" })
        XCTAssertEqual(failure.discoveryCommand, "alln menu --json")
        // Suggestions never authorize substitution — no auto-selected id to run.
        XCTAssertFalse(failure.suggestionIds.isEmpty)
    }

    func testWorkerRejectsTypoWithSuggestions() {
        let result = ExactIdResolver.resolveWorker("model_sonet", models: models())
        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.code, "WORKER_NOT_AVAILABLE")
        XCTAssertTrue(failure.suggestionIds.contains("model_sonnet"))
        XCTAssertTrue(failure.candidates.contains { $0.id == "model_sonnet" && $0.driverId == "claude_code" })
    }

    func testWorkerCaseInsensitiveExactId() {
        let result = ExactIdResolver.resolveWorker("MODEL_SONNET", models: models())
        guard case .success(let model) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(model.id, "model_sonnet")
    }

    // MARK: --team

    func testTeamHonorsExactId() {
        let result = ExactIdResolver.resolveTeam("code_growth", teams: teams())
        guard case .success(let team) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(team.id, "code_growth")
    }

    func testTeamRejectsDisplayName() {
        let result = ExactIdResolver.resolveTeam("Growth", teams: teams())
        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.code, "TEAM_NOT_FOUND")
        XCTAssertEqual(failure.flag, "--team")
        XCTAssertTrue(failure.message.lowercased().contains("display"))
        XCTAssertTrue(failure.candidates.contains { $0.id == "code_growth" })
    }

    func testTeamRejectsTypoWithSuggestions() {
        let result = ExactIdResolver.resolveTeam("code_growt", teams: teams())
        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        XCTAssertTrue(failure.suggestionIds.contains("code_growth"))
        XCTAssertEqual(failure.discoveryCommand, "alln menu --json")
    }

    // MARK: --dev-worker / panel --seat (via PilotSeatResolver)

    func testDevWorkerHonorsExactId() {
        XCTAssertEqual(
            try PilotSeatResolver.resolve(alias: "model_opus", models: models()).get(),
            "model_opus"
        )
    }

    func testDevWorkerRejectsDisplayNameAndFuzzy() {
        XCTAssertThrowsError(try PilotSeatResolver.resolve(alias: "Opus 5", models: models()).get())
        XCTAssertThrowsError(try PilotSeatResolver.resolve(alias: "opus", models: models()).get())
    }

    // The exact-id law for teams is covered by the `ExactIdResolver.resolveTeam`
    // cases above; the panel-specific resolver was deleted with `alln panel`.

    // MARK: Candidate state

    func testWorkerCandidateStateReflectsEnabled() {
        let result = ExactIdResolver.resolveWorker(
            "model_chatgp",
            models: models(),
            readyModelIds: ["model_sonnet", "model_opus"]
        )
        guard case .failure(let failure) = result else { return XCTFail("expected failure") }
        let chatgpt = failure.candidates.first { $0.id == "model_chatgpt" }
        XCTAssertEqual(chatgpt?.state, "disabled")
    }
}
