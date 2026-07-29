import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RSO-S01 — `--seat` resolution, dry-run projection, replay, and flag gates.
final class RunExplicitSeatTests: XCTestCase {

    private func bench() -> [Model] {
        [
            Model(id: "model_chatgpt", displayName: "GPT", modelLabel: "gpt",
                  driverId: "codex", role: .answerer, enabled: true),
            Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                  driverId: "grok", role: .answerer, enabled: true),
            Model(id: "model_cursor_composer_25", displayName: "Composer", modelLabel: "composer",
                  driverId: "cursor", role: .answerer, enabled: true),
        ]
    }

    private func resolve(
        seatIds: [String],
        teamId: String = "code_spec_review_min",
        workerId: String? = nil
    ) -> ResolvedRunInvocation {
        RunInvocationResolver.resolve(
            RunInvocationInput(
                message: "Review docs/phases/Ephemeral_Teams.md",
                projectRoot: "/tmp/alln-rso",
                flagMode: .dryRun,
                flags: .init(
                    teamId: teamId,
                    pinnedModelId: workerId,
                    effort: nil,
                    lane: .code,
                    json: true,
                    explicitSeatModelIds: seatIds
                )
            ),
            context: RunInvocationResolveContext(
                models: bench(),
                teams: TeamCatalog.all,
                readyModels: bench(),
                readyModelIds: Set(bench().map(\.id)),
                defaultSettings: .fresh
            )
        )
    }

    func testDryRunProjectsExplicitSeatsInOrder() {
        let invocation = resolve(seatIds: [
            "model_chatgpt", "model_grok", "model_cursor_composer_25"
        ])
        XCTAssertTrue(invocation.canStart)
        let json = invocation.makeDryRunJSON()
        let crew = json.seats?.filter { $0.stage == AgentStage.answer.rawValue } ?? []
        XCTAssertEqual(crew.map(\.modelId), [
            "model_chatgpt", "model_grok", "model_cursor_composer_25"
        ])
        XCTAssertTrue(invocation.teachingCommand.contains("--seat"))
        XCTAssertTrue(invocation.teachingCommand.contains("model_chatgpt"))
    }

    func testSeatRequiresTeam() {
        let invocation = RunInvocationResolver.resolve(
            RunInvocationInput(
                message: "probe",
                projectRoot: "/tmp/alln-rso",
                flagMode: .dryRun,
                flags: .init(json: true, explicitSeatModelIds: ["model_chatgpt"])
            ),
            context: RunInvocationResolveContext(
                models: bench(),
                teams: TeamCatalog.all,
                readyModels: bench(),
                readyModelIds: Set(bench().map(\.id)),
                defaultSettings: .fresh
            )
        )
        XCTAssertFalse(invocation.canStart)
        XCTAssertTrue(invocation.blockedReason?.contains("--seat requires") == true)
    }

    func testSeatConflictsWithWorker() {
        let invocation = resolve(
            seatIds: ["model_chatgpt", "model_grok", "model_cursor_composer_25"],
            workerId: "model_chatgpt"
        )
        XCTAssertFalse(invocation.canStart)
        XCTAssertTrue(invocation.blockedReason?.contains("mutually exclusive") == true)
    }

    func testIdempotencyDigestIncludesExplicitSeats() {
        let seats = ["model_chatgpt", "model_grok", "model_cursor_composer_25"]
        let base = AsyncTeamCanonicalPayload(
            prompt: "p",
            lane: WorkLane.code.rawValue,
            teamPresetId: "code_spec_review_min",
            effort: EffortLevel.med.rawValue,
            modelId: nil,
            type: nil,
            context: nil,
            repoRoot: "/tmp/alln-rso"
        )
        let withSeats = AsyncTeamCanonicalPayload(
            prompt: "p",
            lane: WorkLane.code.rawValue,
            teamPresetId: "code_spec_review_min",
            effort: EffortLevel.med.rawValue,
            modelId: nil,
            type: nil,
            context: nil,
            repoRoot: "/tmp/alln-rso",
            explicitSeatModelIds: seats
        )
        XCTAssertNotEqual(IdempotencyStore.digest(base), IdempotencyStore.digest(withSeats))
    }
}
