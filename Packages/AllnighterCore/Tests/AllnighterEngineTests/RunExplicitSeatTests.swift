import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// RSO-S01 — `--seat` resolution, dry-run projection, replay, and flag gates.
final class RunExplicitSeatTests: XCTestCase {

    private func bench() -> [Model] {
        [
            Model(id: "model_gpt_sol", displayName: "GPT", modelLabel: "gpt",
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
            "model_gpt_sol", "model_grok", "model_cursor_composer_25"
        ])
        XCTAssertTrue(invocation.canStart)
        let json = invocation.makeDryRunJSON()
        let crew = json.seats?.filter { $0.stage == AgentStage.answer.rawValue } ?? []
        XCTAssertEqual(crew.map(\.modelId), [
            "model_gpt_sol", "model_grok", "model_cursor_composer_25"
        ])
        XCTAssertTrue(crew.allSatisfy { $0.reason == TeamExplicitSeats.explicitSeatingReason })
        XCTAssertTrue(invocation.teachingCommand.contains("--seat"))
        XCTAssertTrue(invocation.teachingCommand.contains("model_gpt_sol"))
    }

    /// Regression: `RunService.dryRun` must forward `--seat` into the shared resolver
    /// (resolver-only coverage previously green while the CLI dry-run path dropped seats).
    func testRunServiceDryRunForwardsExplicitSeats() async {
        let models = bench()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-rso-dry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let service = RunService(
            models: models,
            registry: DriverRegistry([
                TestSupport.headlessManifest(id: "codex", command: "codex"),
                TestSupport.headlessManifest(id: "grok", command: "grok"),
                TestSupport.headlessManifest(id: "cursor", command: "cursor"),
            ]),
            runStore: RunStore(rootDirectory: tmp.appendingPathComponent("runs")),
            commandRunner: MockCommandRunner(scripts: [:]),
            writeLock: RunWriteLockRegistry(),
            defaultSettings: {
                DefaultModelSettings(
                    defaultTier: .frontier,
                    allowHealthySubstitutions: true,
                    tiers: TierMembership(frontier: models.map(\.id))
                )
            },
            probeRecords: {
                models.map {
                    ToolProbeRecord(driverId: $0.driverId, status: .ready(version: "1"), lastProbeAt: .distantPast)
                }
            }
        )
        let seatIds = ["model_gpt_sol", "model_grok", "model_cursor_composer_25"]
        let dry = await service.dryRun(
            RunRequest(
                message: "Review docs/phases/Ephemeral_Teams.md",
                repoRoot: tmp.path,
                presetId: "code_spec_review_min",
                lane: .code,
                explicitSeatModelIds: seatIds
            ),
            readyModels: models
        )
        XCTAssertTrue(dry.canStart)
        let crew = dry.seats?.filter { $0.stage == AgentStage.answer.rawValue } ?? []
        XCTAssertEqual(crew.map(\.modelId), seatIds)
        XCTAssertTrue(crew.allSatisfy { $0.reason == TeamExplicitSeats.explicitSeatingReason })
        XCTAssertTrue(dry.nextAction.command.contains("--seat"))
    }

    func testSeatRequiresTeam() {
        let invocation = RunInvocationResolver.resolve(
            RunInvocationInput(
                message: "probe",
                projectRoot: "/tmp/alln-rso",
                flagMode: .dryRun,
                flags: .init(json: true, explicitSeatModelIds: ["model_gpt_sol"])
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
            seatIds: ["model_gpt_sol", "model_grok", "model_cursor_composer_25"],
            workerId: "model_gpt_sol"
        )
        XCTAssertFalse(invocation.canStart)
        XCTAssertTrue(invocation.blockedReason?.contains("mutually exclusive") == true)
    }

    func testIdempotencyDigestIncludesExplicitSeats() {
        let seats = ["model_gpt_sol", "model_grok", "model_cursor_composer_25"]
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
