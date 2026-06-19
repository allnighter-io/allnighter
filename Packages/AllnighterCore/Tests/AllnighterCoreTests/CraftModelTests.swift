import XCTest
@testable import AllnighterCore

/// CRAFT-1: the team/craft model gains Signal as the 4th craft plus team posture
/// and a mutating flag, on the SAME substrate (no second system). Existing teams
/// keep correct, non-mutating postures.
final class CraftModelTests: XCTestCase {
    func testSignalIsAFourthCraft() {
        XCTAssertEqual(WorkLane.allCases.count, 4)
        XCTAssertTrue(WorkLane.allCases.contains(.signal))
        XCTAssertEqual(WorkLane.signal.rawValue, "signal")
    }

    func testInsightOutputKindAndPostures() {
        XCTAssertTrue(TeamOutputKind.allCases.contains(.insight))
        XCTAssertEqual(Set(TeamPosture.allCases), [.scout, .propose, .review, .execute])
    }

    func testTeamPresetRoundTripsPostureAndMutating() throws {
        let team = TeamPreset(
            id: "signal_demo", displayName: "Demo", lane: .signal, outputKind: .insight,
            posture: .scout, mutating: false,
            workerSpecs: [TeamWorkerSpec(id: "r", skillId: "s")],
            lead: TeamLeadSpec(skillId: "w"), builtIn: true)
        let data = try CoreJSON.encode(team)
        let back = try CoreJSON.decode(TeamPreset.self, from: data)
        XCTAssertEqual(back.posture, .scout)
        XCTAssertEqual(back.mutating, false)
        XCTAssertEqual(back.lane, .signal)
        XCTAssertEqual(back.outputKind, .insight)
    }

    func testExistingBuiltInsHaveCorrectNonMutatingPostures() {
        // Drafting outputs propose; audit/diagnostic outputs review; advisory built-ins do not mutate.
        XCTAssertEqual(BuiltInTeams.team("code_core")?.posture, .propose)
        XCTAssertEqual(BuiltInTeams.team("design_core")?.posture, .propose)
        XCTAssertEqual(BuiltInTeams.team("copy_core")?.posture, .propose)
        XCTAssertEqual(BuiltInTeams.team("code_security_review")?.posture, .review)
        XCTAssertEqual(BuiltInTeams.team("code_bug_hunt")?.posture, .review)
        XCTAssertEqual(BuiltInTeams.team("code_release_proof")?.posture, .review)
        let executionIDs: Set<String> = [
            "code_codex_implementation", "code_claude_implementation", "code_cursor_implementation",
            "default_chat", "execution_playbook"
        ]
        for team in BuiltInTeams.all {
            if executionIDs.contains(team.id) {
                XCTAssertTrue(team.mutating, "\(team.id) is a source-scoped execution team")
                XCTAssertEqual(team.posture, .execute)
                XCTAssertNotNil(team.executionSourceId)
            } else {
                XCTAssertFalse(team.mutating, "\(team.id) must be non-mutating advisory")
            }
        }
    }

    func testStaleBuildLanguageIsGoneFromPublicNames() {
        // Cutover hygiene: no public team display name still says "Build".
        for team in BuiltInTeams.all {
            XCTAssertFalse(team.displayName.contains("Build"), "\(team.id) display name still says Build")
        }
        XCTAssertEqual(BuiltInTeams.team("code_core")?.displayName, "Code Core")
    }

    func testSignalBuiltInsAreScoutNonMutatingInsightTeams() {
        // CRAFT-2: Signal is runnable on the same substrate — scout posture,
        // non-mutating, insight output, on the signal craft.
        let signalTeams = BuiltInTeams.teams(in: .signal)
        XCTAssertEqual(Set(signalTeams.map(\.id)), ["signal_post_to_project", "signal_what_to_build_next"])
        for team in signalTeams {
            XCTAssertEqual(team.lane, .signal)
            XCTAssertEqual(team.posture, .scout)
            XCTAssertEqual(team.outputKind, .insight)
            XCTAssertFalse(team.mutating)
        }
        // Exactly one signal-lane default.
        XCTAssertEqual(BuiltInTeams.all.defaultTeam(for: .signal)?.id, "signal_post_to_project")
    }

    func testSignalTeamsResolveAgainstSignalCapableModels() {
        // Signal skills are signal-lane, and signal-capable models exist so the teams
        // can actually resolve a worker.
        for team in BuiltInTeams.teams(in: .signal) {
            for row in team.workerSpecs {
                XCTAssertEqual(SkillCatalog.skill(row.skillId)?.lane, .signal,
                               "\(team.id) row \(row.skillId) must be a signal skill")
            }
            XCTAssertEqual(SkillCatalog.skill(team.lead.skillId)?.lane, .signal)
        }
        let signalModels = ModelCatalog.builtInCapabilities.filter { $0.value.laneTags.contains(.signal) }
        XCTAssertFalse(signalModels.isEmpty, "no signal-capable model exists")
    }
}
