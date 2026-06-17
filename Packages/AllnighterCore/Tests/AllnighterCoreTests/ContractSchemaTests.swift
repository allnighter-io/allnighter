import XCTest
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
        let model = try XCTUnwrap(trj.models.first)
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
        // Public error codes use the new vocabulary, not council/panel/seat.
        for e in ContractRegistry.milestone1.errors {
            let blob = (e.code + e.ruleId + e.agentAction).lowercased()
            XCTAssertFalse(blob.contains("council") || blob.contains("panel") || blob.contains("masterplan"),
                           "error \(e.code) carries legacy vocabulary")
        }
    }
}
