import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `CapacityWindow`. No IO, no wall clock.
final class CapacityWindowTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_720_000_000)
    private let resetAt = Date(timeIntervalSince1970: 1_720_500_000)

    // MARK: 1 — polarity constructors produce an identical window

    func testUsedAndRemainingConstructorsProduceIdenticalWindow() {
        let fromUsed = CapacityWindow(
            used: 42,
            source: "grok",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: fixedNow,
            sourceTier: .onDisk,
            planTier: "X Premium+"
        )
        let fromRemaining = CapacityWindow(
            remaining: 58,
            source: "grok",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: fixedNow,
            sourceTier: .onDisk,
            planTier: "X Premium+"
        )

        XCTAssertEqual(fromUsed, fromRemaining)
        XCTAssertEqual(fromUsed.usedPercent, 42)
        XCTAssertEqual(fromUsed.remainingPercent, 58)
        XCTAssertEqual(fromRemaining.usedPercent, 42)
        XCTAssertEqual(fromRemaining.remainingPercent, 58)
    }

    // MARK: 2 — agy remaining polarity matches kimi used polarity

    func testAgyRemainingPolarityMatchesKimiUsedPolarity() {
        // agy reports remaining; kimi reports used. Same real window → same used%.
        let agy = CapacityWindow(
            remaining: 61,
            source: "agy",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: fixedNow,
            sourceTier: .tuiProbe,
            poolLabel: "GEMINI MODELS"
        )
        let kimi = CapacityWindow(
            used: 39,
            source: "kimi",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )

        XCTAssertEqual(agy.usedPercent, kimi.usedPercent)
        XCTAssertEqual(agy.remainingPercent, kimi.remainingPercent)
        XCTAssertEqual(agy.usedPercent, 39)
        XCTAssertEqual(agy.remainingPercent, 61)
        XCTAssertEqual(agy.poolLabel, "GEMINI MODELS")
    }

    // MARK: 3 — reset precision survives

    func testDayPrecisionResetIsNeverReportedAsExact() throws {
        let cursor = CapacityWindow(
            used: 27,
            source: "cursor_agent",
            scope: .monthly,
            resetAt: resetAt,
            resetPrecision: .day,
            observedAt: fixedNow,
            sourceTier: .tuiProbe,
            planTier: "Ultra",
            onDemand: CapacityPaidAmount(used: 0, cap: 1, remaining: 1, unit: "$")
        )

        XCTAssertEqual(cursor.resetPrecision, .day)
        XCTAssertNotEqual(cursor.resetPrecision, .exact)
        XCTAssertEqual(cursor.onDemand?.unit, "$")
        XCTAssertEqual(cursor.onDemand?.cap, 1)

        // Encode/decode must keep day, not upgrade to exact.
        let data = try CoreJSON.encode(cursor)
        let back = try CoreJSON.decode(CapacityWindow.self, from: data)
        XCTAssertEqual(back.resetPrecision, .day)
        XCTAssertNotEqual(back.resetPrecision, .exact)
    }

    // MARK: 4 — bucket boundaries including exactly-on-threshold

    func testBucketBoundariesIncludingThresholds() {
        XCTAssertEqual(
            CapacityWindow.bucket(remainingPercent: 100, unknownReason: nil),
            .fat
        )
        // Exactly at fat threshold → fat.
        XCTAssertEqual(
            CapacityWindow.bucket(
                remainingPercent: CapacityWindow.fatRemainingThreshold,
                unknownReason: nil
            ),
            .fat
        )
        // Just under fat threshold → thin.
        XCTAssertEqual(
            CapacityWindow.bucket(
                remainingPercent: CapacityWindow.fatRemainingThreshold - 0.001,
                unknownReason: nil
            ),
            .thin
        )
        XCTAssertEqual(
            CapacityWindow.bucket(remainingPercent: 0.001, unknownReason: nil),
            .thin
        )
        // Exactly at empty threshold → empty.
        XCTAssertEqual(
            CapacityWindow.bucket(
                remainingPercent: CapacityWindow.emptyRemainingThreshold,
                unknownReason: nil
            ),
            .empty
        )
        XCTAssertEqual(
            CapacityWindow.bucket(remainingPercent: -1, unknownReason: nil),
            .empty
        )

        // Instance path matches static classifier.
        let fat = CapacityWindow(
            remaining: CapacityWindow.fatRemainingThreshold,
            source: "codex",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: fixedNow,
            sourceTier: .onDisk
        )
        XCTAssertEqual(fat.bucket, .fat)

        let thin = CapacityWindow(
            remaining: CapacityWindow.fatRemainingThreshold - 1,
            source: "codex",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: fixedNow,
            sourceTier: .onDisk
        )
        XCTAssertEqual(thin.bucket, .thin)

        let empty = CapacityWindow(
            remaining: 0,
            source: "codex",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: fixedNow,
            sourceTier: .onDisk
        )
        XCTAssertEqual(empty.bucket, .empty)
        XCTAssertEqual(empty.usedPercent, 100)
    }

    // MARK: 5 — unknown cases distinguishable from each other and from 0%

    func testUnknownCasesDistinguishableFromEachOtherAndFromZero() {
        let vendorNothing = CapacityWindow.unknown(
            reason: .vendorExposesNothing,
            source: "aider",
            scope: .weekly,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )
        let parserFailed = CapacityWindow.unknown(
            reason: .parserFailed(observedAt: fixedNow),
            source: "claude_code",
            scope: .session,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )
        let neverSampled = CapacityWindow.unknown(
            reason: .neverSampled,
            source: "claude_code",
            scope: .weekly,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )
        let zeroRemaining = CapacityWindow(
            remaining: 0,
            source: "kimi",
            scope: .fiveHour,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )

        XCTAssertEqual(vendorNothing.bucket, .unknown)
        XCTAssertEqual(parserFailed.bucket, .unknown)
        XCTAssertEqual(neverSampled.bucket, .unknown)
        XCTAssertEqual(zeroRemaining.bucket, .empty)

        // Percentages stay nil — never zero-filled.
        XCTAssertNil(vendorNothing.usedPercent)
        XCTAssertNil(vendorNothing.remainingPercent)
        XCTAssertNil(parserFailed.usedPercent)
        XCTAssertNil(neverSampled.remainingPercent)

        // Reasons are distinct.
        XCTAssertNotEqual(vendorNothing.unknownReason, parserFailed.unknownReason)
        XCTAssertNotEqual(parserFailed.unknownReason, neverSampled.unknownReason)
        XCTAssertNotEqual(vendorNothing.unknownReason, neverSampled.unknownReason)

        // 0% empty is not unknown and has real percentages.
        XCTAssertNil(zeroRemaining.unknownReason)
        XCTAssertEqual(zeroRemaining.remainingPercent, 0)
        XCTAssertEqual(zeroRemaining.usedPercent, 100)
        XCTAssertNotEqual(zeroRemaining.bucket, vendorNothing.bucket)
    }

    // MARK: 6 — anchored decrement

    func testAnchoredDecrementMonotoneClampAndZeroBurn() {
        let sample = CapacityWindow(
            remaining: 40,
            source: "agy",
            scope: .fiveHour,
            resetAt: resetAt,
            resetPrecision: .minute,
            observedAt: fixedNow,
            sourceTier: .tuiProbe,
            poolLabel: "CLAUDE + GPT"
        )

        // Zero burn equals the observation exactly.
        XCTAssertEqual(sample.remainingCeiling(burnPercentSinceObservation: 0), 40)
        XCTAssertEqual(
            CapacityWindow.remainingCeiling(remainingObserved: 40, burnPercentSinceObservation: 0),
            40
        )

        // Decreases with burn; never exceeds last observation.
        let after10 = sample.remainingCeiling(burnPercentSinceObservation: 10)!
        let after25 = sample.remainingCeiling(burnPercentSinceObservation: 25)!
        XCTAssertEqual(after10, 30)
        XCTAssertEqual(after25, 15)
        XCTAssertLessThanOrEqual(after10, 40)
        XCTAssertLessThanOrEqual(after25, after10)

        // Monotone across an increasing burn series.
        var previous = 40.0
        for burn in stride(from: 0.0, through: 50.0, by: 5.0) {
            let ceiling = CapacityWindow.remainingCeiling(
                remainingObserved: 40,
                burnPercentSinceObservation: burn
            )
            XCTAssertLessThanOrEqual(ceiling, previous)
            previous = ceiling
        }

        // Clamps at 0 — never negative.
        XCTAssertEqual(
            CapacityWindow.remainingCeiling(remainingObserved: 40, burnPercentSinceObservation: 40),
            0
        )
        XCTAssertEqual(
            CapacityWindow.remainingCeiling(remainingObserved: 40, burnPercentSinceObservation: 99),
            0
        )
        XCTAssertGreaterThanOrEqual(
            CapacityWindow.remainingCeiling(remainingObserved: 40, burnPercentSinceObservation: 999),
            0
        )

        // Unknown has no ceiling.
        let unknown = CapacityWindow.unknown(
            reason: .neverSampled,
            source: "claude_code",
            scope: .weekly,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )
        XCTAssertNil(unknown.remainingCeiling(burnPercentSinceObservation: 0))
    }

    // MARK: 7 — Codable round-trip

    func testCodableRoundTripPreservesPrecisionScopeAndUnknownReason() throws {
        let grok = CapacityWindow(
            used: 42,
            source: "grok",
            scope: .weekly,
            resetAt: resetAt,
            resetPrecision: .exact,
            observedAt: fixedNow,
            sourceTier: .onDisk,
            planTier: "X Premium+",
            onDemand: CapacityPaidAmount(used: 0, cap: 500, remaining: 500, unit: nil),
            prepaidBalance: 0
        )
        let grokBack = try CoreJSON.decode(CapacityWindow.self, from: try CoreJSON.encode(grok))
        XCTAssertEqual(grokBack, grok)
        XCTAssertEqual(grokBack.resetPrecision, .exact)
        XCTAssertEqual(grokBack.scope, .weekly)
        XCTAssertEqual(grokBack.prepaidBalance, 0)
        XCTAssertEqual(grokBack.onDemand?.cap, 500)

        let day = CapacityWindow(
            used: 27,
            source: "cursor_agent",
            scope: .monthly,
            resetAt: resetAt,
            resetPrecision: .day,
            observedAt: fixedNow,
            sourceTier: .tuiProbe,
            planTier: "Ultra",
            onDemand: CapacityPaidAmount(used: 0, cap: 1, remaining: 1, unit: "$")
        )
        let dayBack = try CoreJSON.decode(CapacityWindow.self, from: try CoreJSON.encode(day))
        XCTAssertEqual(dayBack.resetPrecision, .day)
        XCTAssertEqual(dayBack.scope, .monthly)
        XCTAssertEqual(dayBack.onDemand?.unit, "$")

        let failedAt = Date(timeIntervalSince1970: 1_720_111_111)
        let unknown = CapacityWindow.unknown(
            reason: .parserFailed(observedAt: failedAt),
            source: "claude_code",
            scope: .session,
            observedAt: fixedNow,
            sourceTier: .tuiProbe
        )
        let unknownBack = try CoreJSON.decode(CapacityWindow.self, from: try CoreJSON.encode(unknown))
        XCTAssertEqual(unknownBack, unknown)
        XCTAssertEqual(unknownBack.unknownReason, .parserFailed(observedAt: failedAt))
        XCTAssertEqual(unknownBack.scope, .session)
        XCTAssertNil(unknownBack.usedPercent)
        XCTAssertEqual(unknownBack.bucket, .unknown)

        // Grok on-demand/prepaid surface for CAP-S02 mapping without loss.
        XCTAssertEqual(grokBack.onDemand?.used, 0)
        XCTAssertNil(grokBack.onDemand?.unit)
    }

    // MARK: CAP-S02 — extractor → CapacityWindow conversion

    func testGrokConversionWeeklyExactOnDiskAndPaidUnits() {
        let periodStart = Date(timeIntervalSince1970: 1_721_844_700)
        let periodEnd = Date(timeIntervalSince1970: 1_722_449_500)
        let observed = Date(timeIntervalSince1970: 1_722_300_000)
        let grok = GrokWeeklyCapacity(
            usedPercent: 42.0,
            periodStart: periodStart,
            periodEnd: periodEnd,
            observedAt: observed,
            subscriptionTier: "X Premium+",
            onDemandCap: 500,
            onDemandUsed: 12,
            prepaidBalance: 3
        )

        let window = grok.asCapacityWindow()
        XCTAssertEqual(window.source, "grok")
        XCTAssertEqual(window.scope, .weekly)
        XCTAssertEqual(window.usedPercent, 42.0)
        XCTAssertEqual(window.remainingPercent, 58.0)
        XCTAssertEqual(window.resetAt, periodEnd)
        XCTAssertEqual(window.resetPrecision, .exact)
        XCTAssertEqual(window.observedAt, observed)
        XCTAssertEqual(window.sourceTier, .onDisk)
        XCTAssertEqual(window.planTier, "X Premium+")
        XCTAssertEqual(window.onDemand?.used, 12)
        XCTAssertEqual(window.onDemand?.cap, 500)
        XCTAssertEqual(window.onDemand?.remaining, 488)
        XCTAssertNil(window.onDemand?.unit, "Grok paid units are dimensionless, not dollars")
        XCTAssertEqual(window.prepaidBalance, 3)
        XCTAssertNil(window.unknownReason)
    }

    func testAgyConversionFourWindowsAcrossTwoLabelledPools() {
        let observed = Date(timeIntervalSince1970: 1_770_000_000)
        let gemini = AgyPoolCapacity(
            account: "emailmike@gmail.com",
            name: "GEMINI MODELS",
            memberModels: ["Gemini Flash", "Gemini Pro"],
            windows: [
                AgyCapacityWindow(
                    kind: .weekly,
                    remainingPercent: 92.67,
                    observedAt: observed,
                    resetAt: observed.addingTimeInterval(593_400)
                ),
                AgyCapacityWindow(
                    kind: .fiveHour,
                    remainingPercent: 58.48,
                    observedAt: observed,
                    resetAt: observed.addingTimeInterval(12_060)
                ),
            ]
        )
        let claudeGpt = AgyPoolCapacity(
            account: "emailmike@gmail.com",
            name: "CLAUDE AND GPT MODELS",
            memberModels: ["Claude Opus", "Claude Sonnet", "GPT-OSS"],
            windows: [
                AgyCapacityWindow(
                    kind: .weekly,
                    remainingPercent: 60.11,
                    observedAt: observed,
                    resetAt: observed.addingTimeInterval(186_480)
                ),
                AgyCapacityWindow(
                    kind: .fiveHour,
                    remainingPercent: 40.0,
                    observedAt: observed,
                    resetAt: observed.addingTimeInterval(7_200)
                ),
            ]
        )

        let windows = gemini.asCapacityWindows() + claudeGpt.asCapacityWindows()
        XCTAssertEqual(windows.count, 4)

        XCTAssertEqual(windows.map(\.poolLabel), [
            "GEMINI MODELS", "GEMINI MODELS",
            "CLAUDE AND GPT MODELS", "CLAUDE AND GPT MODELS",
        ])
        XCTAssertEqual(windows.map(\.scope), [.weekly, .fiveHour, .weekly, .fiveHour])
        XCTAssertTrue(windows.allSatisfy { $0.source == "agy" })
        XCTAssertTrue(windows.allSatisfy { $0.sourceTier == .tuiProbe })
        XCTAssertTrue(windows.allSatisfy { $0.resetPrecision == .minute })
        XCTAssertTrue(windows.allSatisfy { $0.onDemand == nil })
        XCTAssertTrue(windows.allSatisfy { $0.prepaidBalance == nil })

        // Remaining polarity → consistent usedPercent.
        XCTAssertEqual(windows[0].remainingPercent, 92.67)
        XCTAssertEqual(windows[0].usedPercent!, 100.0 - 92.67, accuracy: 0.000_1)
        XCTAssertEqual(windows[2].remainingPercent, 60.11)
        XCTAssertEqual(windows[2].usedPercent!, 100.0 - 60.11, accuracy: 0.000_1)
    }

    func testKimiConversionUsedPolarityMinuteTuiProbe() {
        let observed = Date(timeIntervalSince1970: 1_770_000_000)
        let weekly = KimiCapacityWindow(
            kind: .weekly,
            usedPercent: 100.0,
            observedAt: observed,
            resetAt: observed.addingTimeInterval(151_380)
        )
        let fiveHour = KimiCapacityWindow(
            kind: .fiveHour,
            usedPercent: 0.0,
            observedAt: observed,
            resetAt: observed.addingTimeInterval(3_780)
        )

        let windows = KimiPlanCapacity(windows: [weekly, fiveHour]).asCapacityWindows()
        XCTAssertEqual(windows.count, 2)

        XCTAssertEqual(windows[0].source, "kimi")
        XCTAssertEqual(windows[0].scope, .weekly)
        XCTAssertEqual(windows[0].usedPercent, 100.0)
        XCTAssertEqual(windows[0].remainingPercent, 0.0)
        XCTAssertEqual(windows[0].resetPrecision, .minute)
        XCTAssertEqual(windows[0].sourceTier, .tuiProbe)
        XCTAssertNil(windows[0].poolLabel)
        XCTAssertNil(windows[0].onDemand)

        XCTAssertEqual(windows[1].scope, .fiveHour)
        XCTAssertEqual(windows[1].usedPercent, 0.0)
        XCTAssertEqual(windows[1].remainingPercent, 100.0)
        XCTAssertEqual(windows[1].sourceTier, .tuiProbe)
    }

    func testKimiUsedAndAgyRemainingPolaritiesAgreeOnUsedPercent() {
        let observed = Date(timeIntervalSince1970: 1_770_000_000)
        let reset = observed.addingTimeInterval(3_600)

        // Same real window: 39% used / 61% remaining.
        let kimi = KimiCapacityWindow(
            kind: .weekly,
            usedPercent: 39.0,
            observedAt: observed,
            resetAt: reset
        ).asCapacityWindow()
        let agy = AgyCapacityWindow(
            kind: .weekly,
            remainingPercent: 61.0,
            observedAt: observed,
            resetAt: reset
        ).asCapacityWindow(poolLabel: "GEMINI MODELS")

        XCTAssertEqual(kimi.usedPercent, agy.usedPercent)
        XCTAssertEqual(kimi.remainingPercent, agy.remainingPercent)
        XCTAssertEqual(kimi.usedPercent, 39.0)
        XCTAssertEqual(agy.poolLabel, "GEMINI MODELS")
        XCTAssertEqual(kimi.sourceTier, .tuiProbe)
        XCTAssertEqual(agy.sourceTier, .tuiProbe)
    }

    func testCursorConversionMonthlyDayPrecisionAndDollarsNotPercent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var observedComponents = DateComponents()
        observedComponents.year = 2026
        observedComponents.month = 7
        observedComponents.day = 29
        observedComponents.hour = 18
        let observed = calendar.date(from: observedComponents)!

        let fixture = """
        Usage • Ultra                                                  Resets Aug 25
         Monthly plan and on-demand usage

         Category        Current             Usage
         Included        27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
           Auto          27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
           API           27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
         On-Demand       $0 / $1             ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

         $1 remaining
        """

        let windows = CursorCapacityLog.capacityWindows(fromRender: fixture, observedAt: observed)
        XCTAssertEqual(windows.count, 2, "Auto and API are separate Cursor meters — not one Included rollup")

        XCTAssertEqual(windows.map(\.poolLabel), ["Auto", "API"])
        for window in windows {
            XCTAssertEqual(window.source, "cursor_agent")
            XCTAssertEqual(window.scope, .monthly)
            XCTAssertEqual(window.resetPrecision, .day)
            XCTAssertNotEqual(window.resetPrecision, .exact)
            XCTAssertEqual(window.sourceTier, .tuiProbe)
            XCTAssertEqual(window.usedPercent, 27.0)
            XCTAssertEqual(window.remainingPercent, 73.0)
            XCTAssertEqual(window.planTier, "Ultra")
        }

        // Dollars stay in paid-amount on the first meter only — never a percentage.
        XCTAssertEqual(windows[0].onDemand?.used, 0.0)
        XCTAssertEqual(windows[0].onDemand?.cap, 1.0)
        XCTAssertEqual(windows[0].onDemand?.remaining, 1.0)
        XCTAssertEqual(windows[0].onDemand?.unit, "$")
        XCTAssertNil(windows[1].onDemand, "on-demand spend is seat-level — once, not duplicated")
        XCTAssertNotEqual(windows[0].usedPercent, windows[0].onDemand?.used)

        var expectedReset = DateComponents()
        expectedReset.year = 2026
        expectedReset.month = 8
        expectedReset.day = 25
        expectedReset.hour = 0
        expectedReset.minute = 0
        expectedReset.second = 0
        XCTAssertEqual(windows[0].resetAt, calendar.date(from: expectedReset))
        XCTAssertEqual(windows[1].resetAt, calendar.date(from: expectedReset))
    }

    func testAcquisitionTierOnDiskForGrokTuiProbeForOthers() {
        let observed = Date(timeIntervalSince1970: 1_770_000_000)
        let reset = observed.addingTimeInterval(3_600)

        let grok = GrokWeeklyCapacity(
            usedPercent: 10,
            periodStart: observed,
            periodEnd: reset,
            observedAt: observed,
            subscriptionTier: "X Premium+",
            onDemandCap: 0,
            onDemandUsed: 0,
            prepaidBalance: 0
        ).asCapacityWindow()
        let agy = AgyCapacityWindow(
            kind: .weekly,
            remainingPercent: 90,
            observedAt: observed,
            resetAt: reset
        ).asCapacityWindow(poolLabel: "GEMINI MODELS")
        let kimi = KimiCapacityWindow(
            kind: .weekly,
            usedPercent: 10,
            observedAt: observed,
            resetAt: reset
        ).asCapacityWindow()
        let cursor = CursorCapacitySnapshot(
            planTier: "Ultra",
            scope: .monthly,
            resetAt: reset,
            resetPrecision: .dayPrecision,
            observedAt: observed,
            percentCategories: [
                CursorPercentCategory(name: "Included", usedPercent: 27, hierarchy: .standalone)
            ],
            onDemandSpend: CursorMoneySpend(usedDollars: 0, capDollars: 1)
        ).asCapacityWindows()

        XCTAssertEqual(grok.sourceTier, .onDisk)
        XCTAssertEqual(agy.sourceTier, .tuiProbe)
        XCTAssertEqual(kimi.sourceTier, .tuiProbe)
        XCTAssertEqual(cursor.first?.sourceTier, .tuiProbe)
    }
}
