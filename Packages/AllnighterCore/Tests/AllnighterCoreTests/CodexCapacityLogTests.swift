import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `CodexCapacityLog`. Never reads `~/.codex` — content is inline.
final class CodexCapacityLogTests: XCTestCase {

    // Verified 2026-07-28 against real plus rollout: primary weekly 10080, secondary null,
    // credits.balance is the string "0", rate_limits sibling of info.
    private let plusWeeklyOnly = #"""
    {"timestamp":"2026-07-28T12:09:28.472Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":26983,"cached_input_tokens":0,"output_tokens":300,"total_tokens":27283},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":52.0,"window_minutes":10080,"resets_at":1785904336},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    // June pro: primary is fiveHour (300), secondary is weekly (10080). credits null.
    private let proBothWindows = #"""
    {"timestamp":"2026-06-17T13:55:58.757Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":21160,"output_tokens":72,"total_tokens":21232},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":2.0,"window_minutes":300,"resets_at":1781715738},"secondary":{"used_percent":94.0,"window_minutes":10080,"resets_at":1781742737},"credits":null,"individual_limit":null,"plan_type":"pro","rate_limit_reached_type":null}}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    // Older observation with a *later* resets_at — must lose to newer timestamp.
    private let olderWithLaterReset = #"""
    {"timestamp":"2026-07-20T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":10080,"resets_at":9999999999},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"plus"}}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    private var plusObservedAt: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-07-28T12:09:28.472Z")!
    }

    private var proObservedAt: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-06-17T13:55:58.757Z")!
    }

    // MARK: - Real shapes

    func testPlusWeeklyOnlySecondaryNullAndCreditsString() {
        let got = CodexCapacityLog.latestWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(got.count, 1, "secondary null must not invent a short window")
        let w = got[0]
        XCTAssertEqual(w.usedPercent, 52.0)
        XCTAssertEqual(w.scope, .weekly)
        XCTAssertEqual(w.resetAt, Date(timeIntervalSince1970: 1_785_904_336))
        XCTAssertEqual(w.observedAt, plusObservedAt)
        XCTAssertEqual(w.planType, "plus")
        XCTAssertEqual(w.creditsBalance, 0.0, "balance string \"0\" parses as 0, not absent")
    }

    func testProPrimaryFiveHourSecondaryWeekly() {
        let got = CodexCapacityLog.latestWindows(fromLogContent: proBothWindows)
        XCTAssertEqual(got.count, 2)

        let fiveHour = got.first { $0.scope == .fiveHour }
        let weekly = got.first { $0.scope == .weekly }
        XCTAssertEqual(fiveHour?.usedPercent, 2.0)
        XCTAssertEqual(fiveHour?.resetAt, Date(timeIntervalSince1970: 1_781_715_738))
        XCTAssertEqual(fiveHour?.planType, "pro")
        XCTAssertNil(fiveHour?.creditsBalance, "credits null → absent, never zero")

        XCTAssertEqual(weekly?.usedPercent, 94.0)
        XCTAssertEqual(weekly?.resetAt, Date(timeIntervalSince1970: 1_781_742_737))
        XCTAssertEqual(weekly?.planType, "pro")
        XCTAssertNil(weekly?.creditsBalance)
        XCTAssertEqual(fiveHour?.observedAt, proObservedAt)
        XCTAssertEqual(weekly?.observedAt, proObservedAt)
    }

    // MARK: - Six traps

    func testModelContextWindowIsNotEmittedAsCapacity() {
        // info.model_context_window is present and large; only rate_limits primary is quota.
        let got = CodexCapacityLog.latestWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].scope, .weekly)
        XCTAssertEqual(got[0].usedPercent, 52.0)
        // No window whose reset or percent could have come from 258400 context tokens.
        XCTAssertFalse(got.contains { $0.usedPercent == 258400 || $0.resetAt.timeIntervalSince1970 == 258400 })

        let windows = CodexCapacityLog.capacityWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].source, "codex")
        XCTAssertEqual(windows[0].scope, .weekly)
        // CapacityWindow must not invent a session-scope window from context size.
        XCTAssertFalse(windows.contains { $0.scope == .session })
    }

    func testCreditsBalanceNonNumericFailsClosedNeverDefaultsToZero() {
        let bad = #"""
        {"timestamp":"2026-07-28T12:09:28.472Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"primary":{"used_percent":52.0,"window_minutes":10080,"resets_at":1785904336},"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":"not-a-number"},"plan_type":"plus"}}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines)

        let got = CodexCapacityLog.latestWindows(fromLogContent: bad)
        XCTAssertTrue(got.isEmpty, "non-numeric credits.balance must fail closed, never invent 0")

        let asNumber = #"""
        {"timestamp":"2026-07-28T12:09:28.472Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"primary":{"used_percent":52.0,"window_minutes":10080,"resets_at":1785904336},"secondary":null,"credits":{"has_credits":true,"unlimited":false,"balance":12},"plan_type":"plus"}}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            CodexCapacityLog.latestWindows(fromLogContent: asNumber).isEmpty,
            "JSON number balance is the wrong type — fail closed rather than accept"
        )
    }

    func testUnknownWindowMinutesSkippedNotGuessed() {
        // Real free-plan size 43200 is not weekly and not fiveHour.
        let freeMonthly = #"""
        {"timestamp":"2026-06-26T17:46:06.684Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":35.0,"window_minutes":43200,"resets_at":1785087584},"secondary":null,"credits":null,"plan_type":"free"}}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            CodexCapacityLog.latestWindows(fromLogContent: freeMonthly).isEmpty,
            "43200 must not be guessed as monthly/weekly"
        )

        // Known weekly alongside unknown secondary must keep only the known slot.
        let mixed = #"""
        {"timestamp":"2026-07-28T12:09:28.472Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"primary":{"used_percent":52.0,"window_minutes":10080,"resets_at":1785904336},"secondary":{"used_percent":1.0,"window_minutes":999,"resets_at":1785904999},"credits":{"balance":"0"},"plan_type":"plus"}}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines)
        let got = CodexCapacityLog.latestWindows(fromLogContent: mixed)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].scope, .weekly)
        XCTAssertEqual(got[0].usedPercent, 52.0)
    }

    func testSecondaryNullIsAbsentNeverZero() {
        let got = CodexCapacityLog.latestWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(got.count, 1)
        XCTAssertNil(got.first { $0.scope == .fiveHour })
        // No phantom 0% fiveHour window.
        XCTAssertFalse(got.contains { $0.usedPercent == 0.0 && $0.scope == .fiveHour })
    }

    func testMostRecentByRecordTimestampNotResetsAt() {
        // Older line has a far-future resets_at; newer plus line has smaller resets_at.
        let olderFirst = olderWithLaterReset + "\n" + plusWeeklyOnly
        let newerFirst = plusWeeklyOnly + "\n" + olderWithLaterReset

        let a = CodexCapacityLog.latestWindows(fromLogContent: olderFirst)
        let b = CodexCapacityLog.latestWindows(fromLogContent: newerFirst)

        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(a[0].usedPercent, 52.0)
        XCTAssertEqual(b[0].usedPercent, 52.0)
        XCTAssertEqual(a[0].observedAt, plusObservedAt)
        XCTAssertEqual(b[0].observedAt, plusObservedAt)
        XCTAssertEqual(a[0].resetAt, Date(timeIntervalSince1970: 1_785_904_336))
        XCTAssertEqual(b[0].resetAt, Date(timeIntervalSince1970: 1_785_904_336))
        // Must not pick the older record's 9999999999 reset.
        XCTAssertNotEqual(a[0].resetAt, Date(timeIntervalSince1970: 9_999_999_999))
    }

    func testPlanTypePlusAndProBothParse() {
        let plus = CodexCapacityLog.latestWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(plus.first?.planType, "plus")

        let pro = CodexCapacityLog.latestWindows(fromLogContent: proBothWindows)
        XCTAssertTrue(pro.allSatisfy { $0.planType == "pro" })

        let plusWin = CodexCapacityLog.capacityWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(plusWin.first?.planTier, "plus")
        let proWins = CodexCapacityLog.capacityWindows(fromLogContent: proBothWindows)
        XCTAssertTrue(proWins.allSatisfy { $0.planTier == "pro" })
    }

    // MARK: - Fail-closed set

    func testUnrelatedLinesReturnEmpty() {
        let noise = """
        {"timestamp":"2026-07-30T00:00:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"hi"}}
        {"timestamp":"2026-07-30T00:01:00.000Z","type":"response_item","payload":{}}
        not even json
        """
        XCTAssertTrue(CodexCapacityLog.latestWindows(fromLogContent: noise).isEmpty)
        XCTAssertTrue(CodexCapacityLog.latestWindows(fromLogContent: "").isEmpty)
        XCTAssertTrue(CodexCapacityLog.latestWindows(fromLogContent: "\n\n  \n").isEmpty)
        XCTAssertTrue(CodexCapacityLog.capacityWindows(fromLogContent: noise).isEmpty)
    }

    func testMalformedMixedWithGoodDoesNotThrow() {
        let mixed = """
        {"timestamp":"broken
        \(plusWeeklyOnly)
        {not json at all
        {"timestamp":"2026-07-28T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count"}}
        """
        let got = CodexCapacityLog.latestWindows(fromLogContent: mixed)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].usedPercent, 52.0)
        XCTAssertEqual(got[0].planType, "plus")
        XCTAssertEqual(got[0].scope, .weekly)
    }

    func testMissingUsedPercentIsNilNotZero() {
        let missing = #"""
        {"timestamp":"2026-07-28T12:09:28.472Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"primary":{"window_minutes":10080,"resets_at":1785904336},"secondary":null,"credits":{"balance":"0"},"plan_type":"plus"}}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines)

        let got = CodexCapacityLog.latestWindows(fromLogContent: missing)
        XCTAssertTrue(got.isEmpty, "missing used_percent must be absent, never defaulted to 0")
    }

    // MARK: - CAP-S02 conversion

    func testAsCapacityWindowsExactOnDiskAndPrepaid() {
        let windows = CodexCapacityLog.capacityWindows(fromLogContent: plusWeeklyOnly)
        XCTAssertEqual(windows.count, 1)
        let w = windows[0]
        XCTAssertEqual(w.source, "codex")
        XCTAssertEqual(w.scope, .weekly)
        XCTAssertEqual(w.usedPercent, 52.0)
        XCTAssertEqual(w.remainingPercent, 48.0)
        XCTAssertEqual(w.resetAt, Date(timeIntervalSince1970: 1_785_904_336))
        XCTAssertEqual(w.resetPrecision, .exact)
        XCTAssertEqual(w.observedAt, plusObservedAt)
        XCTAssertEqual(w.sourceTier, .onDisk)
        XCTAssertEqual(w.planTier, "plus")
        XCTAssertEqual(w.prepaidBalance, 0.0)
        XCTAssertNil(w.onDemand)
        XCTAssertNil(w.unknownReason)

        // Pro both scopes convert with credits absent.
        let pro = CodexCapacityLog.capacityWindows(fromLogContent: proBothWindows)
        XCTAssertEqual(pro.count, 2)
        XCTAssertTrue(pro.contains { $0.scope == .weekly && $0.usedPercent == 94.0 })
        XCTAssertTrue(pro.contains { $0.scope == .fiveHour && $0.usedPercent == 2.0 })
        XCTAssertTrue(pro.allSatisfy { $0.prepaidBalance == nil })
        XCTAssertTrue(pro.allSatisfy { $0.sourceTier == .onDisk })
        XCTAssertTrue(pro.allSatisfy { $0.resetPrecision == .exact })
    }
}
