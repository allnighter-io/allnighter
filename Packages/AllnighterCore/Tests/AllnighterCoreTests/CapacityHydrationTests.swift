import XCTest
@testable import AllnighterCore

final class CapacityHydrationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_753_900_000)
    private let older = Date(timeIntervalSince1970: 1_753_800_000)
    private let futureReset = Date(timeIntervalSince1970: 1_754_000_000)

    private func known(
        source: String,
        used: Double,
        observedAt: Date,
        pool: String? = nil
    ) -> CapacityWindow {
        CapacityWindow(
            used: used,
            source: source,
            scope: .weekly,
            resetAt: futureReset,
            resetPrecision: .minute,
            observedAt: observedAt,
            sourceTier: .tuiProbe,
            poolLabel: pool
        )
    }

    private func neverSampled(_ source: String) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: .neverSampled,
            source: source,
            scope: .weekly,
            observedAt: now,
            sourceTier: .tuiProbe
        )
    }

    private func parserFailed(_ source: String) -> CapacityWindow {
        CapacityWindow.unknown(
            reason: .parserFailed(observedAt: now),
            source: source,
            scope: .weekly,
            observedAt: now,
            sourceTier: .tuiProbe
        )
    }

    func testLiveKnownBeatsHistory() {
        let live = [known(source: "cursor_agent", used: 10, observedAt: now)]
        let history = [known(source: "cursor_agent", used: 50, observedAt: older)]
        let out = CapacityHydration.apply(live: live, history: history, now: now)
        let cursor = out.filter { $0.source == "cursor_agent" }
        XCTAssertEqual(cursor.count, 1)
        XCTAssertEqual(cursor[0].usedPercent, 10)
        XCTAssertEqual(cursor[0].observedAt, now)
    }

    func testNeverSampledHydratesHistoryWithRealAge() {
        let live = [neverSampled("cursor_agent"), neverSampled("kimi")]
        let history = [
            known(source: "cursor_agent", used: 28, observedAt: older),
            known(source: "kimi", used: 100, observedAt: older),
        ]
        let out = CapacityHydration.apply(live: live, history: history, now: now)
        let cursor = out.first { $0.source == "cursor_agent" }
        XCTAssertEqual(cursor?.usedPercent, 28)
        XCTAssertEqual(cursor?.observedAt, older)
        XCTAssertNil(cursor?.unknownReason)
        let kimi = out.first { $0.source == "kimi" }
        XCTAssertEqual(kimi?.usedPercent, 100)
        XCTAssertEqual(kimi?.remainingPercent, 0)
        XCTAssertEqual(kimi?.observedAt, older)
    }

    func testParserFailedFallsBackToHistoryWhenNotSuppressed() {
        // Bare / unprobed path: history is honest last-known with real age.
        let live = [parserFailed("claude_code")]
        let history = [known(source: "claude_code", used: 48, observedAt: older)]
        let out = CapacityHydration.apply(live: live, history: history, now: now)
        let claude = out.first { $0.source == "claude_code" }
        XCTAssertEqual(claude?.usedPercent, 48)
        XCTAssertEqual(claude?.observedAt, older)
        XCTAssertNil(claude?.unknownReason)
    }

    func testRefreshFailureDoesNotHydrateHistoryAsLive() {
        // Failed current attempt must keep the failure — not paint history as live.
        let live = [parserFailed("claude_code")]
        let history = [known(source: "claude_code", used: 48, observedAt: older)]
        let out = CapacityHydration.apply(
            live: live,
            history: history,
            now: now,
            suppressHistoryForSources: ["claude_code"]
        )
        let claude = out.first { $0.source == "claude_code" }
        XCTAssertEqual(claude?.unknownReason, .parserFailed(observedAt: now))
        XCTAssertNil(claude?.usedPercent)
        XCTAssertTrue(CapacityHydration.isFailedAttempt(live))
    }

    func testNoHistoryKeepsNeverSampled() {
        let live = [neverSampled("agy")]
        let out = CapacityHydration.apply(live: live, history: [], now: now)
        XCTAssertEqual(out.first { $0.source == "agy" }?.unknownReason, .neverSampled)
    }

    func testClosedHistoryIsNotHydrated() {
        let closedReset = Date(timeIntervalSince1970: 1_753_000_000)
        let history = [
            CapacityWindow(
                used: 10,
                source: "cursor_agent",
                scope: .weekly,
                resetAt: closedReset,
                resetPrecision: .day,
                observedAt: older,
                sourceTier: .tuiProbe
            ),
        ]
        let live = [neverSampled("cursor_agent")]
        let out = CapacityHydration.apply(live: live, history: history, now: now)
        XCTAssertEqual(out.first { $0.source == "cursor_agent" }?.unknownReason, .neverSampled)
    }

    func testMultiPoolHistoryPreserved() {
        let live = [neverSampled("agy")]
        let history = [
            known(source: "agy", used: 10, observedAt: older, pool: "GEMINI MODELS"),
            known(source: "agy", used: 48, observedAt: older, pool: "CLAUDE AND GPT MODELS"),
        ]
        let out = CapacityHydration.apply(live: live, history: history, now: now)
        let agy = out.filter { $0.source == "agy" }
        XCTAssertEqual(agy.count, 2)
        XCTAssertEqual(Set(agy.compactMap(\.poolLabel)).count, 2)
    }

    func testTargetedSiblingNeverSampledHydrates() {
        // Live: cursor ok, kimi neverSampled (unprobed sibling).
        let live = [
            known(source: "cursor_agent", used: 28, observedAt: now),
            neverSampled("kimi"),
        ]
        let history = [known(source: "kimi", used: 100, observedAt: older)]
        let out = CapacityHydration.apply(live: live, history: history, now: now)
        XCTAssertEqual(out.first { $0.source == "cursor_agent" }?.usedPercent, 28)
        XCTAssertEqual(out.first { $0.source == "kimi" }?.usedPercent, 100)
        XCTAssertEqual(out.first { $0.source == "kimi" }?.observedAt, older)
    }
}
