import XCTest
@testable import AllnighterCore

final class VendorContinuityPresentationTests: XCTestCase {
    func testWaitStatusNeverInventClock() {
        XCTAssertEqual(
            VendorContinuityPresentation.waitStatus(vendorDisplayName: "Claude"),
            "Waiting for Claude"
        )
    }

    func testMorningReceiptCountsAutomaticResumesOnly() {
        let parkedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let resumedAt = parkedAt.addingTimeInterval(3_600)
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "rate limited",
            observedAt: parkedAt,
            observedResetAt: resumedAt,
            wakeAfter: resumedAt
        )
        var run = TeamRun(
            id: "r1",
            prompt: "p",
            status: .done,
            createdAt: parkedAt,
            attempts: [
                RunAttempt(
                    attemptNumber: 1,
                    startedAt: parkedAt.addingTimeInterval(-60),
                    endedAt: parkedAt,
                    capacityObservation: observation
                ),
                RunAttempt(
                    attemptNumber: 2,
                    startedAt: resumedAt,
                    selectionOrigin: MorningReceipt.automaticResumeOrigin
                ),
            ]
        )
        let receipt = MorningReceipt.project(
            runs: [run],
            since: parkedAt.addingTimeInterval(-10),
            until: resumedAt.addingTimeInterval(10)
        )
        XCTAssertEqual(receipt.vendorWaitSecondsCovered, 3_600)
        XCTAssertEqual(receipt.runsResumedWithoutIntervention, 1)
        XCTAssertTrue(receipt.humanSummary.contains("1h 0m"))
        XCTAssertTrue(receipt.humanSummary.contains("without intervention"))
    }

    func testResetCountdownUnder24h() {
        let now = Date()
        let future = now.addingTimeInterval(23 * 3_600 + 59 * 60) // 23h 59m
        let result = VendorContinuityPresentation.resetDisplayTime(future, now: now)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.hasPrefix("in "))
        XCTAssertTrue(result!.contains("h"))
    }

    func testResetDateFormatBeyond24h() {
        let now = Date()
        let future = now.addingTimeInterval(24 * 3_600 + 60) // 24h 1m
        let result = VendorContinuityPresentation.resetDisplayTime(future, now: now)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.hasPrefix("in "), "should use dated form, not countdown")
    }

    func testResetPastReturnsNil() {
        let now = Date()
        let past = now.addingTimeInterval(-3 * 3_600) // 3h ago
        XCTAssertNil(VendorContinuityPresentation.resetDisplayTime(past, now: now))
    }
}
