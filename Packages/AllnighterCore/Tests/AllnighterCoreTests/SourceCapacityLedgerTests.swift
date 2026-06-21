import XCTest
@testable import AllnighterCore

/// The pre-dispatch capacity gate. A source that recently hit a real capacity wall is
/// "cooling" until its reset, so readiness can route around it — without a run-path retry.
final class SourceCapacityLedgerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func obs(
        _ source: String,
        kind: CapacityObservationKind = .accountRateLimit,
        confidence: CapacitySourceConfidence = .structured,
        wakeAfter: Date? = nil,
        observedResetAt: Date? = nil
    ) -> CapacityObservation {
        CapacityObservation(kind: kind, source: source, sourceConfidence: confidence,
                            rawSnippet: "rate limited", observedAt: now,
                            observedResetAt: observedResetAt, retryAfterSeconds: nil, wakeAfter: wakeAfter)
    }

    func testRateLimitedSourceCoolsUntilWake() {
        let until = now.addingTimeInterval(3600)
        let cd = SourceCapacityLedger.cooldowns(observations: [obs("claude_code", wakeAfter: until)], now: now)
        XCTAssertEqual(cd["claude_code"]?.coolingUntil, until)
        XCTAssertEqual(SourceCapacityLedger.coolingSources(observations: [obs("claude_code", wakeAfter: until)], now: now),
                       ["claude_code"])
    }

    func testFallsBackToObservedResetWhenNoWake() {
        let reset = now.addingTimeInterval(1800)
        let cd = SourceCapacityLedger.cooldowns(observations: [obs("codex", observedResetAt: reset)], now: now)
        XCTAssertEqual(cd["codex"]?.coolingUntil, reset)
    }

    func testExpiredObservationIsNotCooling() {
        let past = now.addingTimeInterval(-60)
        XCTAssertTrue(SourceCapacityLedger.cooldowns(observations: [obs("grok", wakeAfter: past)], now: now).isEmpty,
                      "a source past its reset is ready again")
    }

    func testNoResetTimeNeverBenches() {
        XCTAssertTrue(SourceCapacityLedger.cooldowns(observations: [obs("agy")], now: now).isEmpty,
                      "never bench a source on an open-ended guess (no wake / reset)")
    }

    func testAuthAndManualDoNotCool() {
        let until = now.addingTimeInterval(3600)
        for kind in [CapacityObservationKind.authRequired, .manualRequired, .unknownCapacity] {
            XCTAssertTrue(
                SourceCapacityLedger.cooldowns(observations: [obs("x", kind: kind, wakeAfter: until)], now: now).isEmpty,
                "\(kind) needs user action, not a substitute — must not cool the source")
        }
    }

    func testUnknownConfidenceIsIgnored() {
        let until = now.addingTimeInterval(3600)
        XCTAssertTrue(
            SourceCapacityLedger.cooldowns(observations: [obs("x", confidence: .unknown, wakeAfter: until)], now: now).isEmpty,
            "an unknown-confidence parse is too noisy to bench a source")
    }

    func testLongestLiveCooldownWinsPerSource() {
        let near = now.addingTimeInterval(600)
        let far = now.addingTimeInterval(7200)
        let cd = SourceCapacityLedger.cooldowns(
            observations: [obs("claude_code", wakeAfter: near), obs("claude_code", wakeAfter: far)], now: now)
        XCTAssertEqual(cd["claude_code"]?.coolingUntil, far, "keep the source benched for the longest known window")
    }
}
