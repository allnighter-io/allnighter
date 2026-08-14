import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `CodexCapacityProbe` (TUI screen-text parser).
/// All renders are inline — never reads `~/.codex` or spawns a process.
final class CodexCapacityProbeTests: XCTestCase {

    /// Confirmed founder capture 2026-07-31: Codex at 0% weekly limit remaining.
    /// Source: Codex /status TUI (v0.146.0).
    private let codexStatusRender = """
    │  >_ OpenAI Codex (v0.146.0)                                                  │
    │                                                                              │
    │ Visit https://chatgpt.com/codex/settings/usage for up-to-date                │
    │ information on rate limits and credits                                       │
    │                                                                              │
    │  Model:                gpt-5.6-terra (reasoning high, summaries auto)        │
    │  Directory:            ~/Documents/GitHub/Allnighter                         │
    │  Permissions:          Custom (workspace with network access)                │
    │  Agents.md:            AGENTS.md                                             │
      Account:              support@allnighter.io (Plus)                            │
    │  Collaboration mode:   Default                                               │
    │  Session:              019fb825-40c0-7e02-a5df-408aadc3650c                  │
    │                                                                              │
    │  Weekly limit:         [░░░░░░░░░░░░░░░░░░░░] 0% left                        │
    │                        (resets 21:32 on 4 Aug)              Continue
    """

    /// observedAt: 2026-07-31T05:41:00 PDT = 12:41 UTC
    private let observedAt = Date(timeIntervalSince1970: 1_753_786_860)

    // MARK: - Primary format

    func testCodexStatusRenderParsesWeeklyWindowAndPlanTier() throws {
        let windows = CodexCapacityProbe.capacityWindows(
            fromRender: codexStatusRender, observedAt: observedAt
        )
        XCTAssertEqual(windows.count, 1)
        let w = try XCTUnwrap(windows.first)
        XCTAssertEqual(w.source, "codex")
        XCTAssertEqual(w.scope, .weekly)
        XCTAssertEqual(w.sourceTier, .tuiProbe)
        // "0% left" → remainingPercent=0, usedPercent=100 (derived)
        XCTAssertEqual(w.remainingPercent, 0.0)
        XCTAssertEqual(w.usedPercent, 100.0)
        XCTAssertEqual(w.planTier, "Plus")
        XCTAssertNil(w.unknownReason)
    }

    /// Pins the parse mechanics (month/day/hour/minute extraction) with an
    /// explicit UTC zone, independent of whatever zone the default parameter
    /// would resolve to on the machine running this suite.
    func testCodexStatusRenderParsesResetDateAug4UTC() throws {
        let windows = CodexCapacityProbe.capacityWindows(
            fromRender: codexStatusRender, observedAt: observedAt, timeZone: TimeZone(identifier: "UTC")!
        )
        let w = try XCTUnwrap(windows.first)
        let reset = try XCTUnwrap(w.resetAt)
        // "resets 21:32 on 4 Aug" interpreted as UTC → August 4 at 21:32 UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.month, from: reset), 8)    // August
        XCTAssertEqual(cal.component(.day, from: reset), 4)
        XCTAssertEqual(cal.component(.hour, from: reset), 21)
        XCTAssertEqual(cal.component(.minute, from: reset), 32)
    }

    /// **Regression for the live 7-hour lie**: codex's TUI renders "resets
    /// HH:MM on D Mon" in the HOST'S LOCAL timezone, not UTC — confirmed
    /// against `account/rateLimits/read`'s `resetsAt` epoch and the on-disk
    /// rollout log's `resets_at` epoch, which agree with each other. The old
    /// implementation hardcoded `TimeZone(identifier: "UTC")`, which was
    /// silently correct only on a UTC machine (error == host's UTC offset).
    ///
    /// This pins a FIXED non-UTC zone (`America/Los_Angeles`, PDT = UTC-7 in
    /// August) explicitly — never `TimeZone.current` — so the assertion means
    /// the same thing on every CI host, including a UTC one, where the old bug
    /// would have been invisible.
    ///
    /// Mirrors the real capture from `Capacity_Native_Channels.md`: codex's own
    /// `resetsAt: 1786825938` is `2026-08-15T20:32:18Z`, i.e. `13:32:18 PDT`.
    func testCodexTUIResetInterpretedInHostLocalTimeNotUTC() throws {
        let pdt = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let render = """
        │  Weekly limit:         [░░░░░░░░░░░░░░░░░░░░] 87% left               │
        │                        (resets 13:32 on 15 Aug)                      │
          Account:              user@example.com (Plus)                       │
        """
        let windows = CodexCapacityProbe.capacityWindows(
            fromRender: render, observedAt: observedAt, timeZone: pdt
        )
        let w = try XCTUnwrap(windows.first)
        let reset = try XCTUnwrap(w.resetAt)

        // 13:32 PDT (UTC-7) == 20:32 UTC the same day — NOT 13:32 UTC, which is
        // what the pre-fix `TimeZone(identifier: "UTC")` code would have
        // produced (year is deliberately not asserted here — it is whichever
        // year `resolveDate` rolls forward to from `observedAt`, and is not
        // the point of this regression; the offset is).
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utcCal.component(.month, from: reset), 8)
        XCTAssertEqual(utcCal.component(.day, from: reset), 15)
        XCTAssertEqual(utcCal.component(.hour, from: reset), 20)
        XCTAssertEqual(utcCal.component(.minute, from: reset), 32)

        // Directly contradicts the old bug: interpreting "13:32" as UTC
        // (rather than PDT) would have landed on hour 13, not 20.
        XCTAssertNotEqual(utcCal.component(.hour, from: reset), 13)
    }

    /// Sanity check that the default parameter is genuinely `.current`, not a
    /// zone smuggled in as a default that happens to equal UTC.
    func testCapacityWindowsDefaultsToHostLocalTimeZone() throws {
        let render = """
        Weekly limit: 50% left
        (resets 10:00 on 20 Aug)
        Account: user@x.com (Plus)
        """
        let explicitCurrent = CodexCapacityProbe.capacityWindows(
            fromRender: render, observedAt: observedAt, timeZone: .current
        )
        let defaulted = CodexCapacityProbe.capacityWindows(
            fromRender: render, observedAt: observedAt
        )
        XCTAssertEqual(explicitCurrent.first?.resetAt, defaulted.first?.resetAt)
    }

    // MARK: - parseLeftPercent

    func testParseLeftPercentZero() {
        XCTAssertEqual(CodexCapacityProbe.parseLeftPercent(from: "0% left"), 0.0)
        XCTAssertEqual(CodexCapacityProbe.parseLeftPercent(from: "[░░░░░░░░░░░░░░░░░░░░] 0% left"), 0.0)
    }

    func testParseLeftPercentPartial() {
        XCTAssertEqual(CodexCapacityProbe.parseLeftPercent(from: "47.3% left"), 47.3)
        XCTAssertEqual(CodexCapacityProbe.parseLeftPercent(from: "100% left"), 100.0)
    }

    func testParseLeftPercentNilForNoMatch() {
        XCTAssertNil(CodexCapacityProbe.parseLeftPercent(from: "47% used"))
        XCTAssertNil(CodexCapacityProbe.parseLeftPercent(from: "no percent here"))
        XCTAssertNil(CodexCapacityProbe.parseLeftPercent(from: ""))
    }

    // MARK: - parseResetDateHHMM

    func testParseResetDate4Aug() {
        // "(resets 21:32 on 4 Aug)" interpreted as UTC (explicit zone — pinned,
        // not defaulted, so this stays meaningful on any CI host).
        let got = CodexCapacityProbe.parseResetDateHHMM(
            from: "(resets 21:32 on 4 Aug)", observedAt: observedAt, timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertNotNil(got)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.month, from: got!), 8)
        XCTAssertEqual(cal.component(.day, from: got!), 4)
        XCTAssertEqual(cal.component(.hour, from: got!), 21)
        XCTAssertEqual(cal.component(.minute, from: got!), 32)
    }

    func testParseResetDateWithoutParentheses() {
        let got = CodexCapacityProbe.parseResetDateHHMM(
            from: "resets 09:00 on 1 Jan", observedAt: observedAt, timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertNotNil(got)
    }

    func testParseResetDateNilForNoMatch() {
        XCTAssertNil(CodexCapacityProbe.parseResetDateHHMM(from: "0% left", observedAt: observedAt))
        XCTAssertNil(CodexCapacityProbe.parseResetDateHHMM(from: "", observedAt: observedAt))
    }

    // MARK: - parsePlanTierFromAccountLine

    func testParsePlanTierPlus() {
        XCTAssertEqual(
            CodexCapacityProbe.parsePlanTierFromAccountLine(from: "Account:  support@allnighter.io (Plus)"),
            "Plus"
        )
    }

    func testParsePlanTierPro() {
        XCTAssertEqual(
            CodexCapacityProbe.parsePlanTierFromAccountLine(from: "Account: user@x.com (Pro)"),
            "Pro"
        )
    }

    func testParsePlanTierNilWhenAbsent() {
        XCTAssertNil(CodexCapacityProbe.parsePlanTierFromAccountLine(from: "Account: user@x.com"))
        XCTAssertNil(CodexCapacityProbe.parsePlanTierFromAccountLine(from: "Model: gpt-5"))
    }

    // MARK: - Fail closed

    func testFailsClosedOnNoUsableData() {
        XCTAssertNil(CodexCapacityProbe.parse(renderText: "no useful content here", observedAt: observedAt))
        XCTAssertEqual(CodexCapacityProbe.capacityWindows(fromRender: "noise", observedAt: observedAt), [])
    }

    func testFailsClosedOnPercentWithoutReset() {
        // Percent alone — no reset line → nil.
        XCTAssertNil(CodexCapacityProbe.parse(renderText: "0% left", observedAt: observedAt))
    }

    func testFailsClosedOnResetWithoutPercent() {
        XCTAssertNil(CodexCapacityProbe.parse(
            renderText: "(resets 21:32 on 4 Aug)", observedAt: observedAt
        ))
    }
}
