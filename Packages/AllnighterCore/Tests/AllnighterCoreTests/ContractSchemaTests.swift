import XCTest
import AgentOSTeam
@testable import AllnighterCore

/// Drift proof for the generated JSON Schemas and the markdown reference: the
/// schema property sets are tied back to the actual Swift types via `Mirror`, so
/// adding or removing a field on `TeamRunJSON`/`DoctorResult` fails the wall
/// until the schema (and its regenerated artifact) is updated.
final class ContractSchemaTests: XCTestCase {

    private func properties(_ schema: [String: Any]) throws -> Set<String> {
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        return Set(props.keys)
    }
    private func def(_ schema: [String: Any], _ name: String) throws -> [String: Any] {
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        return try XCTUnwrap(defs[name] as? [String: Any])
    }
    private func labels(_ value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    func testTeamRunSchemaMatchesType() throws {
        let trj = try Fixtures.decode(TeamRunJSON.self, .teamRunJSON)
        let schema = ContractSchema.teamRunSchema()
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertNotNil(schema["$schema"])

        XCTAssertEqual(try properties(schema), labels(trj), "TeamRunJSON top-level schema drifted from the type")
        XCTAssertEqual(try properties(def(schema, "RunInfo")), labels(trj.teamRun), "RunInfo schema drifted")
        let answer = try XCTUnwrap(trj.answer)
        XCTAssertEqual(try properties(def(schema, "Answer")), labels(answer), "Answer schema drifted")
        XCTAssertEqual(try properties(def(schema, "AnswerSource")), labels(answer.source), "AnswerSource schema drifted")
        // ModelInfo remains a nested type for DoctorResult; keep $defs parity via a constructed value.
        let model = TeamRunJSON.ModelInfo(id: "m", displayName: "M", sourceId: "s", status: .ready)
        XCTAssertEqual(try properties(def(schema, "ModelInfo")), labels(model), "ModelInfo schema drifted")
    }

    func testDoctorResultSchemaMatchesType() throws {
        let doc = try Fixtures.decode(DoctorResult.self, .doctorResult)
        let schema = ContractSchema.doctorResultSchema()
        XCTAssertEqual(try properties(schema), labels(doc), "DoctorResult top-level schema drifted from the type")
        let check = try XCTUnwrap(doc.checks.first)
        XCTAssertEqual(try properties(def(schema, "Check")), labels(check), "Check schema drifted")
        XCTAssertEqual(try properties(def(schema, "Coordinator")), labels(doc.coordinator), "Coordinator schema drifted")
    }

    func testPendingItemSchemaMatchesType() throws {
        let pending = try Fixtures.pendingItemJSON()
        let schema = ContractSchema.pendingItemSchema()
        XCTAssertEqual(try properties(schema), labels(pending), "PendingItemJSON top-level schema drifted from the type")
    }

    func testFloorRunSchemaMatchesType() throws {
        // Project a representative run so the schema is tied back to the real types.
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let run = TeamRun(
            id: "r1", prompt: "p", status: .complete, origin: .cli, presetId: "signal_outside",
            workers: [Agent(id: "w#0", modelId: "m", instanceIndex: 0, purpose: .plan)],
            workerAnswers: [TeamAnswer(memberId: "w#0", modelId: "m", role: "plan",
                                       result: WorkerRunResult(status: .done, output: "x", timing: RunTiming(finishedAt: now)))],
            stages: [StageOutput(id: "s1", purpose: .plan, status: .done, payload: .plan(markdown: "md"))],
            createdAt: now, lane: .signal, outputKind: .insight)
        let floor = FloorProjector.project(run)
        let schema = ContractSchema.floorRunSchema()

        XCTAssertEqual(try properties(schema), labels(floor), "FloorRun top-level schema drifted from the type")
        XCTAssertEqual(try properties(def(schema, "FloorRunInfo")), labels(floor.run), "FloorRunInfo schema drifted")
        XCTAssertEqual(try properties(def(schema, "FloorTeam")), labels(floor.team), "FloorTeam schema drifted")
        let lane = try XCTUnwrap(floor.workerLanes.first)
        XCTAssertEqual(try properties(def(schema, "FloorWorkerLane")), labels(lane), "FloorWorkerLane schema drifted")
        let ret = try XCTUnwrap(floor.floorReturn)
        XCTAssertEqual(try properties(def(schema, "FloorReturn")), labels(ret), "FloorReturn schema drifted")
        let artifact = try XCTUnwrap(floor.artifacts.first)
        XCTAssertEqual(try properties(def(schema, "RunArtifactRef")), labels(artifact), "RunArtifactRef schema drifted")
    }

    func testSpecResultSchemaMatchesType() throws {
        let result = SpecRetrieval.Result(
            runId: "r", status: "done", lane: "signal", teamPresetId: "t", outputKind: "insight",
            selector: "latest", detail: "summary", summary: "s", full: nil, warnings: [],
            failedWorkers: [SpecRetrieval.FailedWorker(workerId: "w", skillName: "Sk", reason: "x")],
            artifactRefs: [])
        let schema = ContractSchema.specResultSchema()
        XCTAssertEqual(try properties(schema), labels(result), "SpecResult top-level schema drifted from the type")
        let failed = try XCTUnwrap(result.failedWorkers.first)
        XCTAssertEqual(try properties(def(schema, "FailedWorker")), labels(failed), "FailedWorker schema drifted")
    }

    func testCatalogSchemasMatchTypes() throws {
        let team = TeamCatalogJSON.project(BuiltInTeams.teams(in: .signal), lane: .signal,
                                           contractVersion: ContractRegistry.contractVersion)
        let teamSchema = ContractSchema.teamCatalogSchema()
        XCTAssertEqual(try properties(teamSchema), labels(team), "TeamCatalogJSON top-level schema drifted")
        XCTAssertEqual(try properties(def(teamSchema, "TeamCatalogEntry")), labels(try XCTUnwrap(team.teams.first)), "TeamCatalogEntry schema drifted")

        let emptyTeam = TeamCatalogJSON.project([], lane: nil, contractVersion: ContractRegistry.contractVersion)
        XCTAssertEqual(try properties(teamSchema), labels(emptyTeam), "TeamCatalogJSON counsel fields drifted")

        let model = ModelListProjector.build(
            registry: DriverRegistry([]),
            definitions: ModelCatalog.list(),
            probeRecords: [],
            diagnostics: [])
        let modelSchema = ContractSchema.modelListSchema()
        XCTAssertEqual(try properties(modelSchema), labels(model), "ModelListJSON top-level schema drifted")

        let version = VersionJSON(binaryVersion: "0.1.0")
        XCTAssertEqual(try properties(ContractSchema.versionSchema()), labels(version), "VersionJSON schema drifted")

        let skill = SkillCatalogJSON.project(SkillCatalog.list(lane: .signal), lane: .signal,
                                             contractVersion: ContractRegistry.contractVersion)
        let skillSchema = ContractSchema.skillCatalogSchema()
        XCTAssertEqual(try properties(skillSchema), labels(skill), "SkillCatalogJSON top-level schema drifted")
        XCTAssertEqual(try properties(def(skillSchema, "SkillCatalogEntry")), labels(try XCTUnwrap(skill.skills.first)), "SkillCatalogEntry schema drifted")
    }

    func testRetrievalSchemasMatchTypes() throws {
        let history = HistoryJSON(contractVersion: "1.0.0", query: "q",
                                  results: [RecallResult(runId: "r", prompt: "p", createdAt: Date(timeIntervalSince1970: 1), planExcerpt: "e")])
        let hSchema = ContractSchema.historySchema()
        XCTAssertEqual(try properties(hSchema), labels(history), "HistoryJSON top-level schema drifted")
        XCTAssertEqual(try properties(def(hSchema, "RecallResult")), labels(try XCTUnwrap(history.results.first)), "RecallResult schema drifted")

        let status = ThreadStatusResponse(threadId: "t", isRunning: true, needsAttention: false)
        XCTAssertEqual(try properties(ContractSchema.threadStatusSchema()), labels(status), "ThreadStatusResponse schema drifted")
    }

    func testOwnershipGarbageCollectionSchemaMatchesType() throws {
        let row = OwnershipGarbageCollectionRecordJSON(
            id: "run-1",
            kind: "run",
            createdAt: Date(timeIntervalSince1970: 1),
            status: "complete"
        )
        let result = OwnershipGarbageCollectionJSON(retentionCount: 100, pruned: [row])
        let schema = ContractSchema.ownershipGarbageCollectionSchema()

        XCTAssertEqual(try properties(schema), labels(result), "ownership GC schema drifted")
        XCTAssertEqual(
            try properties(def(schema, "GarbageCollectionRecord")),
            labels(row),
            "ownership GC record schema drifted"
        )
    }

    func testSchemasSerializeDeterministically() throws {
        XCTAssertEqual(try ContractSchema.json(ContractSchema.teamRunSchema()),
                       try ContractSchema.json(ContractSchema.teamRunSchema()))
    }

    func testMarkdownDocsCoverTheRegistry() {
        let md = ContractDocs.markdown()
        let reg = ContractRegistry.milestone1
        XCTAssertTrue(md.contains("# alln — Agent-Facing CLI Reference"))
        for c in reg.commands where c.milestone == .m1 {
            XCTAssertTrue(md.contains("`alln \(c.name)`"), "docs missing command \(c.name)")
        }
        for e in reg.errors {
            XCTAssertTrue(md.contains("`\(e.code)`"), "docs missing error \(e.code)")
        }
        // No estimate language leaks into the generated reference.
        XCTAssertFalse(md.lowercased().contains("estimated cost"))
        // SH-S10 teaching sections.
        XCTAssertTrue(md.contains("## Run stream mode (`--stream`)"))
        XCTAssertTrue(md.contains("## Model controls (vendor CLI boundary)"))
        XCTAssertTrue(md.contains("`--effort <low|med|high>`"))
    }

    /// CLI M1 step 8: the public contract (generated docs + registry) must teach
    /// only the new grammar — no legacy RB6/council vocabulary.
    func testNoLegacyPublicGrammar() {
        let md = ContractDocs.markdown().lowercased()
        for legacy in ["masterplan", "council", "panelseat", "alln ask", "alln presets", "alln recall", "team teams", "skillversion"] {
            XCTAssertFalse(md.contains(legacy), "generated docs still teach legacy grammar: \(legacy)")
        }
        let names = Set(ContractRegistry.milestone1.commands.map(\.name))
        for legacy in ["ask", "presets", "recall", "team teams", "team edit"] {
            XCTAssertFalse(names.contains(legacy), "registry still has legacy command: \(legacy)")
        }
        // Public error codes use the new vocabulary, not council/masterplan — and
        // no `panel` at all: `alln panel` was deleted outright, so the exemption
        // that used to carve out `PANEL_*` codes is gone with them.
        for e in ContractRegistry.milestone1.errors {
            let blob = (e.code + e.ruleId + e.agentAction).lowercased()
            XCTAssertFalse(blob.contains("council") || blob.contains("masterplan"),
                           "error \(e.code) carries legacy vocabulary")
            XCTAssertFalse(blob.contains("panel"),
                           "error \(e.code) carries legacy vocabulary")
        }
    }
}
