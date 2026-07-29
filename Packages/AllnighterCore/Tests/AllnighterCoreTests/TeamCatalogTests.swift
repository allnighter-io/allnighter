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
            agentSpecs: [
                TeamAgentSpec(id: "row_a", skillId: "skill_a", purpose: .answer),
                TeamAgentSpec(id: "row_b", skillId: "skill_b", purpose: .answer),
                TeamAgentSpec(id: "row_c", skillId: "skill_c", purpose: .review,
                               preferredModelId: "model_opus",
                               fallbackModelIds: ["model_kimi_k3", "model_grok"],
                               fallbackPolicy: .anyReady, required: false)
            ],
            lead: TeamLeadSpec(
                skillId: "plan_writer_build",
                fallbackModelIds: ["model_chatgpt_sol", "model_opus"],
                dissentPolicy: .riskRegister),
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

    func testCatalogWrittenBeforeOrderedFallbacksStillDecodes() throws {
        let data = try CoreJSON.encode(sampleTeam())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(object["agentSpecs"] as? [[String: Any]])
        for index in rows.indices { rows[index].removeValue(forKey: "fallbackModelIds") }
        object["agentSpecs"] = rows
        var lead = try XCTUnwrap(object["lead"] as? [String: Any])
        lead.removeValue(forKey: "fallbackModelIds")
        object["lead"] = lead

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try CoreJSON.decode(TeamPreset.self, from: legacyData)
        XCTAssertTrue(decoded.agentSpecs.allSatisfy { $0.fallbackModelIds == nil })
        XCTAssertNil(decoded.lead.fallbackModelIds)
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
            sampleTeam(id: "code_plan", lane: .code, isDefault: true),
            sampleTeam(id: "code_bug_hunt", lane: .code, isDefault: false),
            sampleTeam(id: "design_design", lane: .design, isDefault: true)
        ]
        XCTAssertTrue(teams.lanesViolatingSingleDefault().isEmpty)
        XCTAssertEqual(teams.defaultTeam(for: .code)?.id, "code_plan")
        XCTAssertEqual(teams.defaultTeam(for: .design)?.id, "design_design")
        XCTAssertNil(teams.defaultTeam(for: .copy))
    }

    func testZeroOrMultipleDefaultsViolate() {
        let twoDefaults = [
            sampleTeam(id: "code_plan", lane: .code, isDefault: true),
            sampleTeam(id: "code_bug_hunt", lane: .code, isDefault: true)
        ]
        XCTAssertEqual(twoDefaults.lanesViolatingSingleDefault(), [.code])

        let noDefault = [sampleTeam(id: "design_design", lane: .design, isDefault: false)]
        XCTAssertEqual(noDefault.lanesViolatingSingleDefault(), [.design])
        // Falls back to the <lane>_core built-in when no explicit default is set.
        XCTAssertEqual(noDefault.defaultTeam(for: .design)?.id, "design_design")
    }

    // MARK: - ADP-S03: every catalog row discloses a non-empty name

    /// Reproduces the caller-reported mechanism: `teams duplicate --name ""`
    /// (an explicit blank, not an omitted flag) saves a custom team whose
    /// `displayName` is a literal empty string. `disclosedDisplayName` — used
    /// by every catalog/menu projection — must still surface a non-empty
    /// human name (falling back to the canonical id) rather than leaking "".
    func testBlankDisplayNameFallsBackToIdForDisclosure() {
        var team = sampleTeam(id: "custom_code_blank")
        team.displayName = ""
        XCTAssertEqual(team.disclosedDisplayName, "custom_code_blank")

        var whitespaceOnly = sampleTeam(id: "custom_code_ws")
        whitespaceOnly.displayName = "   "
        XCTAssertEqual(whitespaceOnly.disclosedDisplayName, "custom_code_ws")

        // Non-empty names are passed through untouched.
        XCTAssertEqual(sampleTeam(id: "custom_code_named").disclosedDisplayName, "Sample")
    }

    /// `teams --json` (`TeamCatalogJSON.project`) never emits an empty
    /// `displayName` for any row — built-in or a duplicate saved with a
    /// blank `--name`.
    func testTeamCatalogJSONNeverEmitsEmptyDisplayName() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let teamsRoot = base.appendingPathComponent("teams", isDirectory: true)
        let skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
        defer {
            CatalogRoots.resetTestingOverrides()
            try? FileManager.default.removeItem(at: base)
        }

        _ = try TeamCatalog.duplicateBuiltIn(
            "code_bug_hunt", name: "", customId: "custom_code_blank_dup")

        let payload = TeamCatalogJSON.project(
            TeamCatalog.all, lane: nil, contractVersion: ContractRegistry.contractVersion)
        XCTAssertFalse(payload.teams.isEmpty)
        for entry in payload.teams {
            XCTAssertFalse(
                entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "team \(entry.id) discloses an empty displayName"
            )
        }
        let blank = try XCTUnwrap(payload.teams.first { $0.id == "custom_code_blank_dup" })
        XCTAssertEqual(blank.displayName, "custom_code_blank_dup")
    }
}
