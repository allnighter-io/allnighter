import XCTest
@testable import AllnighterCore

final class TeamCatalogTests: XCTestCase {

    private func sampleTeam(id: String = "code_sample", lane: WorkLane = .code, isDefault: Bool = false) -> TeamPreset {
        TeamPreset(
            id: id,
            displayName: "Sample",
            lane: lane,
            description: "A sample team.",
            outputKind: .plan,
            defaultEffort: .med,
            isDefaultForLane: isDefault,
            workerSpecs: [
                TeamWorkerSpec(id: "row_a", skillId: "skill_a", purpose: .answer),
                TeamWorkerSpec(id: "row_b", skillId: "skill_b", purpose: .answer),
                TeamWorkerSpec(id: "row_c", skillId: "skill_c", purpose: .review,
                               preferredModelId: "model_opus", fallbackPolicy: .anyReady, required: false)
            ],
            lead: TeamLeadSpec(skillId: "plan_writer_build", dissentPolicy: .riskRegister),
            typeTags: ["feature"],
            builtIn: true
        )
    }

    // MARK: - Codable round-trip (enum-keyed dictionaries are the risk)

    func testTeamPresetRoundTrips() throws {
        let team = sampleTeam()
        let data = try CoreJSON.encode(team)
        let decoded = try CoreJSON.decode(TeamPreset.self, from: data)
        XCTAssertEqual(decoded, team)
        XCTAssertEqual(decoded.lead.dissentPolicy, .riskRegister)
        XCTAssertEqual(decoded.lead.skillId, "plan_writer_build")
    }

    func testCanonicalEffortRawValues() throws {
        XCTAssertEqual(EffortLevel.allCases.map(\.rawValue), ["low", "med", "high"])
        // Hard cutover: no quick/standard/deep/medium anywhere in the contract.
        XCTAssertNil(EffortLevel(rawValue: "medium"))
        XCTAssertNil(EffortLevel(rawValue: "standard"))
    }

    func testLeadIsEffortIndependent() {
        // One Team Lead per team — effort scales the crew, never the Lead.
        let team = sampleTeam()
        XCTAssertEqual(team.lead.skillId, "plan_writer_build")
        XCTAssertEqual(team.lead.dissentPolicy, .riskRegister)
    }

    // MARK: - Default-per-lane integrity

    func testExactlyOneDefaultPerLaneIsValid() {
        let teams = [
            sampleTeam(id: "code_core", lane: .code, isDefault: true),
            sampleTeam(id: "code_bug_hunt", lane: .code, isDefault: false),
            sampleTeam(id: "design_core", lane: .design, isDefault: true)
        ]
        XCTAssertTrue(teams.lanesViolatingSingleDefault().isEmpty)
        XCTAssertEqual(teams.defaultTeam(for: .code)?.id, "code_core")
        XCTAssertEqual(teams.defaultTeam(for: .design)?.id, "design_core")
        XCTAssertNil(teams.defaultTeam(for: .copy))
    }

    func testZeroOrMultipleDefaultsViolate() {
        let twoDefaults = [
            sampleTeam(id: "code_core", lane: .code, isDefault: true),
            sampleTeam(id: "code_bug_hunt", lane: .code, isDefault: true)
        ]
        XCTAssertEqual(twoDefaults.lanesViolatingSingleDefault(), [.code])

        let noDefault = [sampleTeam(id: "design_core", lane: .design, isDefault: false)]
        XCTAssertEqual(noDefault.lanesViolatingSingleDefault(), [.design])
        // Falls back to the <lane>_core built-in when no explicit default is set.
        XCTAssertEqual(noDefault.defaultTeam(for: .design)?.id, "design_core")
    }
}
