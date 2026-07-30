import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `GrokCapacityLog`. Never reads `~/.grok` — content is inline.
final class GrokCapacityLogTests: XCTestCase {

    // Verified 2026-07-30 against `/usage` ("Weekly limit: 42%  Next reset: July 31, 11:11").
    private let record20260730 = #"""
    {"ts":"2026-07-30T00:48:39.329Z","src":"shell","pid":55275,"ver":"0.2.114","lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":42.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-24T18:11:40.374130+00:00","end":"2026-07-31T18:11:40.374130+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true,"billingPeriodStart":"2026-07-24T18:11:40.374130+00:00","billingPeriodEnd":"2026-07-31T18:11:40.374130+00:00","historyLen":0},"onDemandEnabled":null,"subscriptionTier":"X Premium+"}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    // Older snapshot: different percent + non-zero on-demand cap.
    private let record20260717 = #"""
    {"ts":"2026-07-17T12:00:00.000Z","src":"shell","pid":1,"ver":"0.2.100","lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":41.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-10T18:11:40.374130+00:00","end":"2026-07-17T18:11:40.374130+00:00"},"onDemandCap":{"val":500},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true},"onDemandEnabled":null,"subscriptionTier":"X Premium+"}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    private var expectedPeriodEnd: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-07-31T18:11:40.374130+00:00")!
    }

    private var expectedObservedAt: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-07-30T00:48:39.329Z")!
    }

    func testReal20260730Record() {
        let got = GrokCapacityLog.latestWeeklyWindow(fromLogContent: record20260730)
        XCTAssertNotNil(got)
        XCTAssertEqual(got?.usedPercent, 42.0)
        XCTAssertEqual(got?.periodEnd, expectedPeriodEnd)
        XCTAssertEqual(got?.observedAt, expectedObservedAt)
        XCTAssertEqual(got?.subscriptionTier, "X Premium+")
        XCTAssertEqual(got?.onDemandCap, 0)
        XCTAssertEqual(got?.onDemandUsed, 0)
        XCTAssertEqual(got?.prepaidBalance, 0)
    }

    func testMostRecentWinsRegardlessOfOrder() {
        let olderFirst = record20260717 + "\n" + record20260730
        let newerFirst = record20260730 + "\n" + record20260717

        let a = GrokCapacityLog.latestWeeklyWindow(fromLogContent: olderFirst)
        let b = GrokCapacityLog.latestWeeklyWindow(fromLogContent: newerFirst)

        XCTAssertEqual(a?.usedPercent, 42.0)
        XCTAssertEqual(b?.usedPercent, 42.0)
        XCTAssertEqual(a?.periodEnd, expectedPeriodEnd)
        XCTAssertEqual(b?.periodEnd, expectedPeriodEnd)
        XCTAssertEqual(a?.observedAt, expectedObservedAt)
        XCTAssertEqual(b?.observedAt, expectedObservedAt)
        // Older record's non-zero on-demand cap must not leak when newer wins.
        XCTAssertEqual(a?.onDemandCap, 0)
        XCTAssertEqual(b?.onDemandCap, 0)
    }

    func testUnrelatedLinesReturnNil() {
        let noise = """
        {"ts":"2026-07-30T00:00:00.000Z","src":"shell","msg":"session start","lvl":"info"}
        {"ts":"2026-07-30T00:01:00.000Z","src":"shell","msg":"tool call","lvl":"debug"}
        not even json
        """
        XCTAssertNil(GrokCapacityLog.latestWeeklyWindow(fromLogContent: noise))
        XCTAssertNil(GrokCapacityLog.latestWeeklyWindow(fromLogContent: ""))
        XCTAssertNil(GrokCapacityLog.latestWeeklyWindow(fromLogContent: "\n\n  \n"))
    }

    func testMalformedMixedWithGoodDoesNotThrow() {
        let mixed = """
        {"ts":"broken
        \(record20260730)
        {not json at all
        {"msg":"billing: fetched credits config","ctx":{}}
        """
        let got = GrokCapacityLog.latestWeeklyWindow(fromLogContent: mixed)
        XCTAssertEqual(got?.usedPercent, 42.0)
        XCTAssertEqual(got?.subscriptionTier, "X Premium+")
        XCTAssertEqual(got?.periodEnd, expectedPeriodEnd)
    }

    func testMissingCreditUsagePercentIsNilNotZero() {
        let missingPercent = #"""
        {"ts":"2026-07-30T00:48:39.329Z","src":"shell","pid":1,"ver":"0.2.114","lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-24T18:11:40.374130+00:00","end":"2026-07-31T18:11:40.374130+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0}},"subscriptionTier":"X Premium+"}}
        """#.trimmingCharacters(in: .whitespacesAndNewlines)

        let got = GrokCapacityLog.latestWeeklyWindow(fromLogContent: missingPercent)
        XCTAssertNil(got, "missing creditUsagePercent must be absent, never defaulted to 0")
    }
}
