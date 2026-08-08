import XCTest
import AgentOSCLI
@testable import AllnighterCore

/// PF-S00 — a probe verdict may not outlive its own evidence.
final class ProbeFreshnessGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func rateLimited(retryAfterSeconds: Int? = nil) -> ModelSetupStatus {
        .rateLimited(observation: CapacityObservation(
            kind: .accountRateLimit, source: "kimi", sourceConfidence: .localPolicy,
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
            ProbeFreshnessGate.expiredNegativeDriverIds([stale], now: now), ["kimi"])
    }

    /// Inside its own window it still counts — expiry is not "ignore limits".
    func testVerdictInsideItsRetryWindowStillCounts() {
        let fresh = record(rateLimited(retryAfterSeconds: 3600), ageSeconds: 600)
        XCTAssertFalse(ProbeFreshnessGate.isExpired(fresh, now: now))
        XCTAssertTrue(ProbeFreshnessGate.expiredNegativeDriverIds([fresh], now: now).isEmpty)
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
        XCTAssertTrue(ProbeFreshnessGate.expiredNegativeDriverIds([ancientReady], now: now).isEmpty)
    }

    /// Law: the gate is a READ-TIME view. A selection surface must never mutate
    /// the durable record — the disclosure slice needs the original timestamp to
    /// report age honestly.
    func testGateNeverMutatesTheStoredRecord() {
        let stale = record(rateLimited(retryAfterSeconds: 3600), ageSeconds: 38 * 3600)
        let before = stale
        _ = ProbeFreshnessGate.expiredNegativeDriverIds([stale], now: now)
        XCTAssertEqual(stale, before)
        XCTAssertEqual(stale.lastProbeAt, before.lastProbeAt)
    }
}
