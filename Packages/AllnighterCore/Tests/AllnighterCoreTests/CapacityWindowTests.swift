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
}
