import XCTest
@testable import AllnighterCore

/// PN-S02 finding-schema parse — happy / empty (no material findings) / unparseable.
/// Lineage of RelayVerdictParser (last-object + fence-on-own-line).
final class PanelFindingsParserTests: XCTestCase {

    func testHappyPathFencedFindings() throws {
        let report = """
        I found one hole in the scope section.

        ```json
        {
          "findings": [
            {
              "claim": "Scope is too wide",
              "severity": "high",
              "evidence": "section 3 lists six non-goals as goals",
              "proposedChange": "Cut v1 to transport only"
            }
          ],
          "noMaterialFindings": false
        }
        ```
        """
        let extraction = try unwrap(PanelFindingsParser.extract(from: report))
        XCTAssertEqual(extraction.findings.count, 1)
        XCTAssertEqual(extraction.findings[0].claim, "Scope is too wide")
        XCTAssertEqual(extraction.findings[0].severity, .high)
        XCTAssertEqual(extraction.findings[0].proposedChange, "Cut v1 to transport only")
        XCTAssertFalse(extraction.noMaterialFindings)
        XCTAssertTrue(extraction.strippedReport.contains("I found one hole"))
        XCTAssertFalse(extraction.strippedReport.contains("\"findings\""))
    }

    func testNoMaterialFindingsIsFirstClassValid() throws {
        let report = """
        Reviewed carefully — nothing material.

        ```json
        {"findings": [], "noMaterialFindings": true, "reason": "Target already states the v1 boundary clearly."}
        ```
        """
        let extraction = try unwrap(PanelFindingsParser.extract(from: report))
        XCTAssertEqual(extraction.findings, [])
        XCTAssertTrue(extraction.noMaterialFindings)
        XCTAssertEqual(extraction.reason, "Target already states the v1 boundary clearly.")

        let seat = PanelFindingsParser.seatResult(
            workerId: "model_opus", lens: "adversary", report: report, runId: "r1"
        )
        XCTAssertEqual(seat.status, .done)
        XCTAssertEqual(seat.findings, [])
        XCTAssertTrue(seat.noMaterialFindings)
        XCTAssertEqual(seat.report, report)
    }

    func testUnparseableKeepsVerbatimReportAndFlagsUnstructured() {
        let report = "Just prose. No JSON at all. Still useful for the session."
        let seat = PanelFindingsParser.seatResult(
            workerId: "model_opus", lens: "simplicity", report: report
        )
        XCTAssertEqual(seat.status, .done)
        XCTAssertNil(seat.findings, "unstructured → findings nil")
        XCTAssertFalse(seat.noMaterialFindings)
        XCTAssertEqual(seat.reason, "unstructured report (no parseable findings block)")
        XCTAssertEqual(seat.report, report, "never discard the report")
    }

    func testLastFindingsObjectWinsOverEarlierJSON() throws {
        let report = """
        Analysis first:

        ```json
        {"filesChanged": 3, "risk": "low"}
        ```

        Then the schema:

        ```json
        {"findings": [{"claim": "real", "severity": "low", "evidence": "e"}], "noMaterialFindings": false}
        ```
        """
        let extraction = try unwrap(PanelFindingsParser.extract(from: report))
        XCTAssertEqual(extraction.findings.first?.claim, "real")
    }

    func testEmbeddedFenceInsideStringDoesNotTerminateEarly() throws {
        // d96f332a lineage: a ```json mention inside a JSON string value must not
        // close the outer fence early (closing fence must be on its own line).
        let report = """
        ```json
        {"findings": [], "noMaterialFindings": true, "reason": "Do not re-litigate; see prior ```json example in brief."}
        ```
        """
        let extraction = try unwrap(PanelFindingsParser.extract(from: report))
        XCTAssertTrue(extraction.noMaterialFindings)
        XCTAssertTrue(extraction.reason?.contains("```json") == true)
    }

    func testInvalidSeverityIsInvalidShape() {
        let report = """
        ```json
        {"findings": [{"claim": "x", "severity": "critical", "evidence": "e"}], "noMaterialFindings": false}
        ```
        """
        switch PanelFindingsParser.extract(from: report) {
        case .success:
            XCTFail("critical is not a valid severity")
        case .failure(let err):
            if case .invalidShape = err { /* ok */ }
            else { XCTFail("expected invalidShape, got \(err)") }
        }
    }

    func testEmptyReportIsEmptyStatus() {
        let seat = PanelFindingsParser.seatResult(
            workerId: "w", lens: "l", report: "   \n  "
        )
        XCTAssertEqual(seat.status, .empty)
    }

    func testTerminalDispatchFailureKeepsActionableReason() {
        let seat = PanelFindingsParser.seatResult(
            workerId: "model_codex",
            lens: "contracts",
            report: "",
            runId: "run_1",
            dispatchStatus: .failed,
            dispatchReason: "app-server initialization failed: permission denied"
        )

        XCTAssertEqual(seat.status, .failed)
        XCTAssertEqual(
            seat.reason,
            "app-server initialization failed: permission denied"
        )
        XCTAssertEqual(seat.report, "")
    }

    // MARK: - PP-S01 unstructuredSeats envelope projection

    /// agy-style prose report (real content, no fenced block) surfaces at envelope top
    /// on both `PanelRoundLogEntry` and `PanelRoundJSON` — never buried only in seat reason.
    func testUnstructuredProseSurfacesInEnvelopeTop() throws {
        let prose = """
        The consent boundary is load-bearing; three seats already hit it independently.
        Schema JSON is in the artifact, not the report text.
        """
        let unstructured = PanelFindingsParser.seatResult(
            workerId: "model_agy_opus", lens: "adversary", report: prose
        )
        XCTAssertEqual(unstructured.status, .done)
        XCTAssertNil(unstructured.findings)
        XCTAssertFalse(prose.isEmpty, "content is real — just unstructured")

        let cleanReport = """
        Reviewed.

        ```json
        {"findings": [], "noMaterialFindings": true, "reason": "Target states the boundary clearly."}
        ```
        """
        let clean = PanelFindingsParser.seatResult(
            workerId: "model_sonnet", lens: "simplicity", report: cleanReport
        )
        XCTAssertEqual(clean.status, .done)
        XCTAssertNotNil(clean.findings)

        let round = PanelRound(
            roundNumber: 1,
            targetHash: "abc",
            brief: "pressure-test",
            briefSource: .builtin,
            seatResults: [unstructured, clean],
            startedAt: Date()
        )

        let log = PanelRoundLogEntry(round)
        XCTAssertEqual(log.unstructuredSeats, ["model_agy_opus"])

        let panel = PanelJSON.project(
            PanelState(
                id: "panel_pp_s01", projectRoot: "/repo", projectId: "proj",
                targetPath: "docs/spec.md", seats: [],
                status: .awaitingPM, rounds: [round], createdAt: Date()
            ),
            contractVersion: ContractRegistry.contractVersion
        )
        XCTAssertEqual(panel.roundLog.first?.unstructuredSeats, ["model_agy_opus"])

        let envelope = PanelRoundJSON(
            contractVersion: ContractRegistry.contractVersion,
            panel: panel,
            round: 1,
            attempt: 1,
            targetHash: "abc",
            briefSource: "builtin",
            seatResults: round.seatResults.map(SeatResultJSON.init),
            unstructuredSeats: PanelUnstructuredSeats.project(from: round.seatResults)
        )
        XCTAssertEqual(envelope.unstructuredSeats, ["model_agy_opus"])
    }

    /// Clean round keeps `unstructuredSeats` present as `[]` (not nil / not omitted).
    func testCleanRoundUnstructuredSeatsIsEmptyArray() throws {
        let cleanReport = """
        ```json
        {"findings": [{"claim": "ok", "severity": "low", "evidence": "e"}], "noMaterialFindings": false}
        ```
        """
        let clean = PanelFindingsParser.seatResult(
            workerId: "model_sonnet", lens: "simplicity", report: cleanReport
        )
        let round = PanelRound(
            roundNumber: 1,
            targetHash: "def",
            brief: "pressure-test",
            briefSource: .builtin,
            seatResults: [clean],
            startedAt: Date()
        )

        let log = PanelRoundLogEntry(round)
        XCTAssertEqual(log.unstructuredSeats, [])

        let encoded = try JSONEncoder().encode(log)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let seats = try XCTUnwrap(obj["unstructuredSeats"] as? [String])
        XCTAssertEqual(seats, [], "field must be present and empty, not nil/omitted")

        let envelope = PanelRoundJSON(
            contractVersion: ContractRegistry.contractVersion,
            panel: PanelJSON.project(
                PanelState(
                    id: "panel_clean", projectRoot: "/repo", projectId: "proj",
                    targetPath: "docs/spec.md", seats: [],
                    status: .awaitingPM, createdAt: Date()
                ),
                contractVersion: ContractRegistry.contractVersion
            ),
            round: 1,
            attempt: 1,
            targetHash: "def",
            briefSource: "builtin",
            seatResults: [SeatResultJSON(clean)],
            unstructuredSeats: PanelUnstructuredSeats.project(from: [clean])
        )
        XCTAssertEqual(envelope.unstructuredSeats, [])
        let envEncoded = try JSONEncoder().encode(envelope)
        let envObj = try XCTUnwrap(JSONSerialization.jsonObject(with: envEncoded) as? [String: Any])
        let envSeats = try XCTUnwrap(envObj["unstructuredSeats"] as? [String])
        XCTAssertEqual(envSeats, [])
    }

    private func unwrap<T>(_ result: Result<T, PanelFindingsParser.ExtractError>) throws -> T {
        switch result {
        case .success(let v): return v
        case .failure(let e): throw NSError(domain: "PanelFindings", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(e)"])
        }
    }
}
