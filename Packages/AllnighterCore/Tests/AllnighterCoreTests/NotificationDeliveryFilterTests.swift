import XCTest
@testable import AllnighterCore

final class NotificationDeliveryFilterTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 920_000)

    func testMutedThreadBlocksDelivery() {
        var policy = NotificationPolicy()
        policy.mutedThreadIds.insert("t1")
        let candidate = sampleCandidate(threadId: "t1")
        XCTAssertFalse(NotificationDeliveryFilter.shouldDeliver(
            candidate: candidate, policy: policy, now: now
        ))
    }

    func testDebounceBlocksSecondDeliveryInWindow() {
        var policy = NotificationPolicy(debounceIntervalSeconds: 60)
        let candidate = sampleCandidate(threadId: "t1")
        NotificationDeliveryFilter.recordDelivery(candidate: candidate, policy: &policy, now: now)
        XCTAssertFalse(NotificationDeliveryFilter.shouldDeliver(
            candidate: candidate, policy: policy, now: now.addingTimeInterval(10)
        ))
    }

    func testQuietHoursBlocksDelivery() {
        var policy = NotificationPolicy(
            quietHoursEnabled: true,
            quietHoursStartMinutes: 0,
            quietHoursEndMinutes: 24 * 60
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 17, hour: 12, minute: 0
        ))!
        XCTAssertFalse(NotificationDeliveryFilter.shouldDeliver(
            candidate: sampleCandidate(),
            policy: policy,
            now: noon,
            calendar: calendar
        ))
    }

    func testReplyToggleDisablesCompletedEvents() {
        var policy = NotificationPolicy(notifyReplies: false)
        let candidate = NotificationCandidate(
            threadId: "t1", turnId: "w1", event: .turnCompleted,
            threadTitle: "t", occurredAt: now
        )
        XCTAssertFalse(NotificationDeliveryFilter.shouldDeliver(
            candidate: candidate, policy: policy, now: now
        ))
    }

    func testRelayEventsGatedOnFailuresAndBlockedToggle() {
        let enabledPolicy = NotificationPolicy(notifyFailuresAndBlocked: true)
        let disabledPolicy = NotificationPolicy(notifyFailuresAndBlocked: false)
        for event in [NotificationEventKind.relayNeedsAnswer, .relayStopped] {
            XCTAssertTrue(NotificationDeliveryFilter.eventEnabled(event, policy: enabledPolicy))
            XCTAssertFalse(NotificationDeliveryFilter.eventEnabled(event, policy: disabledPolicy))
        }
    }

    func testLoopParkEventsGatedOnFailuresAndBlockedToggle() {
        let enabledPolicy = NotificationPolicy(notifyFailuresAndBlocked: true)
        let disabledPolicy = NotificationPolicy(notifyFailuresAndBlocked: false)
        for event in [NotificationEventKind.loopParked, .loopResumed] {
            XCTAssertTrue(NotificationDeliveryFilter.eventEnabled(event, policy: enabledPolicy))
            XCTAssertFalse(NotificationDeliveryFilter.eventEnabled(event, policy: disabledPolicy))
        }
    }

    func testLoopParkedTitleNamesVendor() {
        let candidate = NotificationCandidate(
            threadId: "relay_1", turnId: "relay_1", event: .loopParked,
            threadTitle: "QABC", vendorDisplayName: "Claude", occurredAt: now
        )
        XCTAssertEqual(
            NotificationCopy.title(candidate: candidate, workerDisplayName: nil),
            "Loop parked — waiting on Claude"
        )
        XCTAssertEqual(
            NotificationCopy.title(
                candidate: NotificationCandidate(
                    threadId: "relay_1", turnId: "relay_1", event: .loopResumed,
                    threadTitle: "QABC", occurredAt: now
                ),
                workerDisplayName: nil
            ),
            "Loop resumed"
        )
    }

    func testRelayNeedsAnswerTitleIsExactRequiredString() {
        let candidate = NotificationCandidate(
            threadId: "t1", turnId: "relay_escalate1", event: .relayNeedsAnswer,
            threadTitle: "Delivery Loop: some doc", occurredAt: now
        )
        XCTAssertEqual(
            NotificationCopy.title(candidate: candidate, workerDisplayName: nil),
            "Delivery Loop needs an answer"
        )
    }

    func testRelayStoppedTitleIsExactRequiredString() {
        let candidate = NotificationCandidate(
            threadId: "t1", turnId: "relay_stopped", event: .relayStopped,
            threadTitle: "Delivery Loop: some doc", occurredAt: now
        )
        XCTAssertEqual(
            NotificationCopy.title(candidate: candidate, workerDisplayName: nil),
            "Delivery Loop stopped"
        )
    }

    private func sampleCandidate(threadId: String = "t1") -> NotificationCandidate {
        NotificationCandidate(
            threadId: threadId, turnId: "w1", event: .turnCompleted,
            threadTitle: "Thread", occurredAt: now
        )
    }
}
