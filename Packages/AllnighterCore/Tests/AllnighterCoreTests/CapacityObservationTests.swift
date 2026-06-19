import XCTest
@testable import AllnighterCore

final class CapacityObservationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_718_800_500)

    func testModelRoundTrips() throws {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "rate limited",
            observedAt: fixedNow,
            observedResetAt: fixedNow.addingTimeInterval(9_900),
            retryAfterSeconds: 9_900,
            wakeAfter: fixedNow.addingTimeInterval(9_900)
        )
        let data = try CoreJSON.encode(observation)
        let back = try CoreJSON.decode(CapacityObservation.self, from: data)
        XCTAssertEqual(observation, back)
    }

    func testJSONMapperUsesISO8601() {
        let iso = ISO8601DateFormatter()
        let reset = fixedNow.addingTimeInterval(3_600)
        let observation = CapacityObservation(
            kind: .cooldown,
            source: "agy",
            sourceConfidence: .structured,
            rawSnippet: "capacity exhausted",
            observedAt: fixedNow,
            observedResetAt: reset,
            retryAfterSeconds: 3_600,
            wakeAfter: reset
        )
        let json = CapacityObservationJSONMapper.map(observation, iso: iso)
        XCTAssertEqual(json.kind, "cooldown")
        XCTAssertEqual(json.observedAt, iso.string(from: fixedNow))
        XCTAssertEqual(json.observedResetAt, iso.string(from: reset))
        XCTAssertEqual(json.wakeAfter, iso.string(from: reset))
    }

    func testProviderBusyResumeReasonExists() {
        XCTAssertTrue(PendingResumeReason.allCases.contains(.providerBusy))
    }
}
