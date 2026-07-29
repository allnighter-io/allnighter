import XCTest
@testable import AllnighterCore

/// CRAFT-1: the team/craft model gains Signal as the 4th craft plus a mutating
/// flag, on the SAME substrate (no second system).
final class CraftModelTests: XCTestCase {
    func testSignalIsAFourthCraft() {
        XCTAssertEqual(WorkLane.allCases.count, 4)
        XCTAssertTrue(WorkLane.allCases.contains(.signal))
        XCTAssertEqual(WorkLane.signal.rawValue, "signal")
    }

    func testInsightOutputKind() {
        XCTAssertTrue(TeamOutputKind.allCases.contains(.insight))
    }

    func testTeamPresetRoundTripsMutatingFlag() throws {
        let team = TeamPreset(
            id: "signal_demo", displayName: "Demo", lane: .signal, outputKind: .insight,
            mutating: false,
            agentSpecs: [TeamAgentSpec(id: "r", skillId: "s")],
            lead: TeamLeadSpec(skillId: "w"), builtIn: true)
        let data = try CoreJSON.encode(team)
        let back = try CoreJSON.decode(TeamPreset.self, from: data)
        XCTAssertEqual(back.mutating, false)
        XCTAssertEqual(back.lane, .signal)
        XCTAssertEqual(back.outputKind, .insight)
    }

    func testExistingBuiltInsHaveCorrectMutationShape() {
        let executionIDs: Set<String> = ["default_chat", "build_slice"]
        for team in BuiltInTeams.all {
            if executionIDs.contains(team.id) {
                XCTAssertTrue(team.mutating, "\(team.id) is a source-scoped execution team")
                XCTAssertNotNil(team.executionSourceId)
            } else {
                XCTAssertFalse(team.mutating, "\(team.id) must be non-mutating advisory")
            }
        }
    }

    func testStaleBuildLanguageIsGoneFromPublicNames() {
        // Cutover hygiene: no public team display name still uses the old internal
        // "Build" lane prefix — except the founder-approved obvious-job names
        // "Build a Slice" and "What to Build Next" (Team_Catalog_Normalization.md, Law 1).
        let approvedBuildNames: Set<String> = ["build_slice", "signal_what_to_build_next"]
        for team in BuiltInTeams.all where !approvedBuildNames.contains(team.id) {
            XCTAssertFalse(team.displayName.contains("Build"), "\(team.id) display name still says Build")
        }
        XCTAssertEqual(BuiltInTeams.team("code_plan")?.displayName, "Plan")
    }

    func testSignalBuiltInsAreScoutNonMutatingInsightTeams() {
        // CRAFT-2: Signal is runnable on the same substrate — non-mutating,
        // insight output, on the signal craft.
        let signalTeams = BuiltInTeams.teams(in: .signal)
        XCTAssertEqual(Set(signalTeams.map(\.id)), ["signal_outside", "signal_what_to_build_next"])
        for team in signalTeams {
            XCTAssertEqual(team.lane, .signal)
            XCTAssertEqual(team.outputKind, .insight)
            XCTAssertFalse(team.mutating)
        }
        // Exactly one signal-lane default.
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .signal)?.id, "signal_outside")
    }

    func testSignalTeamsResolveAgainstSignalCapableModels() {
        // Signal skills are signal-lane, and signal-capable models exist so the teams
        // can actually resolve a worker.
        for team in BuiltInTeams.teams(in: .signal) {
            for row in team.agentSpecs {
                XCTAssertEqual(SkillCatalog.skill(row.skillId)?.lane, .signal,
                               "\(team.id) row \(row.skillId) must be a signal skill")
            }
            XCTAssertEqual(SkillCatalog.skill(team.lead.skillId)?.lane, .signal)
        }
        let signalModels = ModelCatalog.builtInCapabilities.filter { $0.value.laneTags.contains(.signal) }
        XCTAssertFalse(signalModels.isEmpty, "no signal-capable model exists")
    }
}
