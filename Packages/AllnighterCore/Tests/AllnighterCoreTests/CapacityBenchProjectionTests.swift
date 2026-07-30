import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `CapacityBenchProjection`. No IO, no wall clock.
/// Values mirror tonight's CAP-S00 spikes (Kimi, agy, Grok, Cursor).
final class CapacityBenchProjectionTests: XCTestCase {

    /// ~2026-07-30 00:48 UTC — matches the Grok log sample era.
    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    // MARK: - Helpers

    private func used(
        _ usedPercent: Double,
        source: String,
        scope: CapacityWindowScope,
        resetAt: Date?,
        precision: CapacityResetPrecision = .minute,
        observedAt: Date? = nil,
        poolLabel: String? = nil,
        planTier: String? = nil,
        onDemand: CapacityPaidAmount? = nil
    ) -> CapacityWindow {
        CapacityWindow(
            used: usedPercent,
            source: source,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: precision,
            observedAt: observedAt ?? now,
            sourceTier: .tuiProbe,
            poolLabel: poolLabel,
            planTier: planTier,
            onDemand: onDemand
        )
    }

    private func remaining(
        _ remainingPercent: Double,
        source: String,
        scope: CapacityWindowScope,
        resetAt: Date?,
        precision: CapacityResetPrecision = .minute,
        observedAt: Date? = nil,
        poolLabel: String? = nil,
        planTier: String? = nil
    ) -> CapacityWindow {
        CapacityWindow(
            remaining: remainingPercent,
            source: source,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: precision,
            observedAt: observedAt ?? now,
            sourceTier: .tuiProbe,
            poolLabel: poolLabel,
            planTier: planTier
        )
    }

    // MARK: 1 — Kimi: weekly 0% + 5h 100% → effective 0%, raw 5h reachable

    func testKimiExhaustedWeeklyFloorsEffectiveAvailabilityWhileRawFiveHourSurvives() {
        // Spike: Weekly 100% used / 0% remaining; 5h 0% used / 100% remaining.
        let weeklyReset = now.addingTimeInterval(151_380) // 1d 18h 3m
        let fiveHourReset = now.addingTimeInterval(3_780) // 1h 3m
        let windows = [
            used(100, source: "kimi", scope: .weekly, resetAt: weeklyReset),
            used(0, source: "kimi", scope: .fiveHour, resetAt: fiveHourReset),
        ]

        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.source, "kimi")
        XCTAssertEqual(row.effectiveRemainingPercent, 0.0)
        XCTAssertNil(row.unknownReason)

        XCTAssertEqual(row.pools.count, 1)
        XCTAssertEqual(row.pools[0].dashboardScope, .weekly)
        XCTAssertEqual(row.pools[0].dashboardRemainingPercent, 0.0)

        // Raw 5h still reachable (derive, never hide).
        guard case .known(let shortRemaining, let shortUsed, _, _, _) = row.pools[0].shortWindow else {
            return XCTFail("expected known short window, got \(row.pools[0].shortWindow)")
        }
        XCTAssertEqual(shortRemaining, 100.0)
        XCTAssertEqual(shortUsed, 0.0)

        let rawFiveHour = row.rawWindows.first { $0.scope == .fiveHour }
        XCTAssertEqual(rawFiveHour?.remainingPercent, 100.0)
        XCTAssertEqual(rawFiveHour?.usedPercent, 0.0)
    }

    // MARK: 2 — agy: two pools in one row, never duplicated

    func testAgyTwoPoolsCollapseToOneRow() {
        // Spike values: Gemini weekly 92.67% remaining / 5h 58.48%;
        // Claude/GPT weekly 60.11% remaining (no parseable 5h).
        let geminiWeeklyReset = now.addingTimeInterval(593_400) // 164h 50m
        let geminiFiveHourReset = now.addingTimeInterval(12_060) // 3h 21m
        let claudeWeeklyReset = now.addingTimeInterval(186_480) // 51h 48m
        let windows = [
            remaining(92.67, source: "agy", scope: .weekly, resetAt: geminiWeeklyReset,
                      poolLabel: "GEMINI MODELS"),
            remaining(58.48, source: "agy", scope: .fiveHour, resetAt: geminiFiveHourReset,
                      poolLabel: "GEMINI MODELS"),
            remaining(60.11, source: "agy", scope: .weekly, resetAt: claudeWeeklyReset,
                      poolLabel: "CLAUDE AND GPT MODELS"),
        ]

        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.count, 1, "two pools must not become two rows")
        let row = rows[0]
        XCTAssertEqual(row.source, "agy")
        XCTAssertEqual(row.pools.count, 2)
        XCTAssertEqual(row.pools[0].poolLabel, "GEMINI MODELS")
        XCTAssertEqual(row.pools[1].poolLabel, "CLAUDE AND GPT MODELS")

        XCTAssertEqual(row.pools[0].dashboardRemainingPercent, 92.67)
        XCTAssertEqual(row.pools[1].dashboardRemainingPercent, 60.11)

        // Tightest across every window on the source (Gemini 5h 58.48%).
        XCTAssertEqual(row.effectiveRemainingPercent, 58.48)

        guard case .known(let geminiShort, _, _, _, _) = row.pools[0].shortWindow else {
            return XCTFail("Gemini short window should be known")
        }
        XCTAssertEqual(geminiShort, 58.48)
        // Claude pool has no fiveHour sample → explicit none (not unknown).
        guard case .none = row.pools[1].shortWindow else {
            return XCTFail("Claude pool with no fiveHour sample is .none, got \(row.pools[1].shortWindow)")
        }
    }

    // MARK: 3 — Grok: no short window → explicit none, not unknown

    func testGrokHasExplicitNoneShortWindowNotUnknown() {
        // Spike: used 42% → remaining 58%; period end ~41h from sample-era now.
        let periodEnd = now.addingTimeInterval(41 * 3600)
        let windows = [
            used(42, source: "grok", scope: .weekly, resetAt: periodEnd,
                 precision: .exact, planTier: "X Premium+"),
        ]

        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.planTier, "X Premium+")
        XCTAssertEqual(row.pools[0].dashboardScope, .weekly)
        XCTAssertEqual(row.pools[0].dashboardRemainingPercent, 58.0)
        XCTAssertEqual(row.effectiveRemainingPercent, 58.0)

        guard case .none = row.pools[0].shortWindow else {
            return XCTFail("Grok short window must be .none, not unknown; got \(row.pools[0].shortWindow)")
        }
        XCTAssertNil(row.unknownReason)
    }

    // MARK: 4 — Cursor: monthly is dashboard; day precision survives

    func testCursorMonthlyIsDashboardAndDayPrecisionSurvives() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var resetComponents = DateComponents()
        resetComponents.year = 2026
        resetComponents.month = 8
        resetComponents.day = 25
        resetComponents.hour = 0
        resetComponents.minute = 0
        resetComponents.second = 0
        let resetAt = calendar.date(from: resetComponents)!

        let windows = [
            used(27, source: "cursor_agent", scope: .monthly, resetAt: resetAt,
                 precision: .day, poolLabel: "Included", planTier: "Ultra",
                 onDemand: CapacityPaidAmount(used: 0, cap: 1, remaining: 1, unit: "$")),
        ]

        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.pools[0].dashboardScope, .monthly)
        XCTAssertEqual(row.pools[0].dashboardRemainingPercent, 73.0)
        XCTAssertEqual(row.pools[0].dashboardResetPrecision, .day)
        XCTAssertEqual(row.pools[0].dashboardResetAt, resetAt)
        XCTAssertEqual(row.planTier, "Ultra")
        guard case .none = row.pools[0].shortWindow else {
            return XCTFail("Cursor has no 5h window → .none")
        }
        // Day precision must survive on the raw window too.
        XCTAssertEqual(row.rawWindows.first?.resetPrecision, .day)
    }

    // MARK: 5 — Hero eligibility: Grok 58%/41h eligible; agy Claude 60%/51h not

    func testHeroEligibilityGrokEligibleAgyClaudeOutsideFortyEightHours() {
        let grokReset = now.addingTimeInterval(41 * 3600)
        let claudeReset = now.addingTimeInterval(51 * 3600)
        let windows = [
            used(42, source: "grok", scope: .weekly, resetAt: grokReset, precision: .exact),
            remaining(60.11, source: "agy", scope: .weekly, resetAt: claudeReset,
                      poolLabel: "CLAUDE AND GPT MODELS"),
        ]

        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        let bySource = Dictionary(uniqueKeysWithValues: rows.map { ($0.source, $0) })

        XCTAssertEqual(bySource["grok"]?.isHeroEligible(at: now), true)
        XCTAssertEqual(bySource["agy"]?.isHeroEligible(at: now), false)

        // Predicate unit checks at the product numbers.
        XCTAssertTrue(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 58, resetAt: grokReset, now: now))
        XCTAssertFalse(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 60.11, resetAt: claudeReset, now: now))
    }

    // MARK: 6 — Hero boundary: strict inequalities on thresholds

    func testHeroEligibilityBoundariesAreStrict() {
        // Exactly 48h + 21% remaining → not eligible (timeLeft < 48h fails).
        XCTAssertFalse(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 21,
            resetAt: now.addingTimeInterval(CapacityBenchProjection.heroNearDeadline),
            now: now))

        // Just under 48h + 21% → eligible.
        XCTAssertTrue(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 21,
            resetAt: now.addingTimeInterval(CapacityBenchProjection.heroNearDeadline - 1),
            now: now))

        // Exactly 20% with 47h → not eligible (remaining > 20 fails; urgent needs < 24h).
        XCTAssertFalse(CapacityBenchProjection.isHeroEligible(
            remainingPercent: CapacityBenchProjection.heroNearDeadlineMinRemaining,
            resetAt: now.addingTimeInterval(47 * 3600),
            now: now))

        // 20.01% with 47h → eligible via near-deadline gate.
        XCTAssertTrue(CapacityBenchProjection.isHeroEligible(
            remainingPercent: CapacityBenchProjection.heroNearDeadlineMinRemaining + 0.01,
            resetAt: now.addingTimeInterval(47 * 3600),
            now: now))

        // Exactly 24h + 15% → not eligible (urgent needs timeLeft < 24h).
        XCTAssertFalse(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 15,
            resetAt: now.addingTimeInterval(CapacityBenchProjection.heroUrgentDeadline),
            now: now))

        // Just under 24h + 15% → eligible via urgent gate.
        XCTAssertTrue(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 15,
            resetAt: now.addingTimeInterval(CapacityBenchProjection.heroUrgentDeadline - 1),
            now: now))

        // Exactly 10% with 12h → not eligible (remaining > 10 fails).
        XCTAssertFalse(CapacityBenchProjection.isHeroEligible(
            remainingPercent: CapacityBenchProjection.heroUrgentMinRemaining,
            resetAt: now.addingTimeInterval(12 * 3600),
            now: now))

        // 10.01% with 12h → eligible.
        XCTAssertTrue(CapacityBenchProjection.isHeroEligible(
            remainingPercent: CapacityBenchProjection.heroUrgentMinRemaining + 0.01,
            resetAt: now.addingTimeInterval(12 * 3600),
            now: now))

        // Missing reset is never eligible.
        XCTAssertFalse(CapacityBenchProjection.isHeroEligible(
            remainingPercent: 90, resetAt: nil, now: now))
    }

    // MARK: 7 — No sample → unknown reason, no zeros

    func testSourceWithNoSampleCarriesUnknownReasonWithoutZeros() {
        let windows = [
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            )
        ]

        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.source, "claude_code")
        XCTAssertEqual(row.unknownReason, .neverSampled)
        XCTAssertNil(row.effectiveRemainingPercent)
        XCTAssertTrue(row.pools.isEmpty)
        // No invented zeros on the unknown window.
        XCTAssertNil(row.rawWindows.first?.remainingPercent)
        XCTAssertNil(row.rawWindows.first?.usedPercent)
        XCTAssertFalse(row.isHeroEligible(at: now))
    }

    // MARK: 8 — One row per source even when many windows arrive interleaved

    func testOneRowPerSourceNeverTwo() {
        let windows = [
            used(10, source: "kimi", scope: .weekly, resetAt: now.addingTimeInterval(1000)),
            used(50, source: "grok", scope: .weekly, resetAt: now.addingTimeInterval(2000),
                 precision: .exact),
            used(20, source: "kimi", scope: .fiveHour, resetAt: now.addingTimeInterval(500)),
            used(30, source: "grok", scope: .weekly, resetAt: now.addingTimeInterval(3000),
                 precision: .exact, observedAt: now.addingTimeInterval(10)),
        ]
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.map(\.source), ["kimi", "grok"])
        XCTAssertEqual(rows.count, 2)
    }

    // MARK: 9 — Explicit fiveHour unknown is not none

    func testFiveHourUnknownIsDistinctFromNone() {
        let windows = [
            used(40, source: "kimi", scope: .weekly, resetAt: now.addingTimeInterval(100_000)),
            CapacityWindow.unknown(
                reason: .parserFailed(observedAt: now),
                source: "kimi",
                scope: .fiveHour,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let row = CapacityBenchProjection.rows(from: windows, now: now)[0]
        guard case .unknown(let reason) = row.pools[0].shortWindow else {
            return XCTFail("parser-failed fiveHour must be .unknown, got \(row.pools[0].shortWindow)")
        }
        XCTAssertEqual(reason, .parserFailed(observedAt: now))
    }
}
