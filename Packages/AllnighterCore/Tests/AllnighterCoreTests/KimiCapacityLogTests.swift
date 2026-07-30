import XCTest
@testable import AllnighterCore

final class KimiCapacityLogTests: XCTestCase {

    private let verbatimUsageFixture = """
   ╭ Usage ───────────────────────────────────────────────────────────────╮
   │ Session usage                                                        │
   │   No token usage recorded yet.                                       │
   │                                                                      │
   │ Context window                                                       │
   │   ░░░░░░░░░░░░░░░░░░░░      0%  (0 / 1M)                             │
   │                                                                      │
   │ Plan usage                                                           │
   │   Weekly limit  ████████████████████  100% used  resets in 1d 18h 3m │
   │   5h limit      ░░░░░░░░░░░░░░░░░░░░  0% used    resets in 1h 3m     │
   ╰──────────────────────────────────────────────────────────────────────╯
"""

    private let verbatimStatusFixture = """
Kimi Code Status
Model: kimi-code/k3
Session: session_98765
Permissions: auto

   ╭ Usage ───────────────────────────────────────────────────────────────╮
   │ Session usage                                                        │
   │   No token usage recorded yet.                                       │
   │                                                                      │
   │ Context window                                                       │
   │   ░░░░░░░░░░░░░░░░░░░░      0%  (0 / 1M)                             │
   │                                                                      │
   │ Plan usage                                                           │
   │   Weekly limit  ████████████████████  100% used  resets in 1d 18h 3m │
   │   5h limit      ░░░░░░░░░░░░░░░░░░░░  0% used    resets in 1h 3m     │
   ╰──────────────────────────────────────────────────────────────────────╯
"""

    private var fixedObservedAt: Date {
        Date(timeIntervalSince1970: 1770000000)
    }

    func testFullUsageBlockRender() {
        let windows = KimiCapacityLog.parseWindows(fromRender: verbatimUsageFixture, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.count, 2)

        // Window 1: Weekly limit (100% used, resets in 1d 18h 3m)
        let w1 = windows[0]
        XCTAssertEqual(w1.kind, .weekly)
        XCTAssertEqual(w1.usedPercent, 100.0)
        XCTAssertEqual(w1.remainingPercent, 0.0)
        XCTAssertEqual(w1.observedAt, fixedObservedAt)
        // 1d 18h 3m = (1 * 86400) + (18 * 3600) + (3 * 60) = 86400 + 64800 + 180 = 151380s
        XCTAssertEqual(w1.resetAt, fixedObservedAt.addingTimeInterval(151380))

        // Window 2: 5h limit (0% used, resets in 1h 3m)
        let w2 = windows[1]
        XCTAssertEqual(w2.kind, .fiveHour)
        XCTAssertEqual(w2.usedPercent, 0.0)
        XCTAssertEqual(w2.remainingPercent, 100.0)
        XCTAssertEqual(w2.observedAt, fixedObservedAt)
        // 1h 3m = (1 * 3600) + (3 * 60) = 3600 + 180 = 3780s
        XCTAssertEqual(w2.resetAt, fixedObservedAt.addingTimeInterval(3780))
    }

    func testStatusVariantWithHeaderMetadata() {
        guard let capacity = KimiCapacityLog.parsePlanCapacity(fromRender: verbatimStatusFixture, observedAt: fixedObservedAt) else {
            XCTFail("Failed to parse status fixture capacity")
            return
        }

        XCTAssertEqual(capacity.model, "kimi-code/k3")
        XCTAssertEqual(capacity.sessionId, "session_98765")
        XCTAssertEqual(capacity.windows.count, 2)

        XCTAssertEqual(capacity.windows[0].kind, .weekly)
        XCTAssertEqual(capacity.windows[0].usedPercent, 100.0)

        XCTAssertEqual(capacity.windows[1].kind, .fiveHour)
        XCTAssertEqual(capacity.windows[1].usedPercent, 0.0)
    }

    func testContextWindowRowIsExcludedFromResults() {
        let textWithContextOnly = """
   ╭ Usage ───────────────────────────────────────────────────────────────╮
   │ Context window                                                       │
   │   ░░░░░░░░░░░░░░░░░░░░      0%  (0 / 1M)                             │
   ╰──────────────────────────────────────────────────────────────────────╯
"""
        let windows = KimiCapacityLog.parseWindows(fromRender: textWithContextOnly, observedAt: fixedObservedAt)
        XCTAssertTrue(windows.isEmpty, "Context window must NEVER be emitted as a capacity window")
    }

    func testRelativeResetMathIncludingDayUnit() {
        let text = """
   ╭ Usage ───────────────────────────────────────────────────────────────╮
   │ Plan usage                                                           │
   │   Weekly limit  ████████████████████  50% used   resets in 2d 5h 10m  │
   ╰──────────────────────────────────────────────────────────────────────╯
"""
        let windows = KimiCapacityLog.parseWindows(fromRender: text, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.count, 1)
        
        let window = windows[0]
        XCTAssertEqual(window.kind, .weekly)
        XCTAssertEqual(window.usedPercent, 50.0)
        XCTAssertEqual(window.remainingPercent, 50.0)
        
        // 2d 5h 10m = (2 * 86400) + (5 * 3600) + (10 * 60) = 172800 + 18000 + 600 = 191400s
        let expectedDuration: TimeInterval = 191400
        XCTAssertEqual(window.observedAt, fixedObservedAt)
        XCTAssertEqual(window.resetAt, fixedObservedAt.addingTimeInterval(expectedDuration))
        XCTAssertEqual(window.resetAt.timeIntervalSince1970, 1770191400)
    }

    func testFullyTappedSeat100PercentUsedParsesCleanly() {
        let text = """
   │ Plan usage                                                           │
   │   Weekly limit  ████████████████████  100% used  resets in 12h       │
"""
        let windows = KimiCapacityLog.parseWindows(fromRender: text, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.count, 1)
        
        let window = windows[0]
        XCTAssertEqual(window.usedPercent, 100.0)
        XCTAssertEqual(window.remainingPercent, 0.0)
        XCTAssertEqual(window.resetAt, fixedObservedAt.addingTimeInterval(12 * 3600))
    }

    func testGarbageReturnsEmptyWithoutCrash() {
        XCTAssertTrue(KimiCapacityLog.parseWindows(fromRender: "", observedAt: fixedObservedAt).isEmpty)
        XCTAssertTrue(KimiCapacityLog.parseWindows(fromRender: "   \n\n ", observedAt: fixedObservedAt).isEmpty)
        XCTAssertTrue(KimiCapacityLog.parseWindows(fromRender: "random text without plan usage", observedAt: fixedObservedAt).isEmpty)
        XCTAssertNil(KimiCapacityLog.parsePlanCapacity(fromRender: "invalid garbage render", observedAt: fixedObservedAt))
    }

    func testMissingPercentIsNilNotZero() {
        let missingPercentText = """
   │ Plan usage                                                           │
   │   Weekly limit  ████████████████████  resets in 1d 18h 3m            │
"""
        let windows = KimiCapacityLog.parseWindows(fromRender: missingPercentText, observedAt: fixedObservedAt)
        XCTAssertTrue(windows.isEmpty, "Missing percentage window must be skipped, never defaulted to 0")
    }

    func testANSIAndBoxDrawingFrameTolerance() {
        let ansiFixture = """
\u{001B}[1mKimi Code Status\u{001B}[0m
\u{001B}[32mModel: kimi-code/k3\u{001B}[0m

   ╭ Usage ───────────────────────────────────────────────────────────────╮
   │ \u{001B}[34mPlan usage\u{001B}[0m                                                           │
   │   Weekly limit  ████████████████████  \u{001B}[31m100% used\u{001B}[0m  resets in 1d 18h 3m │
   │   5h limit      ░░░░░░░░░░░░░░░░░░░░  \u{001B}[32m0% used\u{001B}[0m    resets in 1h 3m     │
   ╰──────────────────────────────────────────────────────────────────────╯
"""
        let capacity = KimiCapacityLog.parsePlanCapacity(fromRender: ansiFixture, observedAt: fixedObservedAt)
        XCTAssertNotNil(capacity)
        XCTAssertEqual(capacity?.model, "kimi-code/k3")
        XCTAssertEqual(capacity?.windows.count, 2)
        XCTAssertEqual(capacity?.windows[0].usedPercent, 100.0)
        XCTAssertEqual(capacity?.windows[1].usedPercent, 0.0)
    }
}
