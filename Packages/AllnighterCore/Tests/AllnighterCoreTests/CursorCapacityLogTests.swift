import XCTest
@testable import AllnighterCore

final class CursorCapacityLogTests: XCTestCase {

    private let verbatimFixture = """
────────────────────────────────────────────────────────────────────────────────
 Usage • Ultra                                                  Resets Aug 25
 Monthly plan and on-demand usage

 Category        Current             Usage
 Included        27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
   Auto          27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
   API           27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 On-Demand       $0 / $1             ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

 $1 remaining

 View in dashboard: cursor.com/dashboard?tab=usage
"""

    private var fixedObservedAt: Date {
        // 2026-07-29 18:00:00 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 29
        components.hour = 18
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)!
    }

    func testFullVerbatimRenderParsing() {
        guard let snapshot = CursorCapacityLog.parse(renderText: verbatimFixture, observedAt: fixedObservedAt) else {
            XCTFail("Failed to parse verbatim Cursor /usage render")
            return
        }

        // Header / Plan Tier & Scope
        XCTAssertEqual(snapshot.planTier, "Ultra")
        XCTAssertEqual(snapshot.scope, .monthly)
        XCTAssertEqual(snapshot.resetPrecision, .dayPrecision)
        XCTAssertEqual(snapshot.observedAt, fixedObservedAt)

        // Reset Date Resolution (July 29, 2026 -> Aug 25, 2026 00:00:00 UTC)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var expectedResetComponents = DateComponents()
        expectedResetComponents.year = 2026
        expectedResetComponents.month = 8
        expectedResetComponents.day = 25
        expectedResetComponents.hour = 0
        expectedResetComponents.minute = 0
        expectedResetComponents.second = 0
        let expectedResetDate = calendar.date(from: expectedResetComponents)
        XCTAssertEqual(snapshot.resetAt, expectedResetDate)

        // Nested Categories (Included -> Auto, API)
        XCTAssertEqual(snapshot.percentCategories.count, 3)

        let cat0 = snapshot.percentCategories[0]
        XCTAssertEqual(cat0.name, "Included")
        XCTAssertEqual(cat0.usedPercent, 27.0)
        XCTAssertEqual(cat0.remainingPercent, 73.0)
        XCTAssertEqual(cat0.hierarchy, .parent(children: ["Auto", "API"]))

        let cat1 = snapshot.percentCategories[1]
        XCTAssertEqual(cat1.name, "Auto")
        XCTAssertEqual(cat1.usedPercent, 27.0)
        XCTAssertEqual(cat1.remainingPercent, 73.0)
        XCTAssertEqual(cat1.hierarchy, .child(parent: "Included"))

        let cat2 = snapshot.percentCategories[2]
        XCTAssertEqual(cat2.name, "API")
        XCTAssertEqual(cat2.usedPercent, 27.0)
        XCTAssertEqual(cat2.remainingPercent, 73.0)
        XCTAssertEqual(cat2.hierarchy, .child(parent: "Included"))

        // On-Demand Money Spend (NOT a percentage)
        guard let money = snapshot.onDemandSpend else {
            XCTFail("Missing on-demand spend in snapshot")
            return
        }
        XCTAssertEqual(money.usedDollars, 0.0)
        XCTAssertEqual(money.capDollars, 1.0)
        XCTAssertEqual(money.remainingDollars, 1.0)
        XCTAssertEqual(money.currency, "$")
    }

    func testBareDateYearResolutionAndDecemberToAugustRollover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // observedAt in December 2026
        var decComponents = DateComponents()
        decComponents.year = 2026
        decComponents.month = 12
        decComponents.day = 10
        decComponents.hour = 12
        let decObservedAt = calendar.date(from: decComponents)!

        let decFixture = """
 Usage • Ultra                                                  Resets Aug 25
 Category        Current             Usage
 Included        10% used            ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
"""
        guard let snapshot = CursorCapacityLog.parse(renderText: decFixture, observedAt: decObservedAt) else {
            XCTFail("Failed to parse December fixture")
            return
        }

        // Must roll over to Aug 25, 2027
        var expectedComponents = DateComponents()
        expectedComponents.year = 2027
        expectedComponents.month = 8
        expectedComponents.day = 25
        expectedComponents.hour = 0
        expectedComponents.minute = 0
        expectedComponents.second = 0
        let expectedResetDate = calendar.date(from: expectedComponents)

        XCTAssertEqual(snapshot.resetAt, expectedResetDate)
    }

    func testNestedIncludedAutoAPINotFlattenedIntoPeers() {
        guard let snapshot = CursorCapacityLog.parse(renderText: verbatimFixture, observedAt: fixedObservedAt) else {
            XCTFail("Failed to parse fixture")
            return
        }

        // Verify structure differentiates parent vs children
        let parentCategories = snapshot.percentCategories.filter {
            if case .parent = $0.hierarchy { return true }
            return false
        }
        let childCategories = snapshot.percentCategories.filter {
            if case .child = $0.hierarchy { return true }
            return false
        }

        XCTAssertEqual(parentCategories.count, 1)
        XCTAssertEqual(parentCategories.first?.name, "Included")
        XCTAssertEqual(childCategories.count, 2)
        XCTAssertEqual(childCategories.map(\.name), ["Auto", "API"])
    }

    func testOnDemandDollarsParsedAsMoneyAndNotAsPercent() {
        let fixtureWithMoneyOnly = """
 Usage • Pro                                                    Resets Sep 10
 On-Demand       $15.50 / $50.00     ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 $34.50 remaining
"""
        guard let snapshot = CursorCapacityLog.parse(renderText: fixtureWithMoneyOnly, observedAt: fixedObservedAt) else {
            XCTFail("Failed to parse money fixture")
            return
        }

        XCTAssertTrue(snapshot.percentCategories.isEmpty, "On-demand spend must not be emitted as a percent category")
        guard let money = snapshot.onDemandSpend else {
            XCTFail("On-demand spend missing")
            return
        }

        XCTAssertEqual(money.usedDollars, 15.50)
        XCTAssertEqual(money.capDollars, 50.00)
        XCTAssertEqual(money.remainingDollars, 34.50)
        XCTAssertEqual(money.currency, "$")
    }

    func testMissingPercentIsNilNotZero() {
        let textWithMissingPercent = """
 Usage • Ultra                                                  Resets Aug 25
 Category        Current             Usage
 Included        n/a                 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
"""
        guard let snapshot = CursorCapacityLog.parse(renderText: textWithMissingPercent, observedAt: fixedObservedAt) else {
            XCTFail("Failed to parse fixture with missing percent")
            return
        }

        XCTAssertEqual(snapshot.percentCategories.count, 1)
        let cat = snapshot.percentCategories[0]
        XCTAssertEqual(cat.name, "Included")
        XCTAssertNil(cat.usedPercent, "Missing percent must be nil, never defaulted to 0")
        XCTAssertNil(cat.remainingPercent, "Missing remaining percent must be nil")
    }

    func testGarbageReturnsEmptyOrNilWithoutCrash() {
        XCTAssertNil(CursorCapacityLog.parse(renderText: "", observedAt: fixedObservedAt))
        XCTAssertNil(CursorCapacityLog.parse(renderText: "   \n\n ", observedAt: fixedObservedAt))
        XCTAssertNil(CursorCapacityLog.parse(renderText: "Random unparseable log text with no usage data", observedAt: fixedObservedAt))
    }

    func testANSIAndBoxDrawingFrameTolerance() {
        let ansiFixture = """
\u{001B}[1m Usage • Ultra                                                  Resets Aug 25\u{001B}[0m
\u{001B}[32m Monthly plan and on-demand usage\u{001B}[0m

 Category        Current             Usage
 Included        \u{001B}[33m27% used\u{001B}[0m            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
   Auto          \u{001B}[33m27% used\u{001B}[0m            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
   API           \u{001B}[33m27% used\u{001B}[0m            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 On-Demand       $0 / $1             ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

 $1 remaining
"""
        guard let snapshot = CursorCapacityLog.parse(renderText: ansiFixture, observedAt: fixedObservedAt) else {
            XCTFail("Failed to parse ANSI fixture")
            return
        }

        XCTAssertEqual(snapshot.planTier, "Ultra")
        XCTAssertEqual(snapshot.percentCategories.count, 3)
        XCTAssertEqual(snapshot.onDemandSpend?.usedDollars, 0.0)
    }
}
