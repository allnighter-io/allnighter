import XCTest
import AgentOSCLI
@testable import AllnighterCore

/// PF-S00 — a probe verdict may not outlive its own evidence.
final class ProbeFreshnessGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Vendor-stated by default, so the freshness tests below are testing
    /// freshness and not accidentally testing PF-S02's inference rule.
    private func rateLimited(
        retryAfterSeconds: Int? = nil,
        confidence: CapacitySourceConfidence = .structured
    ) -> ModelSetupStatus {
        .rateLimited(observation: CapacityObservation(
            kind: .accountRateLimit, source: "kimi", sourceConfidence: confidence,
            rawSnippet: "kimi version 0.34.0", observedAt: now,
            retryAfterSeconds: retryAfterSeconds))
    }

    private func record(
        _ status: ModelSetupStatus, ageSeconds: TimeInterval, driverId: String = "kimi"
    ) -> ToolProbeRecord {
        ToolProbeRecord(
            driverId: driverId, status: status,
            lastProbeAt: now.addingTimeInterval(-ageSeconds))
    }

    /// The dogfood shape: an observation that declared "retry in an hour", still
    /// being asserted 38 hours later.
    func testVerdictExpiresOnItsOwnStatedRetryWindow() {
        let stale = record(rateLimited(retryAfterSeconds: 3600), ageSeconds: 38 * 3600)
        XCTAssertTrue(ProbeFreshnessGate.isExpired(stale, now: now))
        XCTAssertEqual(
            ProbeFreshnessGate.unassertableNegatives([stale], now: now), ["kimi": .expired])
    }

    /// Inside its own window it still counts — expiry is not "ignore limits".
    func testVerdictInsideItsRetryWindowStillCounts() {
        let fresh = record(rateLimited(retryAfterSeconds: 3600), ageSeconds: 600)
        XCTAssertFalse(ProbeFreshnessGate.isExpired(fresh, now: now))
        XCTAssertTrue(ProbeFreshnessGate.unassertableNegatives([fresh], now: now).isEmpty)
    }

    /// No stated window: the shared 30-minute clock applies.
    func testVerdictWithoutARetryWindowExpiresOnTheSharedClock() {
        let justInside = record(rateLimited(), ageSeconds: ProbeFreshnessGate.gateInterval - 60)
        let justOutside = record(rateLimited(), ageSeconds: ProbeFreshnessGate.gateInterval + 60)
        XCTAssertFalse(ProbeFreshnessGate.isExpired(justInside, now: now))
        XCTAssertTrue(ProbeFreshnessGate.isExpired(justOutside, now: now))
    }

    /// One clock, shared with capacity paint — a second constant would be a
    /// second thing to explain the moment the two disagree.
    func testFreshnessClockMatchesCapacityPaintGate() {
        XCTAssertEqual(ProbeFreshnessGate.gateInterval, 30 * 60)
    }

    /// Only observation-derived negatives age. A missing binary is a detection
    /// fact, sign-in and path confirmation are standing setup facts that name a
    /// fix, and `ready` is never decayed — decaying positives would remove
    /// working seats to fix a problem whose whole harm is seats disappearing.
    func testOnlyObservationDerivedNegativesAge() {
        XCTAssertTrue(ProbeFreshnessGate.assertsUnavailable(rateLimited()))
        XCTAssertTrue(ProbeFreshnessGate.assertsUnavailable(.probeFailed(reason: "timeout")))

        XCTAssertFalse(ProbeFreshnessGate.assertsUnavailable(.notInstalled))
        XCTAssertFalse(ProbeFreshnessGate.assertsUnavailable(.ready(version: "1")))
        XCTAssertFalse(ProbeFreshnessGate.assertsUnavailable(.installedNotProbed(version: "1")))
        XCTAssertFalse(ProbeFreshnessGate.assertsUnavailable(
            .installedNotSignedIn(LoginFlow(interactiveCommand: "c", instructions: "sign in"))))

        // A very old `ready` is still not reported as an expired negative.
        let ancientReady = record(.ready(version: "1"), ageSeconds: 38 * 3600, driverId: "claude_code")
        XCTAssertTrue(ProbeFreshnessGate.unassertableNegatives([ancientReady], now: now).isEmpty)
    }

    // MARK: - PF-S02 — a limit no vendor stated is silence, not a limit

    /// The dogfood record: `sourceConfidence: .localPolicy` on a snippet that is
    /// a version banner, not a limit message. Nothing observed it; we computed
    /// it. Fresh or not, it may not be asserted.
    func testAnInferredLimitIsNotAssertedEvenWhenFresh() {
        let fresh = record(rateLimited(confidence: .localPolicy), ageSeconds: 120)
        XCTAssertFalse(ProbeFreshnessGate.isExpired(fresh, now: now), "precondition: fresh")
        XCTAssertEqual(
            ProbeFreshnessGate.unassertableNegatives([fresh], now: now), ["kimi": .inferred])
    }

    /// `.unknown` confidence is not vendor-stated either — the guard is an
    /// allowlist of the two sourced cases, not a denylist of `.localPolicy`.
    func testUnknownConfidenceIsAlsoInferred() {
        let fresh = record(rateLimited(confidence: .unknown), ageSeconds: 120)
        XCTAssertEqual(
            ProbeFreshnessGate.unassertableNegatives([fresh], now: now), ["kimi": .inferred])
    }

    /// The control: a vendor-stated limit inside its window still gates the
    /// seat. PF-S02 withholds inference, not real limits.
    func testAVendorStatedLimitIsStillAsserted() {
        let fresh = record(rateLimited(retryAfterSeconds: 3600, confidence: .messageFallback),
                           ageSeconds: 600)
        XCTAssertTrue(ProbeFreshnessGate.unassertableNegatives([fresh], now: now).isEmpty)
    }

    /// `inferred` outranks `expired`: refreshing the clock on a verdict that was
    /// never evidence would not make it evidence, so the deeper reason wins and
    /// the surface says "capacity unknown", not "not checked recently".
    func testInferredOutranksExpiredWhenBothApply() {
        let stale = record(rateLimited(confidence: .localPolicy), ageSeconds: 38 * 3600)
        XCTAssertTrue(ProbeFreshnessGate.isExpired(stale, now: now), "precondition: also expired")
        XCTAssertEqual(
            ProbeFreshnessGate.unassertableNegatives([stale], now: now), ["kimi": .inferred])
    }

    /// A probe that actually failed is a local fact we observed, not an
    /// inference. It gates the seat until it ages out on the clock.
    func testProbeFailedIsObservedNotInferred() {
        XCTAssertFalse(ProbeFreshnessGate.isInferred(.probeFailed(reason: "timeout")))
        let fresh = record(.probeFailed(reason: "timeout"), ageSeconds: 120)
        XCTAssertTrue(ProbeFreshnessGate.unassertableNegatives([fresh], now: now).isEmpty)
    }

    /// Law: the gate is a READ-TIME view. A selection surface must never mutate
    /// the durable record — the disclosure slice needs the original timestamp to
    /// report age honestly.
    func testGateNeverMutatesTheStoredRecord() {
        let stale = record(rateLimited(retryAfterSeconds: 3600), ageSeconds: 38 * 3600)
        let before = stale
        _ = ProbeFreshnessGate.unassertableNegatives([stale], now: now)
        XCTAssertEqual(stale, before)
        XCTAssertEqual(stale.lastProbeAt, before.lastProbeAt)
    }
}
