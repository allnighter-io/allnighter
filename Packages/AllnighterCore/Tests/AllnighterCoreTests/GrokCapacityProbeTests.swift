import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `GrokCapacityProbe` (TUI screen-text parser).
/// All renders are inline — never reads `~/.grok` or spawns a process.
final class GrokCapacityProbeTests: XCTestCase {

    /// Confirmed founder capture 2026-07-31: Grok at 100% weekly limit.
    private let grokTUIRender = """
    Weekly limit: 100%
    Next reset: July 31, 11:11
    """

    /// observedAt: 2026-07-31T05:41:00 PDT (UTC-7) = 12:41 UTC
    private let observedAt = Date(timeIntervalSince1970: 1_753_786_860)

    // MARK: - Primary format

    func testGrokTUIWeeklyLimitAndNextReset() throws {
        let windows = GrokCapacityProbe.capacityWindows(
            fromRender: grokTUIRender, observedAt: observedAt
        )
        XCTAssertEqual(windows.count, 1)
        let w = try XCTUnwrap(windows.first)
        XCTAssertEqual(w.source, "grok")
        XCTAssertEqual(w.scope, .weekly)
        XCTAssertEqual(w.sourceTier, .tuiProbe)
        // "Weekly limit: 100%" is used-polarity: 100% used.
        XCTAssertEqual(w.usedPercent, 100.0)
        XCTAssertEqual(w.remainingPercent, 0.0)
        XCTAssertNil(w.unknownReason)
    }

    func testGrokTUINextResetParsesLocalDate() throws {
        let windows = GrokCapacityProbe.capacityWindows(
            fromRender: grokTUIRender, observedAt: observedAt
        )
        let w = try XCTUnwrap(windows.first)
        let reset = try XCTUnwrap(w.resetAt)
        // "Next reset: July 31, 11:11" should resolve to July 31 at 11:11 local time.
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: reset), 7)   // July
        XCTAssertEqual(cal.component(.day, from: reset), 31)
        XCTAssertEqual(cal.component(.hour, from: reset), 11)
        XCTAssertEqual(cal.component(.minute, from: reset), 11)
    }

    // MARK: - parsePercent

    func testParseBarePercentUsedPolarity() {
        // "Weekly limit: 100%" — bare % → used-polarity (not remaining).
        XCTAssertEqual(GrokCapacityProbe.parsePercent(from: "Weekly limit: 100%", remainingPolarity: false), 100.0)
        XCTAssertEqual(GrokCapacityProbe.parsePercent(from: "Weekly limit: 54%", remainingPolarity: false), 54.0)
        XCTAssertEqual(GrokCapacityProbe.parsePercent(from: "54.5% used", remainingPolarity: false), 54.5)
    }

    func testParsePercentRemainingPolarityConverts() {
        // "46% left" → usedPercent = 54.0
        XCTAssertEqual(GrokCapacityProbe.parsePercent(from: "46% left", remainingPolarity: true), 54.0)
    }

    // MARK: - parseNextResetLocalDate

    func testParseNextResetJuly31() {
        // "Next reset: July 31, 11:11"
        let got = GrokCapacityProbe.parseNextResetLocalDate(
            from: "Next reset: July 31, 11:11", observedAt: observedAt
        )
        XCTAssertNotNil(got)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: got!), 7)
        XCTAssertEqual(cal.component(.day, from: got!), 31)
        XCTAssertEqual(cal.component(.hour, from: got!), 11)
        XCTAssertEqual(cal.component(.minute, from: got!), 11)
    }

    func testParseNextResetCaseInsensitive() {
        let got = GrokCapacityProbe.parseNextResetLocalDate(
            from: "next reset: august 4, 09:00", observedAt: observedAt
        )
        XCTAssertNotNil(got)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: got!), 8)
        XCTAssertEqual(cal.component(.day, from: got!), 4)
        XCTAssertEqual(cal.component(.hour, from: got!), 9)
        XCTAssertEqual(cal.component(.minute, from: got!), 0)
    }

    func testParseNextResetNilForUnrecognizedFormat() {
        XCTAssertNil(GrokCapacityProbe.parseNextResetLocalDate(from: "Weekly limit: 100%", observedAt: observedAt))
        XCTAssertNil(GrokCapacityProbe.parseNextResetLocalDate(from: "", observedAt: observedAt))
    }

    // MARK: - parseResetDate dispatch order

    func testParseResetDatePrefersNextResetOverRelative() {
        // When a "Next reset:" line is present, it should win over "resets in".
        let line = "Next reset: July 31, 11:11 (resets in 5h 30m)"
        let got = GrokCapacityProbe.parseResetDate(from: line, observedAt: observedAt)
        XCTAssertNotNil(got)
        let cal = Calendar.current
        // "Next reset:" wins → July 31, 11:11 local.
        XCTAssertEqual(cal.component(.month, from: got!), 7)
        XCTAssertEqual(cal.component(.day, from: got!), 31)
        XCTAssertEqual(cal.component(.hour, from: got!), 11)
    }

    func testParseResetDateRelativeDuration() {
        let line = "Resets in 6d 3h 20m"
        let got = GrokCapacityProbe.parseResetDate(from: line, observedAt: observedAt)
        XCTAssertNotNil(got)
        let days: TimeInterval = 6.0 * 86400.0
        let hours: TimeInterval = 3.0 * 3600.0
        let mins: TimeInterval = 20.0 * 60.0
        let interval: TimeInterval = days + hours + mins
        let expected = observedAt.addingTimeInterval(interval)
        XCTAssertEqual(
            got!.timeIntervalSinceReferenceDate,
            expected.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    // MARK: - Fail closed

    func testFailsClosedOnNoUsableData() {
        XCTAssertNil(GrokCapacityProbe.parse(renderText: "no useful content here", observedAt: observedAt))
        XCTAssertEqual(GrokCapacityProbe.capacityWindows(fromRender: "noise", observedAt: observedAt), [])
    }

    func testFailsClosedOnPercentWithoutReset() {
        // Percent alone — no reset → nil.
        let render = "Weekly limit: 54%"
        XCTAssertNil(GrokCapacityProbe.parse(renderText: render, observedAt: observedAt))
    }
}
