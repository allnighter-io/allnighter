import XCTest
@testable import AllnighterCore
@testable import AllnighterCLI

final class CatalogCLITests: XCTestCase {

    private var teamsRoot: URL!
    private var skillsRoot: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        teamsRoot = base.appendingPathComponent("teams", isDirectory: true)
        skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        CatalogRoots.overrideForTesting(teams: teamsRoot, skills: skillsRoot)
    }

    override func tearDown() {
        CatalogRoots.resetTestingOverrides()
        try? FileManager.default.removeItem(at: teamsRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testSkillsCodeJSONListsOnlyCodeLane() throws {
        let json = AllnighterCLI.skillsCatalogJSONString(lane: .code)
        let data = try XCTUnwrap(json.data(using: .utf8))
        struct Catalog: Decodable {
            struct Skill: Decodable { let id: String; let lane: String }
            let lane: String?
            let skills: [Skill]
        }
        let catalog = try CoreJSON.decode(Catalog.self, from: data)
        XCTAssertEqual(catalog.lane, "code")
        XCTAssertFalse(catalog.skills.isEmpty)
        XCTAssertTrue(catalog.skills.allSatisfy { $0.lane == "code" })
    }

    func testSkillShowJSONIncludesTemplate() throws {
        let json = AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get("bug_reproducer")))
        XCTAssertTrue(json.contains("smallest reproducible"))
    }

    func testSkillsDuplicateAndEditRoundTrip() throws {
        let skill = try SkillCatalog.duplicateBuiltIn("contrarian_reviewer", name: "WT Code Contrarian")
        var edited = skill
        edited.template = "WT Code Contrarian: challenge assumptions."
        try SkillCatalog.saveCustom(edited)
        let json = AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get(skill.id)))
        XCTAssertTrue(json.contains("WT Code Contrarian"))
    }

    func testSkillsGCPurgesLabSkillsFromCatalogList() throws {
        let labSkill = Skill(
            id: "custom_code_lab_gc_runner", displayName: "Lab GC Runner", lane: .code,
            purpose: .answer, template: "lab", builtIn: false
        )
        try CatalogFileIO.save(labSkill, id: labSkill.id, kind: .skill, root: CatalogRoots.skills)

        let deleted = try SkillCatalog.purgeUnreferencedCustomSkills()

        XCTAssertTrue(deleted.contains(labSkill.id))
        XCTAssertFalse(SkillCatalog.list(lane: .code).contains { $0.id == labSkill.id })
    }

    func testSkillsEditBuiltInRoundTripAndRestoreJSON() throws {
        var skill = try XCTUnwrap(SkillCatalog.get("bug_reproducer"))
        skill.template = "WSS_CLI_SENTINEL: shared override."
        try SkillCatalog.saveEffective(skill)
        let detail = try CoreJSON.decode(
            SkillDetailJSON.self,
            from: Data(AllnighterCLI.skillShowJSONString(try XCTUnwrap(SkillCatalog.get("bug_reproducer"))).utf8)
        )
        XCTAssertEqual(detail.origin, "override")
        XCTAssertTrue(detail.template.contains("WSS_CLI_SENTINEL"))

        let r1 = try SkillCatalog.restore("bug_reproducer")
        XCTAssertTrue(r1.removedOverride)
        let restore1 = SkillRestoreJSON(
            contractVersion: ContractRegistry.contractVersion,
            id: "bug_reproducer", restored: true, origin: "seed"
        )
        let ack = try CoreJSON.decode(
            SkillRestoreJSON.self, from: Data(AllnighterCLI.jsonString(restore1).utf8)
        )
        XCTAssertTrue(ack.restored)

        let r2 = try SkillCatalog.restore("bug_reproducer")
        XCTAssertFalse(r2.removedOverride)
    }

    func testSkillsRestoreUnsupportedForCustom() throws {
        let custom = try SkillCatalog.duplicateBuiltIn("bug_reproducer", name: "Only Custom")
        XCTAssertThrowsError(try SkillCatalog.restore(custom.id)) { error in
            XCTAssertEqual(error as? CatalogError, .restoreUnsupported)
        }
    }

    func testSkillsCatalogListJSONIncludesOriginFields() throws {
        let catalog = try CoreJSON.decode(
            SkillCatalogJSON.self,
            from: Data(AllnighterCLI.skillsCatalogJSONString(lane: .code).utf8)
        )
        XCTAssertEqual(catalog.schemaVersion, 2)
        XCTAssertFalse(catalog.skills.isEmpty)
        XCTAssertNotNil(catalog.skills.first?.origin)
        XCTAssertNotNil(catalog.skills.first?.seedId as String??)
    }

    func testTeamsDuplicateProducesEditablePresetJSON() throws {
        let team = try TeamCatalog.duplicateBuiltIn("code_plan", name: "WT Code Team")
        let json = AllnighterCLI.teamDefinitionJSONString(team)
        XCTAssertTrue(json.contains(team.id))
        XCTAssertTrue(json.contains("WT Code Team"))
        XCTAssertTrue(json.contains("\"agentSpecs\""))
        XCTAssertTrue(json.contains("\"lead\""))
        XCTAssertFalse(json.contains("\"seatCount\""), "authoring receipt is TeamPreset, not show projection")
        XCTAssertFalse(json.contains("\"crew\""), "authoring receipt is TeamPreset, not show projection")
        XCTAssertFalse(json.contains("\"workerCount\""), "public workerCount retired")
        let decoded = try CoreJSON.decode(TeamPreset.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, team.id)
        XCTAssertEqual(decoded.displayName, "WT Code Team")
    }

    func testTeamsNewAndDuplicateShareEditablePresetJSONShape() throws {
        let seed = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let novel = seed.duplicated(newId: "custom_code_cli_novel", newName: "CLI Novel")
        let created = try TeamCatalog.createNew(novel)
        let duplicated = try TeamCatalog.duplicateBuiltIn(
            "code_bug_hunt", name: "CLI Dup", customId: "custom_code_cli_dup")

        let createdJSON = AllnighterCLI.teamDefinitionJSONString(created)
        let duplicatedJSON = AllnighterCLI.teamDefinitionJSONString(duplicated)
        let definitionJSON = AllnighterCLI.teamDefinitionJSONString(
            try XCTUnwrap(TeamCatalog.get(created.id)))
        for json in [createdJSON, duplicatedJSON, definitionJSON] {
            XCTAssertTrue(json.contains("\"agentSpecs\""))
            XCTAssertTrue(json.contains("\"lead\""))
            XCTAssertFalse(json.contains("\"seatCount\""))
            XCTAssertFalse(json.contains("\"crew\""))
            XCTAssertFalse(json.contains("\"origin\""), "origin lives on show projection only")
        }
        XCTAssertTrue(createdJSON.contains("custom_code_cli_novel"))
        XCTAssertTrue(duplicatedJSON.contains("custom_code_cli_dup"))
    }

    /// MCV-S03 gate: authoring receipts round-trip through `teams edit` unmodified;
    /// show projection is refused by name; set-default stays on the show side.
    func testTeamsAuthoringReceiptsRoundTripThroughEdit() throws {
        let dir = teamsRoot.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let duplicated = try TeamCatalog.duplicateBuiltIn(
            "code_bug_hunt", name: "RT Dup", customId: "custom_code_rt_dup")
        let dupJSON = AllnighterCLI.teamDefinitionJSONString(duplicated)
        let dupURL = dir.appendingPathComponent("dup.json")
        try Data(dupJSON.utf8).write(to: dupURL)
        let fromDup = try AllnighterCLI.loadTeamDefinition(
            from: dupURL.path, expectedId: duplicated.id, verb: "edit")
        XCTAssertEqual(fromDup.id, duplicated.id)
        XCTAssertEqual(fromDup.agentSpecs.count, duplicated.agentSpecs.count)

        let seed = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let novel = seed.duplicated(newId: "custom_code_rt_new", newName: "RT New")
        let created = try TeamCatalog.createNew(novel)
        let newJSON = AllnighterCLI.teamDefinitionJSONString(created)
        let newURL = dir.appendingPathComponent("new.json")
        try Data(newJSON.utf8).write(to: newURL)
        let fromNew = try AllnighterCLI.loadTeamDefinition(
            from: newURL.path, expectedId: created.id, verb: "edit")
        XCTAssertEqual(fromNew.id, created.id)

        var edited = fromDup
        edited.displayName = "RT Dup (edited)"
        try TeamCatalog.saveCustom(edited)
        let editJSON = AllnighterCLI.teamDefinitionJSONString(
            try XCTUnwrap(TeamCatalog.get(edited.id)))
        let editURL = dir.appendingPathComponent("edit.json")
        try Data(editJSON.utf8).write(to: editURL)
        let fromEdit = try AllnighterCLI.loadTeamDefinition(
            from: editURL.path, expectedId: edited.id, verb: "edit")
        XCTAssertEqual(fromEdit.displayName, "RT Dup (edited)")
        try TeamCatalog.saveCustom(fromEdit) // idempotent edit ← edit
        XCTAssertEqual(TeamCatalog.get(edited.id)?.displayName, "RT Dup (edited)")

        let showJSON = AllnighterCLI.teamShowJSONString(edited)
        let showURL = dir.appendingPathComponent("show.json")
        try Data(showJSON.utf8).write(to: showURL)
        XCTAssertThrowsError(
            try AllnighterCLI.loadTeamDefinition(
                from: showURL.path, expectedId: edited.id, verb: "edit")
        ) { error in
            guard case CatalogError.teamInvalid(let detail) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(detail.contains("TeamPreset"), detail)
            XCTAssertTrue(detail.contains("show"), detail.lowercased())
        }

        let setDefaultJSON = AllnighterCLI.teamShowJSONString(
            try XCTUnwrap(TeamCatalog.get("default_chat")))
        XCTAssertTrue(setDefaultJSON.contains("\"seatCount\""))
        XCTAssertTrue(setDefaultJSON.contains("\"crew\""))
        XCTAssertFalse(setDefaultJSON.contains("\"agentSpecs\""))
    }

    func testTeamsNewFileIdMismatch() throws {
        let seed = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let fileTeam = seed.duplicated(newId: "custom_code_file_id", newName: "File Id")
        let url = teamsRoot.deletingLastPathComponent().appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(
            at: teamsRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CoreJSON.encode(fileTeam).write(to: url)

        XCTAssertThrowsError(
            try AllnighterCLI.loadTeamDefinition(
                from: url.path, expectedId: "custom_code_positional", verb: "new")
        ) { error in
            guard case CatalogError.teamInvalid(let detail) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(detail.contains("does not match"), detail)
            let envelope = AllnighterCLI.catalogErrorEnvelope(.teamInvalid(detail))
            XCTAssertEqual(envelope.code, "TEAM_INVALID")
        }
    }

    /// A team definition JSON missing the required `lead` key must surface as
    /// `TEAM_INVALID` naming the missing field — not `INTERNAL_ERROR` with raw
    /// `DecodingError` internals (agents were told to "retry once", which loops
    /// forever on a file that will never parse differently).
    func testTeamsNewMissingLeadFieldIsTeamInvalid() throws {
        let seed = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let team = seed.duplicated(newId: "custom_code_missing_lead", newName: "Missing Lead")
        let data = try CoreJSON.encode(team)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "lead")
        let mutated = try JSONSerialization.data(withJSONObject: obj)

        let dir = teamsRoot.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("missing-lead.json")
        try mutated.write(to: url)

        XCTAssertThrowsError(
            try AllnighterCLI.loadTeamDefinition(from: url.path, expectedId: team.id, verb: "new")
        ) { error in
            guard case CatalogError.teamInvalid(let detail) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(detail.contains("lead"), detail)
            XCTAssertFalse(detail.contains("keyNotFound"), "raw DecodingError internals must not leak: \(detail)")
            XCTAssertFalse(detail.contains("CodingKeys"), "raw DecodingError internals must not leak: \(detail)")
            let envelope = AllnighterCLI.catalogErrorEnvelope(.teamInvalid(detail))
            XCTAssertEqual(envelope.code, "TEAM_INVALID")
        }
    }

    /// A team definition JSON with a `null` `agentSpecs[0].skillId` must surface
    /// as `TEAM_INVALID` naming the exact field path — not `INTERNAL_ERROR` with
    /// raw `DecodingError` internals.
    func testTeamsNewNullWorkerSkillIdIsTeamInvalid() throws {
        let seed = try XCTUnwrap(BuiltInTeams.team("code_bug_hunt"))
        let team = seed.duplicated(newId: "custom_code_null_skill", newName: "Null Skill")
        XCTAssertFalse(team.agentSpecs.isEmpty, "fixture must have at least one worker row to null out")
        let data = try CoreJSON.encode(team)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var agentSpecs = try XCTUnwrap(obj["agentSpecs"] as? [[String: Any]])
        agentSpecs[0]["skillId"] = NSNull()
        obj["agentSpecs"] = agentSpecs
        let mutated = try JSONSerialization.data(withJSONObject: obj)

        let dir = teamsRoot.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("null-skill.json")
        try mutated.write(to: url)

        XCTAssertThrowsError(
            try AllnighterCLI.loadTeamDefinition(from: url.path, expectedId: team.id, verb: "new")
        ) { error in
            guard case CatalogError.teamInvalid(let detail) = error else {
                return XCTFail("expected teamInvalid, got \(error)")
            }
            XCTAssertTrue(detail.contains("agentSpecs[0].skillId"), detail)
            XCTAssertFalse(detail.contains("valueNotFound"), "raw DecodingError internals must not leak: \(detail)")
            XCTAssertFalse(detail.contains("codingPath"), "raw DecodingError internals must not leak: \(detail)")
            let envelope = AllnighterCLI.catalogErrorEnvelope(.teamInvalid(detail))
            XCTAssertEqual(envelope.code, "TEAM_INVALID")
        }
    }

    func testSkillsNewCreatesCustomSkill() throws {
        let skill = try SkillCatalog.createCustom(
            lane: .code, name: "Fresh Skill", purpose: .answer, template: "Be precise."
        )
        XCTAssertFalse(skill.builtIn)
        XCTAssertTrue(skill.id.hasPrefix("custom_code_"))
    }
}
