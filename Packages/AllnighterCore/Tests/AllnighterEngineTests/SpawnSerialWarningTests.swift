import XCTest
import AllnighterCore
@testable import AllnighterEngine

/// CHS-S02 — crew seats sharing a spawn-gated driver (`cursor_agent` /
/// `opencode` / `agy`, `maxConcurrentSpawns == 1`) serialize FIFO instead of
/// dropping (AgentOS CHS-S01). This never refuses the run — `canStart` stays
/// true — it only names the shape in `warnings` before the PM spends the
/// panel. Spec: docs/phases/Crew_Understaffed_Signal.md §Works Test.
final class SpawnSerialWarningTests: XCTestCase {

    // Real built-in model ids (so `ModelCatalog.capabilities` resolves real
    // laneTags — `TeamExplicitSeats.resolve` hard-checks lane compatibility).
    // Real driverId too: `cursor_agent` is gated at 1 in production.
    private func bench() -> [Model] {
        [
            Model(id: "model_opus", displayName: "Opus", modelLabel: "opus",
                  driverId: "claude_code", role: .both, enabled: true),
            Model(id: "model_cursor_gpt_sol", displayName: "Cursor Sol", modelLabel: "sol",
                  driverId: "cursor_agent", role: .answerer, enabled: true),
            Model(id: "model_cursor_composer_25", displayName: "Cursor Composer", modelLabel: "composer",
                  driverId: "cursor_agent", role: .answerer, enabled: true),
            Model(id: "model_gpt_sol", displayName: "GPT Sol", modelLabel: "gpt",
                  driverId: "codex", role: .answerer, enabled: true),
            Model(id: "model_grok", displayName: "Grok", modelLabel: "grok",
                  driverId: "grok", role: .answerer, enabled: true),
        ]
    }

    // cursor_agent gated at 1 (mirrors production); codex/grok/claude_code
    // unlimited. A lightweight test registry, not the bundled catalog, so this
    // stays stable regardless of production manifest edits.
    private func registry() -> DriverRegistry {
        var cursor = TestSupport.headlessManifest(id: "cursor_agent", command: "cursor-agent")
        cursor.maxConcurrentSpawns = 1
        return DriverRegistry([
            cursor,
            TestSupport.headlessManifest(id: "codex", command: "codex"),
            TestSupport.headlessManifest(id: "grok", command: "grok"),
            TestSupport.headlessManifest(id: "claude_code", command: "claude"),
        ])
    }

    // Three crew seats: two on the gated cursor_agent driver, one on codex.
    // `--seat` (Works Test 3/4) needs `crewSlotCount == seatModelIds.count`, so
    // one preset with 3 rows covers both the capability-staffed and --seat
    // scenarios.
    private func crewTeam(id: String = "chs_test_crew") -> TeamPreset {
        TeamPreset(
            id: id, displayName: "CHS Test Crew", lane: .code, outputKind: .plan,
            mutating: false, defaultEffort: .med,
            agentSpecs: [
                TeamAgentSpec(id: "r1", skillId: "regression_guard",
                              preferredModelId: "model_cursor_gpt_sol", fallbackPolicy: .exactOnly),
                TeamAgentSpec(id: "r2", skillId: "regression_guard",
                              preferredModelId: "model_cursor_composer_25", fallbackPolicy: .exactOnly),
                TeamAgentSpec(id: "r3", skillId: "regression_guard",
                              preferredModelId: "model_gpt_sol", fallbackPolicy: .exactOnly),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus", fallbackPolicy: .exactOnly)
        )
    }

    private func tmpDir() -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("alln-chs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeService(teams: [TeamPreset], tmp: URL) -> RunService {
        let models = bench()
        return RunService(
            models: models,
            registry: registry(),
            teams: teams,
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
    }

    // MARK: - Works Test 1: capability-staffed crew (no --seat)

    func testCapabilityStaffedCrewOnGatedDriverWarnsSerializedNotRefused() async {
        let team = crewTeam()
        let tmp = tmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(teams: [team], tmp: tmp)
        let dry = await service.dryRun(
            RunRequest(message: "probe", repoRoot: tmp.path, presetId: team.id, lane: .code),
            readyModels: bench()
        )
        XCTAssertTrue(dry.canStart)
        XCTAssertTrue(dry.warnings.contains {
            $0.hasPrefix("seat_driver_serialized: cursor_agent allows 1 concurrent spawn;")
                && $0.contains("model_cursor_gpt_sol") && $0.contains("model_cursor_composer_25")
        }, "expected a serialize warning naming both cursor seats, got: \(dry.warnings)")
    }

    // MARK: - Works Test 2: spawnConcurrencyLimit override removes the false alarm

    func testSpawnConcurrencyLimitOverrideRemovesFalseWarning() async {
        let team = crewTeam()
        let tmp = tmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(teams: [team], tmp: tmp)
        let dry = await service.dryRun(
            RunRequest(
                message: "probe", repoRoot: tmp.path, presetId: team.id, lane: .code,
                spawnConcurrencyLimit: 2
            ),
            readyModels: bench()
        )
        XCTAssertTrue(dry.canStart)
        XCTAssertFalse(dry.warnings.contains { $0.contains("seat_driver_serialized") },
                        "an override that removes the bottleneck must not warn; got: \(dry.warnings)")
    }

    // MARK: - Works Test 3: --seat dual Cursor + one other

    func testSeatDualCursorPlusOneWarnsAndNotRefused() async {
        let team = crewTeam()
        let tmp = tmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(teams: [team], tmp: tmp)
        let seatIds = ["model_cursor_gpt_sol", "model_cursor_composer_25", "model_gpt_sol"]
        let dry = await service.dryRun(
            RunRequest(
                message: "probe", repoRoot: tmp.path, presetId: team.id, lane: .code,
                explicitSeatModelIds: seatIds
            ),
            readyModels: bench()
        )
        XCTAssertTrue(dry.canStart, "explicit seats on a gated driver must serialize, never refuse")
        XCTAssertTrue(dry.warnings.contains {
            $0.hasPrefix("seat_driver_serialized: cursor_agent allows 1 concurrent spawn;")
        }, "expected the same serialize warning via --seat, got: \(dry.warnings)")
    }

    // MARK: - Works Test 4: three ungated seats (claude/codex/grok) never warn

    func testThreeUngatedSeatsNoWarning() async {
        let team = TeamPreset(
            id: "chs_test_ungated", displayName: "CHS Ungated Crew", lane: .code, outputKind: .plan,
            mutating: false, defaultEffort: .med,
            agentSpecs: [
                TeamAgentSpec(id: "r1", skillId: "regression_guard",
                              preferredModelId: "model_gpt_sol", fallbackPolicy: .exactOnly),
                TeamAgentSpec(id: "r2", skillId: "regression_guard",
                              preferredModelId: "model_grok", fallbackPolicy: .exactOnly),
                TeamAgentSpec(id: "r3", skillId: "regression_guard",
                              preferredModelId: "model_opus", fallbackPolicy: .exactOnly),
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", preferredModelId: "model_opus", fallbackPolicy: .exactOnly)
        )
        let tmp = tmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = makeService(teams: [team], tmp: tmp)
        let seatIds = ["model_gpt_sol", "model_grok", "model_opus"]
        let dry = await service.dryRun(
            RunRequest(
                message: "probe", repoRoot: tmp.path, presetId: team.id, lane: .code,
                explicitSeatModelIds: seatIds
            ),
            readyModels: bench()
        )
        XCTAssertTrue(dry.canStart)
        XCTAssertFalse(dry.warnings.contains { $0.contains("seat_driver_serialized") },
                        "three ungated (unlimited) seats must never warn; got: \(dry.warnings)")
    }
}
