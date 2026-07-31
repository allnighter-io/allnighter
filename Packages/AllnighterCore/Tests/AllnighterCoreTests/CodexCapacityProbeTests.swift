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
      Account:              emailmike@gmail.com (Plus)                            │
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

    func testCodexStatusRenderParsesResetDateAug4UTC() throws {
        let windows = CodexCapacityProbe.capacityWindows(
            fromRender: codexStatusRender, observedAt: observedAt
        )
        let w = try XCTUnwrap(windows.first)
        let reset = try XCTUnwrap(w.resetAt)
        // "resets 21:32 on 4 Aug" → UTC August 4 at 21:32
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.month, from: reset), 8)    // August
        XCTAssertEqual(cal.component(.day, from: reset), 4)
        XCTAssertEqual(cal.component(.hour, from: reset), 21)
        XCTAssertEqual(cal.component(.minute, from: reset), 32)
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
        // "(resets 21:32 on 4 Aug)"
        let got = CodexCapacityProbe.parseResetDateHHMM(
            from: "(resets 21:32 on 4 Aug)", observedAt: observedAt
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
            from: "resets 09:00 on 1 Jan", observedAt: observedAt
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
            CodexCapacityProbe.parsePlanTierFromAccountLine(from: "Account:  emailmike@gmail.com (Plus)"),
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
