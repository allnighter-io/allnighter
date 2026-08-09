import XCTest
@testable import AllnighterCore

/// Model-read of a captured usage pane.
///
/// Fixtures are REAL responses from `model_cursor_composer_25` against real
/// captures, recorded during the 2026-08-08 measurement (packet §4b) — not
/// invented shapes. The point of these tests is the layer we own: envelope
/// extraction, the confidence contract, and never manufacturing a window.
final class CapacityPaneReaderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Extraction

    /// Vendors wrap the answer differently, so extraction must not care. This is
    /// a real cursor-agent envelope shape: the model's JSON arrives as a string
    /// field inside the CLI's own result object.
    func testExtractsReadingFromAVendorEnvelope() throws {
        let output = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":6828,\
        "result":"{\\"pools\\":[{\\"label\\":\\"Included\\",\\"remainingPercent\\":57},\
        {\\"label\\":\\"Auto\\",\\"remainingPercent\\":58},\
        {\\"label\\":\\"API\\",\\"remainingPercent\\":52}],\
        \\"mostConstrainedRemaining\\":52,\\"resetAt\\":\\"2026-08-25T00:00:00Z\\",\
        \\"planTier\\":\\"Ultra\\",\\"confident\\":true,\\"reason\\":\\"three pools shown\\"}",\
        "usage":{"inputTokens":3,"outputTokens":184}}
        """
        // Fed exactly as the CLI prints it — escaped, valid JSON. Brace scanning
        // cannot see inside a JSON string, so this is the case that forces
        // envelope-aware extraction.
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertEqual(reading.mostConstrainedRemaining, 52)
        XCTAssertEqual(reading.pools.count, 3)
        XCTAssertTrue(reading.confident)
    }

    /// The envelope's own `{...}` comes FIRST, so taking the first balanced
    /// object would return the wrapper and lose the answer.
    func testPrefersTheAnswerObjectOverTheEnvelopeHeader() throws {
        let output = """
        {"event":"started","runId":"abc"}
        some prose the CLI printed
        {"pools":[],"mostConstrainedRemaining":91,"resetAt":null,"planTier":null,\
        "confident":true,"reason":"weekly 9% used"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertEqual(reading.mostConstrainedRemaining, 91)
    }

    /// Braces inside strings must not open or close a span.
    func testBracesInsideStringsDoNotBreakExtraction() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":42,"resetAt":null,"planTier":null,\
        "confident":true,"reason":"saw {weird} braces"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertEqual(reading.mostConstrainedRemaining, 42)
        XCTAssertEqual(reading.reason, "saw {weird} braces")
    }

    /// A CLI that errored, timed out, or printed prose yields no reading — which
    /// fails closed rather than inventing one.
    func testNoJSONYieldsNoReading() {
        XCTAssertNil(CapacityPaneReader.extractReading(from: ""))
        XCTAssertNil(CapacityPaneReader.extractReading(from: "error: not logged in"))
        XCTAssertNil(CapacityPaneReader.extractReading(from: #"{"unrelated":true}"#))
    }

    // MARK: - The confidence contract

    /// Real response to grok's 28KB splash-animation capture. `confident: false`
    /// is believed, not second-guessed — this is the whole reason the measured
    /// run had zero invented numbers.
    func testUnconfidentReadingProducesNoWindow() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":null,"resetAt":null,"planTier":null,\
        "confident":false,"reason":"Splash screen only, no quota data"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertFalse(reading.confident)
        XCTAssertNil(CapacityPaneReader.windows(from: reading, source: "grok", now: now))
    }

    /// Confidence alone is not enough — a confident answer with no number is
    /// still no answer.
    func testConfidentButNumberlessProducesNoWindow() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":null,"resetAt":null,"planTier":"Max",\
        "confident":true,"reason":"tier visible, no percentages"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        XCTAssertNil(CapacityPaneReader.windows(from: reading, source: "claude_code", now: now))
    }

    /// Out-of-range values are refused rather than clamped. Clamping would turn
    /// a nonsense reading into a plausible one, which is the failure mode that
    /// costs the most.
    func testImpossiblePercentagesAreRefusedNotClamped() throws {
        for value in ["-5", "140"] {
            let output = """
            {"pools":[],"mostConstrainedRemaining":\(value),"resetAt":null,\
            "planTier":null,"confident":true,"reason":"x"}
            """
            let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
            XCTAssertNil(
                CapacityPaneReader.windows(from: reading, source: "kimi", now: now),
                "\(value)% must not become a window")
        }
    }

    // MARK: - Window shape

    /// Real cursor reading. The window carries the MOST CONSTRAINED pool, since
    /// that is the one that actually gates the seat — reading a real but less
    /// constrained row (Included, 57) was the only miss in the measured run.
    func testWindowUsesTheMostConstrainedPool() throws {
        let output = """
        {"pools":[{"label":"Included","remainingPercent":57},\
        {"label":"Auto","remainingPercent":58},{"label":"API","remainingPercent":52}],\
        "mostConstrainedRemaining":52,"resetAt":"2026-08-25T00:00:00Z",\
        "planTier":"Ultra","confident":true,"reason":"three pools"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        let windows = try XCTUnwrap(
            CapacityPaneReader.windows(from: reading, source: "cursor_agent", now: now))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].remainingPercent, 52)
        XCTAssertEqual(windows[0].usedPercent, 48)
        XCTAssertEqual(windows[0].planTier, "Ultra")
        XCTAssertNil(windows[0].unknownReason)
    }

    /// A reading with no reset time still counts — the number is the useful part
    /// — but its precision must say so rather than implying an exact boundary.
    func testMissingResetIsNotAFakeExactTime() throws {
        let output = """
        {"pools":[],"mostConstrainedRemaining":51,"resetAt":null,"planTier":null,\
        "confident":true,"reason":"weekly 49% used"}
        """
        let reading = try XCTUnwrap(CapacityPaneReader.extractReading(from: output))
        let windows = try XCTUnwrap(
            CapacityPaneReader.windows(from: reading, source: "kimi", now: now))
        XCTAssertNil(windows[0].resetAt)
        XCTAssertNotEqual(windows[0].resetPrecision, .exact)
    }

    // MARK: - Reader invocation

    /// Cheapest seat per vendor: this is telemetry, and spending a premium model
    /// to measure how much of that model is left would be self-defeating.
    func testReaderUsesTheCheapestSeatAndFailsClosedOnUnknownSources() {
        let cursor = CapacityPaneReader.readerArguments(for: "cursor_agent")
        XCTAssertEqual(cursor?.contains("composer-2.5"), true)
        XCTAssertEqual(CapacityPaneReader.readerArguments(for: "claude_code")?.contains("haiku"), true)
        for source in CapacityProbe.probeableSources {
            XCTAssertNotNil(
                CapacityPaneReader.readerArguments(for: source),
                "\(source) is probeable, so it needs a reader invocation")
        }
        XCTAssertNil(CapacityPaneReader.readerArguments(for: "not_a_vendor"))
    }

    /// The pool rule has to survive prompt edits — it is what turned the one
    /// measured miss (57 vs 52) into an exact answer.
    func testPromptSpecifiesTheMostConstrainedPoolRule() {
        XCTAssertTrue(CapacityPaneReader.prompt.contains("LOWEST remaining"))
        XCTAssertTrue(CapacityPaneReader.prompt.contains("Do NOT guess"))
        XCTAssertTrue(CapacityPaneReader.prompt.contains("confident: false"))
    }
}
