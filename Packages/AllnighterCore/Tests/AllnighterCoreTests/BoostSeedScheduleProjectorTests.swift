import Foundation
import XCTest
import AllnighterCore

final class BoostSeedScheduleProjectorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 5, minute: Int = 30) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    func testLatestMissWhenEnabledPastSeedNoEvents() {
        let now = day(2026, 8, 7, hour: 12, minute: 0)
        let receipt = BoostSeedScheduleProjector.latestReceipt(
            events: [],
            enabled: true,
            appliesTo: ["claude_code", "codex"],
            seedMinutes: 5 * 60 + 30,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(receipt?.tone, .failure)
        XCTAssertEqual(receipt?.headline, "No seed recorded this morning")
        XCTAssertFalse(receipt?.detail?.lowercased().contains("asleep") == true)
    }

    func testLatestNilBeforeSeedTime() {
        let now = day(2026, 8, 7, hour: 4, minute: 0)
        let receipt = BoostSeedScheduleProjector.latestReceipt(
            events: [],
            enabled: true,
            appliesTo: ["claude_code"],
            seedMinutes: 5 * 60 + 30,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(receipt?.tone, .neutral)
        XCTAssertEqual(receipt?.headline, "No seed recorded yet")
    }

    func testLatestSuccessFromLedger() {
        let started = day(2026, 8, 7, hour: 5, minute: 30)
        let events = [
            UtilizationSeedEvent(sourceId: "claude_code", startedAt: started, outcome: .succeeded),
            UtilizationSeedEvent(sourceId: "codex", startedAt: started.addingTimeInterval(1), outcome: .succeeded)
        ]
        let receipt = BoostSeedScheduleProjector.latestReceipt(
            events: events,
            enabled: true,
            appliesTo: ["claude_code", "codex"],
            seedMinutes: 5 * 60 + 30,
            now: day(2026, 8, 7, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(receipt?.tone, .success)
        XCTAssertTrue(receipt?.headline.contains("succeeded") == true)
        XCTAssertTrue(receipt?.detail?.contains("ready") == true)
    }

    func testLatestFailureOnMixedOutcomes() {
        let started = day(2026, 8, 7, hour: 5, minute: 30)
        let events = [
            UtilizationSeedEvent(sourceId: "claude_code", startedAt: started, outcome: .succeeded),
            UtilizationSeedEvent(sourceId: "codex", startedAt: started.addingTimeInterval(1), outcome: .rateLimited)
        ]
        let receipt = BoostSeedScheduleProjector.latestReceipt(
            events: events,
            enabled: true,
            appliesTo: ["claude_code", "codex"],
            seedMinutes: 5 * 60 + 30,
            now: day(2026, 8, 7, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(receipt?.tone, .failure)
        XCTAssertTrue(receipt?.headline.contains("problems") == true)
        XCTAssertTrue(receipt?.detail?.contains("rate-limited") == true)
    }

    func testHistoryIncludesEventDaysAndTodayMiss() {
        let older = day(2026, 8, 5, hour: 5, minute: 30)
        let events = [
            UtilizationSeedEvent(sourceId: "claude_code", startedAt: older, outcome: .succeeded)
        ]
        let history = BoostSeedScheduleProjector.history(
            events: events,
            enabled: true,
            appliesTo: ["claude_code"],
            seedMinutes: 5 * 60 + 30,
            dayCount: 7,
            now: day(2026, 8, 7, hour: 12),
            calendar: calendar
        )
        XCTAssertTrue(history.contains { $0.title == "No seed recorded this morning" })
        XCTAssertTrue(history.contains { $0.detail.contains("ready") })
        XCTAssertFalse(history.contains { $0.detail.lowercased().contains("asleep") })
    }

    func testHistoryDoesNotInventPastMisses() {
        let older = day(2026, 8, 5, hour: 5, minute: 30)
        let events = [
            UtilizationSeedEvent(sourceId: "claude_code", startedAt: older, outcome: .succeeded)
        ]
        // Before today's seed — only the Aug 5 event day, no synthetic Aug 6 miss.
        let history = BoostSeedScheduleProjector.history(
            events: events,
            enabled: true,
            appliesTo: ["claude_code"],
            seedMinutes: 5 * 60 + 30,
            dayCount: 7,
            now: day(2026, 8, 7, hour: 4),
            calendar: calendar
        )
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history[0].detail.contains("ready"))
    }

    func testDisabledHidesMissAndEmptyReceipt() {
        XCTAssertNil(BoostSeedScheduleProjector.latestReceipt(
            events: [],
            enabled: false,
            appliesTo: ["claude_code"],
            seedMinutes: 5 * 60 + 30,
            now: day(2026, 8, 7, hour: 12),
            calendar: calendar
        ))
        XCTAssertTrue(BoostSeedScheduleProjector.history(
            events: [],
            enabled: false,
            appliesTo: ["claude_code"],
            seedMinutes: 5 * 60 + 30,
            now: day(2026, 8, 7, hour: 12),
            calendar: calendar
        ).isEmpty)
    }
}
