import XCTest
@testable import AllnighterCore

final class AgyCapacityLogTests: XCTestCase {

    private let verbatimFixture = """
    Models & Quota

      Account: emailmike@gmail.com

    GEMINI MODELS
      Models within this group: Gemini Flash, Gemini Pro

      Weekly Limit
        [██████████████████████████████████████████████░░░░] 92.67%
        93% remaining · Refreshes in 164h 50m

      Five Hour Limit
        [█████████████████████████████░░░░░░░░░░░░░░░░░░░░░] 58.48%
        58% remaining · Refreshes in 3h 21m


    CLAUDE AND GPT MODELS
      Models within this group: Claude Opus, Claude Sonnet, GPT-OSS

      Weekly Limit
        [██████████████████████████████░░░░░░░░░░░░░░░░░░░░] 60.11%
        60% remaining · Refreshes in 51h 48m

      Five Hour Limit
        [ ... same shape, values unknown ... ]
    """

    private var fixedObservedAt: Date {
        Date(timeIntervalSince1970: 1770000000)
    }

    func testFullTwoPoolRender() {
        let pools = AgyCapacityLog.parse(renderText: verbatimFixture, observedAt: fixedObservedAt)
        XCTAssertEqual(pools.count, 2)

        // Account line PII
        XCTAssertEqual(pools[0].account, "emailmike@gmail.com")
        XCTAssertEqual(pools[1].account, "emailmike@gmail.com")

        // Pool 1: GEMINI MODELS
        let pool1 = pools[0]
        XCTAssertEqual(pool1.name, "GEMINI MODELS")
        XCTAssertEqual(pool1.memberModels, ["Gemini Flash", "Gemini Pro"])
        XCTAssertEqual(pool1.windows.count, 2)

        let p1w1 = pool1.windows[0]
        XCTAssertEqual(p1w1.kind, .weekly)
        XCTAssertEqual(p1w1.remainingPercent, 92.67)
        XCTAssertEqual(p1w1.observedAt, fixedObservedAt)
        // 164h 50m = 164 * 3600 + 50 * 60 = 593400s
        XCTAssertEqual(p1w1.resetAt, fixedObservedAt.addingTimeInterval(593400))

        let p1w2 = pool1.windows[1]
        XCTAssertEqual(p1w2.kind, .fiveHour)
        XCTAssertEqual(p1w2.remainingPercent, 58.48)
        XCTAssertEqual(p1w2.observedAt, fixedObservedAt)
        // 3h 21m = 3 * 3600 + 21 * 60 = 12060s
        XCTAssertEqual(p1w2.resetAt, fixedObservedAt.addingTimeInterval(12060))

        // Pool 2: CLAUDE AND GPT MODELS
        let pool2 = pools[1]
        XCTAssertEqual(pool2.name, "CLAUDE AND GPT MODELS")
        XCTAssertEqual(pool2.memberModels, ["Claude Opus", "Claude Sonnet", "GPT-OSS"])
        // Partial five-hour window skipped -> exactly 1 valid window
        XCTAssertEqual(pool2.windows.count, 1)

        let p2w1 = pool2.windows[0]
        XCTAssertEqual(p2w1.kind, .weekly)
        XCTAssertEqual(p2w1.remainingPercent, 60.11)
        XCTAssertEqual(p2w1.observedAt, fixedObservedAt)
        // 51h 48m = 51 * 3600 + 48 * 60 = 186480s
        XCTAssertEqual(p2w1.resetAt, fixedObservedAt.addingTimeInterval(186480))
    }

    func testRelativeResetMathAgainstFixedObservedAt() {
        let text = """
        GEMINI MODELS
          Models within this group: Gemini Flash

          Weekly Limit
            [██████████████████████████████████████████████░░░░] 80.00%
            80% remaining · Refreshes in 2h 30m
        """
        let observedAt = Date(timeIntervalSince1970: 1000000)
        let pools = AgyCapacityLog.parse(renderText: text, observedAt: observedAt)
        XCTAssertEqual(pools.count, 1)
        let window = pools[0].windows[0]
        
        let expectedDuration: TimeInterval = 2 * 3600 + 30 * 60 // 9000s
        XCTAssertEqual(window.observedAt, observedAt)
        XCTAssertEqual(window.resetAt, observedAt.addingTimeInterval(expectedDuration))
        XCTAssertEqual(window.resetAt.timeIntervalSince1970, 1009000)
    }

    func testRemainingVsUsedNormalization() {
        let text = """
        GEMINI MODELS
          Models within this group: Gemini Flash

          Weekly Limit
            [██████████████████████████████████████████████░░░░] 92.67%
            93% remaining · Refreshes in 10h
        """
        let pools = AgyCapacityLog.parse(renderText: text, observedAt: fixedObservedAt)
        XCTAssertEqual(pools.count, 1)
        let window = pools[0].windows[0]
        // Confirm remainingPercent is carried directly as remaining (92.67), not inverted or mixed
        XCTAssertEqual(window.remainingPercent, 92.67)
    }

    func testTruncatedFinalBlockParsesCompleteBlocks() {
        let truncated = """
        GEMINI MODELS
          Models within this group: Gemini Flash, Gemini Pro

          Weekly Limit
            [██████████████████████████████████████████████░░░░] 92.67%
            93% remaining · Refreshes in 164h 50m

        CLAUDE AND GPT MODELS
          Models within this group: Claude Opus
          Weekly Limit
            [███... truncated line
        """
        let pools = AgyCapacityLog.parse(renderText: truncated, observedAt: fixedObservedAt)
        XCTAssertEqual(pools.count, 1, "Complete block parses cleanly while truncated block is skipped")
        XCTAssertEqual(pools[0].name, "GEMINI MODELS")
        XCTAssertEqual(pools[0].windows.count, 1)
        XCTAssertEqual(pools[0].windows[0].remainingPercent, 92.67)
    }

    func testGarbageReturnsEmptyWithoutCrash() {
        XCTAssertTrue(AgyCapacityLog.parse(renderText: "", observedAt: fixedObservedAt).isEmpty)
        XCTAssertTrue(AgyCapacityLog.parse(renderText: "   \n\n ", observedAt: fixedObservedAt).isEmpty)
        XCTAssertTrue(AgyCapacityLog.parse(renderText: "not valid usage render\nrandom text", observedAt: fixedObservedAt).isEmpty)
        XCTAssertTrue(AgyCapacityLog.parse(renderText: "Models & Quota\nAccount: test@example.com", observedAt: fixedObservedAt).isEmpty)
    }

    func testMissingPercentIsNilNotZero() {
        let missingPercentText = """
        GEMINI MODELS
          Models within this group: Gemini Flash

          Weekly Limit
            [██████████████████████████████████████████████░░░░]
            Refreshes in 10h
        """
        let pools = AgyCapacityLog.parse(renderText: missingPercentText, observedAt: fixedObservedAt)
        XCTAssertTrue(pools.isEmpty, "Missing percentage block must be skipped, never defaulted to 0")
    }

    func testANSIAndBoxDrawingCharsTolerance() {
        let ansiFixture = """
        \u{001B}[1mModels & Quota\u{001B}[0m

          Account: \u{001B}[32memailmike@gmail.com\u{001B}[0m

        \u{001B}[34mGEMINI MODELS\u{001B}[0m
          Models within this group: Gemini Flash, Gemini Pro

          Weekly Limit
            [██████████████████████████████████████████████░░░░] \u{001B}[33m92.67%\u{001B}[0m
            93% remaining · Refreshes in 164h 50m
        """
        let pools = AgyCapacityLog.parse(renderText: ansiFixture, observedAt: fixedObservedAt)
        XCTAssertEqual(pools.count, 1)
        XCTAssertEqual(pools[0].account, "emailmike@gmail.com")
        XCTAssertEqual(pools[0].name, "GEMINI MODELS")
        XCTAssertEqual(pools[0].memberModels, ["Gemini Flash", "Gemini Pro"])
        XCTAssertEqual(pools[0].windows.count, 1)
        XCTAssertEqual(pools[0].windows[0].remainingPercent, 92.67)
    }
}
