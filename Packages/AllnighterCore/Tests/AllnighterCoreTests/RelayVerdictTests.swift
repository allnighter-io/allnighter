import XCTest
@testable import AllnighterCore

/// The PM's turn ends with one small `RelayVerdict` JSON tail; everything else is prose
/// (docs/phases/PM_Relay.md §4). These tests cover the three verdicts, fenced/bare tails,
/// the tail-not-last-JSON case, the continue-without-handover re-ask trigger, and that
/// `strippedOutput` is exactly the prose a founder would have pasted.
final class RelayVerdictTests: XCTestCase {

    // MARK: - Happy paths

    func testContinueFencedJSON() throws {
        let output = """
        Reviewed the diff — looks solid, one gap left.

        ```json
        {"verdict": "continue", "handover": "Add a test for the empty-list case."}
        ```
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertEqual(extraction.verdict.verdict, .continueRelay)
        XCTAssertEqual(extraction.verdict.handover, "Add a test for the empty-list case.")
        XCTAssertNil(extraction.verdict.note)
        XCTAssertEqual(extraction.strippedOutput, "Reviewed the diff — looks solid, one gap left.")
    }

    func testDoneBareJSON() throws {
        let output = """
        All three items from last round are done, verified against the actual commits.

        {"verdict": "done", "note": "Doc fully delivered, tests green."}
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertEqual(extraction.verdict.verdict, .done)
        XCTAssertEqual(extraction.verdict.note, "Doc fully delivered, tests green.")
        XCTAssertNil(extraction.verdict.handover)
        XCTAssertEqual(
            extraction.strippedOutput,
            "All three items from last round are done, verified against the actual commits."
        )
    }

    func testEscalateFencedJSON() throws {
        let output = """
        Two valid designs for the settings screen — I can't pick without you.

        ```json
        {"verdict": "escalate", "note": "76/77 or 88 — say which."}
        ```
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertEqual(extraction.verdict.verdict, .escalate)
        XCTAssertEqual(extraction.verdict.note, "76/77 or 88 — say which.")
    }

    // MARK: - Tail selection (verdict is not the only/first JSON object)

    func testVerdictNotLastJSONObjectStillWins() throws {
        let output = """
        Filed the analysis first.

        ```json
        {"filesChanged": 3, "risk": "low"}
        ```

        Then the actual call:

        ```json
        {"verdict": "continue", "handover": "Proceed with slice 2."}
        ```
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertEqual(extraction.verdict.verdict, .continueRelay)
        XCTAssertEqual(extraction.verdict.handover, "Proceed with slice 2.")
        // The earlier analysis block is prose to the dev too — only the verdict tail is stripped.
        XCTAssertTrue(extraction.strippedOutput.contains("\"filesChanged\": 3"))
        XCTAssertFalse(extraction.strippedOutput.contains("\"verdict\""))
    }

    func testBareVerdictAfterBareNonVerdictObject() throws {
        let output = """
        Quick config check: {"timeoutSeconds": 30} looked fine.

        {"verdict": "done", "note": "Shipped."}
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertEqual(extraction.verdict.verdict, .done)
        XCTAssertTrue(extraction.strippedOutput.contains("timeoutSeconds"))
    }

    // MARK: - Error cases

    func testContinueWithoutHandoverErrors() {
        let output = """
        Looks mostly done.

        ```json
        {"verdict": "continue"}
        ```
        """
        let result = RelayVerdictParser.extract(from: output)
        XCTAssertEqual(result.failureError, .continueWithoutHandover)
    }

    func testContinueWithEmptyHandoverErrors() {
        let output = """
        {"verdict": "continue", "handover": "   "}
        """
        let result = RelayVerdictParser.extract(from: output)
        XCTAssertEqual(result.failureError, .continueWithoutHandover)
    }

    func testNoVerdictAtAllErrors() {
        let output = "Ran the tests, all green, will keep going next round."
        let result = RelayVerdictParser.extract(from: output)
        XCTAssertEqual(result.failureError, .noVerdictFound)
    }

    func testGarbageInputErrors() {
        let result = RelayVerdictParser.extract(from: "asdf 1234 {{{ not json at all ]]]")
        XCTAssertEqual(result.failureError, .noVerdictFound)
    }

    func testUnknownVerdictStringErrors() {
        let output = """
        ```json
        {"verdict": "maybe", "note": "unsure"}
        ```
        """
        let result = RelayVerdictParser.extract(from: output)
        XCTAssertEqual(result.failureError, .unknownVerdict("maybe"))
    }

    // MARK: - Prose containing braces (false-positive guard)

    func testProseBracesDoNotMaskRealVerdict() throws {
        let output = """
        The config format uses `{key: value}` syntax and a stray `{` for style.

        ```json
        {"verdict": "done", "note": "All good."}
        ```
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertEqual(extraction.verdict.verdict, .done)
    }

    func testProseBracesAloneYieldNoVerdictFound() {
        let output = "Style note: use `{}` for empty objects, not `[]`."
        let result = RelayVerdictParser.extract(from: output)
        XCTAssertEqual(result.failureError, .noVerdictFound)
    }

    // MARK: - strippedOutput correctness

    func testStrippedOutputPreservesSurroundingProseVerbatim() throws {
        let output = """
        # Round 3 review

        Checked `baseline..HEAD`. The empty-state fix lands cleanly and the fixture
        screenshot at `artifacts/s3/empty-state.png` matches the design exemplar.

        One nit: the loading spinner still flashes on fast networks — not blocking.

        ```json
        {"verdict": "continue", "handover": "Debounce the spinner by 150ms before the next round."}
        ```
        """
        let extraction = try unwrap(RelayVerdictParser.extract(from: output))
        XCTAssertFalse(extraction.strippedOutput.contains("```json"))
        XCTAssertFalse(extraction.strippedOutput.contains("verdict"))
        XCTAssertTrue(extraction.strippedOutput.contains("# Round 3 review"))
        XCTAssertTrue(extraction.strippedOutput.contains("artifacts/s3/empty-state.png"))
        XCTAssertTrue(extraction.strippedOutput.contains("loading spinner still flashes"))
        XCTAssertTrue(extraction.strippedOutput.hasSuffix("not blocking."))
    }

    // MARK: - Codable roundtrip (wire value for `continue`)

    func testContinueRelayEncodesAsBareContinue() throws {
        let verdict = RelayVerdict(verdict: .continueRelay, handover: "go")
        let data = try CoreJSON.encode(verdict)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"continue\""))
        let decoded = try CoreJSON.decode(RelayVerdict.self, from: data)
        XCTAssertEqual(decoded, verdict)
    }
}

// MARK: - Test helpers

private func unwrap(
    _ result: Result<RelayVerdictParser.Extraction, RelayVerdictParser.ExtractError>,
    file: StaticString = #filePath, line: UInt = #line
) throws -> RelayVerdictParser.Extraction {
    switch result {
    case .success(let extraction): return extraction
    case .failure(let error):
        XCTFail("expected success, got \(error)", file: file, line: line)
        throw error
    }
}

private extension Result where Failure == RelayVerdictParser.ExtractError {
    var failureError: RelayVerdictParser.ExtractError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
