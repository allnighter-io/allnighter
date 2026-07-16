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

    private func unwrap<T>(_ result: Result<T, PanelFindingsParser.ExtractError>) throws -> T {
        switch result {
        case .success(let v): return v
        case .failure(let e): throw NSError(domain: "PanelFindings", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(e)"])
        }
    }
}
