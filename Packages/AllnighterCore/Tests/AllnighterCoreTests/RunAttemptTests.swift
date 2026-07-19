import XCTest
@testable import AllnighterCore

final class RunAttemptTests: XCTestCase {
    func testLegacyTeamRunWithoutAttemptsDecodesEmpty() throws {
        let run = TeamRun(
            id: "legacy",
            prompt: "p",
            status: .queued,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let encoded = try CoreJSON.encode(run)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "attempts")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try CoreJSON.decode(TeamRun.self, from: legacy)
        XCTAssertEqual(decoded.attempts, [])
    }

    func testAttemptRoundTripsAndRedactsDiagnosticSnippet() throws {
        let attempt = RunAttempt(
            attemptNumber: 1,
            requestedSourceId: "claude_code",
            requestedModelId: "model_opus",
            resolvedSourceId: "claude_code",
            resolvedModelId: "model_opus",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            vendorSessionId: "session-1",
            selectionOrigin: "explicit",
            terminalStatus: .failed,
            reason: "capacity",
            diagnosticSnippet: "Bearer secret-token-value"
        )

        XCTAssertEqual(attempt.diagnosticSnippet, "[redacted]")
        let decoded = try CoreJSON.decode(
            RunAttempt.self,
            from: CoreJSON.encode(attempt)
        )
        XCTAssertEqual(decoded, attempt)
    }

    func testWaitingForVendorIsQueued() {
        XCTAssertEqual(RunPhase.waitingForVendor.lifecycle, .queued)
    }

    func testVendorBackoffCarriesOnlyCapacityScopeFields() throws {
        let observation = CapacityObservation(
            kind: .accountRateLimit,
            source: "claude_code",
            sourceConfidence: .structured,
            rawSnippet: "limited",
            observedAt: Date(timeIntervalSince1970: 100)
        )
        let blocker = RunBlocker(
            resource: .vendorBackoff,
            quotaScope: "claude_code/profile/default",
            wakeAfter: Date(timeIntervalSince1970: 500),
            capacityObservation: observation
        )

        XCTAssertNil(blocker.scopeRoot)
        XCTAssertNil(blocker.holderId)
        XCTAssertEqual(blocker.capacityObservation, observation)
        XCTAssertEqual(
            try CoreJSON.decode(RunBlocker.self, from: CoreJSON.encode(blocker)),
            blocker
        )
    }
}
