import XCTest
@testable import AllnighterCore

final class VendorBackoffPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func observation(
        kind: CapacityObservationKind = .accountRateLimit,
        confidence: CapacitySourceConfidence = .structured,
        resetAt: Date? = nil,
        retryAfterSeconds: Int? = nil
    ) -> CapacityObservation {
        CapacityObservation(
            kind: kind,
            source: "claude_code",
            sourceConfidence: confidence,
            rawSnippet: "session limit",
            observedAt: now,
            observedResetAt: resetAt,
            retryAfterSeconds: retryAfterSeconds,
            wakeAfter: resetAt
        )
    }

    func testStructuredAccountLimitParksEvenWithoutKnownReset() {
        XCTAssertTrue(VendorBackoffPolicy.shouldPark(observation()))
        XCTAssertNil(VendorBackoffPolicy.computeWakeAfter(
            from: observation(), now: now, jitter: { 60 }
        ))
    }

    func testMessageFallbackRequiresSourcedResetOrRetryAfter() {
        XCTAssertFalse(VendorBackoffPolicy.shouldPark(
            observation(confidence: .messageFallback)
        ))
        XCTAssertTrue(VendorBackoffPolicy.shouldPark(
            observation(confidence: .messageFallback, retryAfterSeconds: 300)
        ))
    }

    func testNeverParksBusyCooldownOrUnknownCapacity() {
        for kind in [
            CapacityObservationKind.providerBusy,
            .cooldown,
            .unknownCapacity,
            .authRequired,
            .manualRequired,
        ] {
            XCTAssertFalse(VendorBackoffPolicy.shouldPark(
                observation(kind: kind, resetAt: now.addingTimeInterval(600))
            ))
        }
    }

    func testWakeAddsTwoMinutePadAndJitter() {
        let reset = now.addingTimeInterval(600)
        let wake = VendorBackoffPolicy.computeWakeAfter(
            from: observation(resetAt: reset),
            now: now,
            jitter: { 60 }
        )
        XCTAssertEqual(wake, reset.addingTimeInterval(180))
    }

    func testJitterIsClampedToOneThroughFiveMinutes() {
        let reset = now.addingTimeInterval(600)
        XCTAssertEqual(
            VendorBackoffPolicy.computeWakeAfter(
                from: observation(resetAt: reset), now: now, jitter: { 0 }
            ),
            reset.addingTimeInterval(180)
        )
        XCTAssertEqual(
            VendorBackoffPolicy.computeWakeAfter(
                from: observation(resetAt: reset), now: now, jitter: { 999 }
            ),
            reset.addingTimeInterval(420)
        )
    }

    func testPastAndAbsurdResetUseUnknownPath() {
        XCTAssertNil(VendorBackoffPolicy.computeWakeAfter(
            from: observation(resetAt: now.addingTimeInterval(-1)),
            now: now,
            jitter: { 60 }
        ))
        XCTAssertNil(VendorBackoffPolicy.computeWakeAfter(
            from: observation(resetAt: now.addingTimeInterval(
                VendorBackoffPolicy.maximumResetDistanceSeconds + 1
            )),
            now: now,
            jitter: { 60 }
        ))
    }
}
