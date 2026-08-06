import XCTest
@testable import AllnighterCore

final class CapacityClassifierTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_718_800_500)

    private func input(
        sourceId: String = "claude_code",
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32? = 1
    ) -> CapacityClassifier.Input {
        CapacityClassifier.Input(
            workerId: "model_opus",
            sourceId: sourceId,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            observedAt: fixedNow
        )
    }

    func testClaudeRateLimitStructured() {
        let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"You've been rate limited","retry_after":9900}}"#
        let obs = CapacityClassifier.classify(input(stderr: stderr))
        XCTAssertEqual(obs?.kind, .accountRateLimit)
        XCTAssertEqual(obs?.source, "claude_code")
        XCTAssertEqual(obs?.sourceConfidence, .structured)
        XCTAssertEqual(obs?.retryAfterSeconds, 9_900)
        XCTAssertNotNil(obs?.observedResetAt)
        XCTAssertNotNil(obs?.wakeAfter)
        XCTAssertFalse(obs?.rawSnippet.lowercased().contains("prompt") ?? true)
    }

    func testClaudeOverloadedStructured() {
        let stderr = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let obs = CapacityClassifier.classify(input(stderr: stderr))
        XCTAssertEqual(obs?.kind, .providerBusy)
        XCTAssertEqual(obs?.sourceConfidence, .structured)
        // VSI-S03: the vendor stated no retry, so we state none. This test used
        // to assert 60s and a wake derived from it — both were invented by a
        // deleted `providerBusyBackoffSeconds` constant, and asserting them
        // pinned the defect in place.
        XCTAssertNil(obs?.retryAfterSeconds, "no vendor retry means no retry")
        XCTAssertNil(obs?.observedResetAt)
        XCTAssertNil(obs?.wakeAfter, "no invented wake on the observation")
    }

    func testCodexJSONLErrorUsageLimit() {
        let stdout = #"{"type":"error","message":"usage_limit_reached","resetsAt":"2026-06-19T12:00:00Z"}"#
        let obs = CapacityClassifier.classify(input(sourceId: "codex", stdout: stdout))
        XCTAssertEqual(obs?.kind, .accountRateLimit)
        XCTAssertEqual(obs?.source, "codex")
        XCTAssertEqual(obs?.sourceConfidence, .structured)
        XCTAssertNotNil(obs?.observedResetAt)
    }

    func testCodexTurnFailedUsageLimit() {
        let stdout = #"{"type":"turn.failed","error":{"message":"Usage limit reached for this billing period"}}"#
        let obs = CapacityClassifier.classify(input(sourceId: "codex", stdout: stdout))
        XCTAssertEqual(obs?.kind, .accountRateLimit)
        XCTAssertEqual(obs?.sourceConfidence, .structured)
    }

    func testAGYCooldownUntilTimestamp() {
        let stderr = "capacity exhausted: cooldown active until 2026-06-19T12:00:00Z"
        let obs = CapacityClassifier.classify(input(sourceId: "agy", stderr: stderr))
        XCTAssertEqual(obs?.kind, .cooldown)
        XCTAssertEqual(obs?.sourceConfidence, .structured)
        XCTAssertNotNil(obs?.observedResetAt)
        XCTAssertNotNil(obs?.wakeAfter)
    }

    func testAuthRequiredBlocker() {
        let stderr = "Error: not signed in — please run /login"
        let obs = CapacityClassifier.classify(input(stderr: stderr))
        XCTAssertEqual(obs?.kind, .authRequired)
        XCTAssertEqual(obs?.sourceConfidence, .messageFallback)
        XCTAssertNil(obs?.observedResetAt)
        XCTAssertNil(obs?.wakeAfter)
        XCTAssertTrue(obs?.rawSnippet.contains("not signed in") ?? false)
    }

    func testClaudeInitOnStdoutAloneIsNotAuthRequired() {
        let stdout = #"{"type":"system","subtype":"init","cwd":"/repo","session_id":"abc","tools":["Read","Write"]}"#
        let obs = CapacityClassifier.classify(input(stdout: stdout))
        XCTAssertNil(obs)
    }

    func testUnauthorizedProseOnStdoutIsNotAuthRequired() {
        let stdout = """
        {"type":"system","subtype":"init","cwd":"/repo","session_id":"abc","tools":["Read"]}
        Checking whether the route returns unauthorized for anonymous users.
        """
        let obs = CapacityClassifier.classify(input(stdout: stdout))
        XCTAssertNil(obs)
    }

    func testAuthOnStderrStillClassifiesWhenStdoutHasInit() {
        let stdout = #"{"type":"system","subtype":"init","cwd":"/repo","session_id":"abc"}"#
        let stderr = "Error: not signed in — please run /login"
        let obs = CapacityClassifier.classify(input(stdout: stdout, stderr: stderr))
        XCTAssertEqual(obs?.kind, .authRequired)
        XCTAssertTrue(obs?.rawSnippet.contains("not signed in") ?? false)
        XCTAssertFalse(obs?.rawSnippet.contains("subtype") ?? true)
    }

    func testManualRequiredBlocker() {
        let stderr = "awaiting manual paste from user"
        let obs = CapacityClassifier.classify(input(stderr: stderr))
        XCTAssertEqual(obs?.kind, .manualRequired)
        XCTAssertNil(obs?.wakeAfter)
    }

    /// Renamed in intent, not just in fact: this used to assert a wake the
    /// classifier invented, under a name claiming "no estimate". VSI-S03 made
    /// the name true — an unsourced capacity fact carries no numbers at all.
    /// The local recheck cadence is the SCHEDULER's job (§10.2 rule 2), not the
    /// observation's.
    func testNoEstimateCarriesNoInventedNumbers() {
        let stderr = "rate limited — try again later"
        let obs = CapacityClassifier.classify(input(stderr: stderr))
        XCTAssertEqual(obs?.kind, .unknownCapacity)
        XCTAssertNotEqual(obs?.sourceConfidence, .structured)
        XCTAssertNil(obs?.observedResetAt)
        XCTAssertNil(obs?.retryAfterSeconds)
        XCTAssertNil(obs?.wakeAfter)
    }

    func testNoFalsePositiveOnGenericFailure() {
        let stderr = "weird failure: syntax error in config"
        XCTAssertNil(CapacityClassifier.classify(input(stderr: stderr)))
    }

    func testClaudeSessionLimitWithTimezoneIsParkable() throws {
        let stderr = "You've hit your session limit · resets 4:20pm (Europe/Madrid)"
        let obs = try XCTUnwrap(CapacityClassifier.classify(input(stderr: stderr)))
        XCTAssertEqual(obs.kind, .accountRateLimit)
        XCTAssertEqual(obs.sourceConfidence, .messageFallback)
        XCTAssertGreaterThan(try XCTUnwrap(obs.observedResetAt), fixedNow)
        XCTAssertTrue(VendorBackoffPolicy.shouldPark(obs))
    }

    func testModelDiscussionOfRateLimitsDoesNotPark() {
        let stdout = """
        Rate limits are quota controls. A model may discuss a session limit,
        but that prose is not evidence that this run hit one.
        """
        let obs = CapacityClassifier.classify(input(stdout: stdout, exitCode: 0))
        XCTAssertFalse(obs.map(VendorBackoffPolicy.shouldPark) ?? false)
    }

    func testRedactsBearerTokenInSnippet() {
        let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"Bearer sk-abcdefghijklmnopqrstuvwxyz123456"}}"#
        let obs = CapacityClassifier.classify(input(stderr: stderr))
        XCTAssertEqual(obs?.rawSnippet.contains("sk-"), false)
        XCTAssertTrue(obs?.rawSnippet.contains("[redacted]") ?? false)
    }

    func testEmitsNoForecastFields() throws {
        let stderr = #"{"type":"error","error":{"type":"rate_limit_error","message":"limited","retry_after":120}}"#
        let obs = try XCTUnwrap(CapacityClassifier.classify(input(stderr: stderr)))
        let blob = String(decoding: try CoreJSON.encode(obs), as: UTF8.self).lowercased()
        XCTAssertFalse(blob.contains("quota"))
        XCTAssertFalse(blob.contains("cost"))
        XCTAssertFalse(blob.contains("runtime"))
        XCTAssertFalse(blob.contains("token"))
    }

    func testGrokPaymentRequiredUsageBalanceExhausted() throws {
        let stderr = "402 Payment Required: Grok Build usage balance exhausted"
        let obs = try XCTUnwrap(CapacityClassifier.classify(input(sourceId: "grok", stderr: stderr)))
        XCTAssertEqual(obs.kind, .accountRateLimit)
        // Was .localPolicy only because an invented wake tripped
        // makeObservation's downgrade. With no invented wake, the honest
        // derivation label stands: this came from matching text.
        XCTAssertEqual(obs.sourceConfidence, .messageFallback)
        XCTAssertNil(obs.retryAfterSeconds)
        XCTAssertTrue(obs.rawSnippet.lowercased().contains("payment required"))
    }

    func testGrok402JSON() throws {
        let stdout = #"{"http_status":402,"message":"Grok Build usage balance exhausted"}"#
        let obs = try XCTUnwrap(CapacityClassifier.classify(input(sourceId: "grok", stdout: stdout)))
        XCTAssertEqual(obs.kind, .accountRateLimit)
        XCTAssertEqual(obs.sourceConfidence, .structured)
        XCTAssertTrue(obs.rawSnippet.lowercased().contains("balance exhausted"))
    }
}
