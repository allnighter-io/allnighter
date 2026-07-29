import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// Dry-run `seats[]` projection.
final class RunDryRunSeatsTests: XCTestCase {

    private func fullBenchWithHaikuFixture() -> (ready: [Model], haikuId: String, caps: (String) -> ModelCapabilities) {
        let haikuId = "fixture_custom_haiku"
        let haiku = Model(
            id: haikuId, displayName: "Claude Haiku (fixture)", modelLabel: "claude-haiku",
            driverId: "claude_code", role: .answerer, enabled: true)
        let ready = ModelCatalog.defaultFreshModels()
            .filter { $0.enabled && ModelCatalog.allowsAutomaticSubstitution($0.id) }
            + [haiku]
        let poisoned = ModelCatalog.builtInCapabilities["model_fable"]!
        var unrated = poisoned
        unrated.strengthRank = ModelCatalog.unratedModelRank
        let caps: (String) -> ModelCapabilities = { id in
            if id == haikuId { return unrated }
            return ModelCatalog.capabilities(id)
        }
        return (ready, haikuId, caps)
    }

    private func resolveTeam(teamId: String, ready: [Model]) -> ResolvedRunInvocation {
        return RunInvocationResolver.resolve(
            RunInvocationInput(
                message: "seat check",
                projectRoot: "/tmp/alln-seat-s3",
                flagMode: .dryRun,
                flags: .init(teamId: teamId, lane: .code, json: true)
            ),
            context: RunInvocationResolveContext(
                models: ready,
                teams: TeamCatalog.all,
                readyModels: ready,
                readyModelIds: Set(ready.map(\.id)),
                defaultSettings: .fresh
            )
        )
    }

    func testDryRunSeatsPresentForSpecReviewMin() {
        let (ready, haikuId, _) = fullBenchWithHaikuFixture()
        let invocation = resolveTeam(teamId: "code_spec_review_min", ready: ready)
        let json = invocation.makeDryRunJSON()

        XCTAssertNotNil(json.seats)
        let seats = json.seats!
        XCTAssertEqual(seats.count, json.counts.seatCount)
        XCTAssertGreaterThan(seats.count, 1)
        for seat in seats {
            XCTAssertFalse(seat.modelId.isEmpty)
            XCTAssertFalse(seat.family.isEmpty)
            XCTAssertFalse(seat.driverId.isEmpty)
            XCTAssertFalse(seat.stage.isEmpty)
            XCTAssertFalse(seat.reason.isEmpty)
        }
        XCTAssertFalse(seats.map(\.modelId).contains(haikuId),
                       "fixture Haiku must not appear in dry-run seats (W8)")
    }

    func testDefaultChatDoesNotProjectCrewSeats() {
        let bench = ModelCatalog.defaultFreshModels().filter(\.enabled)
        let invocation = RunInvocationResolver.resolve(
            RunInvocationInput(
                message: "probe",
                projectRoot: "/tmp/alln-seat-s3",
                flagMode: .dryRun,
                flags: .init(json: true)
            ),
            context: RunInvocationResolveContext(
                models: bench,
                teams: TeamCatalog.all,
                readyModels: bench,
                readyModelIds: Set(bench.map(\.id)),
                defaultSettings: DefaultModelSettings(
                    defaultTier: .frontier,
                    allowHealthySubstitutions: true,
                    tiers: TierMembership(
                        frontier: ["model_sonnet"],
                        balanced: ["model_sonnet"],
                        economy: ["model_sonnet"]
                    )
                )
            )
        )
        XCTAssertEqual(invocation.seatCount, 1)
        XCTAssertNil(invocation.makeDryRunJSON().seats)
    }

    func testLeadAndPreferredRowsCarryPreferredReason() {
        let team = BuiltInTeams.team("code_spec_review_max")!
        let ready: [Model] = [
            Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                  driverId: "grok", role: .answerer),
            Model(id: "model_fable", displayName: "Fable", modelLabel: "fable",
                  driverId: "claude_code", role: .both),
            Model(id: "model_gpt_sol", displayName: "GPT", modelLabel: "gpt",
                  driverId: "codex", role: .answerer),
        ]
        let resolved = TeamResolver.resolve(
            team: team, requestLane: .code, requestEffort: .high, readyModels: ready)
        XCTAssertEqual(resolved.scoutWorker?.seatingReason, "preferred")
        XCTAssertEqual(resolved.planWriter?.seatingReason, "preferred")
    }
}
