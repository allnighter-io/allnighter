import XCTest
@testable import AllnighterCore

/// Pure fixture tests for `AgyNativeCapacityProbe` — agy's print-mode JSON
/// channel (`Capacity_Native_Channels.md` §2). Fixture below is a REAL capture
/// from `agy --print "/usage" --output-format json --print-timeout 25s` on
/// the dogfood host on 2026-08-08, not an invented shape.
final class AgyNativeCapacityProbeTests: XCTestCase {

    /// Verbatim live capture. `response` is the rendered-text sibling field —
    /// present in the real payload to prove the parser must (and does) ignore
    /// it and read only `command.data.groups[]`.
    private let realPayload = #"""
    {"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t93%\t2026-08-12T19:59:49Z\nGemini Models\tFive Hour Limit Remaining\t100%\t2026-08-09T10:09:10Z\nClaude and GPT models\tWeekly Limit Remaining\t100%\t2026-08-16T04:45:30Z\nClaude and GPT models\tFive Hour Limit Remaining\t100%\t2026-08-09T10:09:10Z\n","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"command":{"name":"usage","data":{"description":"Within each group, models share a weekly limit and a 5-hour limit. Quota is consumed proportionally to the cost of the tokens. Thus, limits will last longer with shorter tasks or using more cost-effective models. The 5-hour limit smooths out aggregate demand to fairly distribute global capacity across all users, while your weekly limit is tied directly to your individual tier.","groups":[{"name":"Gemini Models","description":"Models within this group: Gemini Flash, Gemini Pro","buckets":[{"id":"gemini-weekly","name":"Weekly Limit Remaining","description":"You have used some of your weekly limit, it will fully refresh in 3 days, 14 hours.","window":"weekly","remaining_fraction":0.9319064617156982,"reset_time":"2026-08-12T19:59:49Z"},{"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-08-09T10:09:10Z"}]},{"name":"Claude and GPT models","description":"Models within this group: Claude Opus, Claude Sonnet, GPT-OSS","buckets":[{"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-08-16T04:45:30Z"},{"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-08-09T10:09:10Z"}]}]}}}
    """#

    private var fixedObservedAt: Date {
        Date(timeIntervalSince1970: 1770000000)
    }

    // MARK: - The real 4-bucket payload

    func testRealPayloadParsesIntoTwoPoolsWithWeeklyAndFiveHourWindows() throws {
        let windows = AgyNativeCapacityProbe.capacityWindows(
            fromOutput: realPayload, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.count, 4)

        let pools = Set(windows.compactMap(\.poolLabel))
        XCTAssertEqual(pools, ["Gemini Models", "Claude and GPT models"])

        let gemini = windows.filter { $0.poolLabel == "Gemini Models" }
        XCTAssertEqual(gemini.count, 2)
        XCTAssertEqual(Set(gemini.map(\.scope)), [.weekly, .fiveHour])

        let claudeGpt = windows.filter { $0.poolLabel == "Claude and GPT models" }
        XCTAssertEqual(claudeGpt.count, 2)
        XCTAssertEqual(Set(claudeGpt.map(\.scope)), [.weekly, .fiveHour])

        // This is the whole point of the slice: BOTH short windows are present,
        // where the PTY scrape reports `shortWindowNone: true` for both pools.
        let fiveHourWindows = windows.filter { $0.scope == .fiveHour }
        XCTAssertEqual(fiveHourWindows.count, 2)
        for window in fiveHourWindows {
            XCTAssertNotNil(window.remainingPercent)
            XCTAssertNotNil(window.resetAt)
        }

        // remaining_fraction is a 0…1 FRACTION, not a percent — must be *100.
        let geminiWeekly = try XCTUnwrap(gemini.first { $0.scope == .weekly })
        XCTAssertEqual(geminiWeekly.remainingPercent ?? -1, 93.19064617156982, accuracy: 1e-9)
        XCTAssertEqual(geminiWeekly.usedPercent ?? -1, 100.0 - 93.19064617156982, accuracy: 1e-9)

        // reset_time is exact ISO8601 — never day/minute-truncated.
        XCTAssertEqual(geminiWeekly.resetPrecision, .exact)
        let expectedReset = ISO8601DateFormatter().date(from: "2026-08-12T19:59:49Z")
        XCTAssertEqual(geminiWeekly.resetAt, expectedReset)

        // Provenance: native JSON channel, never the PTY tier — and never
        // presented as anything but our own acquisition metadata.
        for window in windows {
            XCTAssertEqual(window.sourceTier, .headlessJSON)
            XCTAssertEqual(window.source, "agy")
            XCTAssertNil(window.unknownReason)
        }
    }

    // MARK: - Fail closed: status

    func testNonSuccessStatusYieldsNoObservation() {
        let payload = #"{"status":"ERROR","command":{"data":{"groups":[]}}}"#
        XCTAssertTrue(
            AgyNativeCapacityProbe.capacityWindows(fromOutput: payload, observedAt: fixedObservedAt).isEmpty)
    }

    func testMissingStatusYieldsNoObservation() {
        let payload = #"{"command":{"data":{"groups":[]}}}"#
        XCTAssertTrue(
            AgyNativeCapacityProbe.capacityWindows(fromOutput: payload, observedAt: fixedObservedAt).isEmpty)
    }

    // MARK: - Fail closed: malformed / empty input never throws

    func testMalformedAndEmptyInputYieldsNoObservationWithoutThrowing() {
        for garbage in ["", "not json", "{", "null", "[]", "   \n\t  "] {
            XCTAssertTrue(
                AgyNativeCapacityProbe.capacityWindows(fromOutput: garbage, observedAt: fixedObservedAt).isEmpty,
                "must fail closed on: \(garbage)")
        }
    }

    // MARK: - Fail closed: per-bucket shape

    func testUnrecognizedWindowKindIsSkippedNotGuessed() {
        let payload = #"""
        {"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[\#
        {"window":"monthly","remaining_fraction":0.5,"reset_time":"2026-08-12T19:59:49Z"},\#
        {"window":"weekly","remaining_fraction":0.5,"reset_time":"2026-08-12T19:59:49Z"}]}]}}}
        """#
        let windows = AgyNativeCapacityProbe.capacityWindows(fromOutput: payload, observedAt: fixedObservedAt)
        XCTAssertEqual(windows.count, 1, "unrecognized window kind must be dropped, not the whole group")
        XCTAssertEqual(windows[0].scope, .weekly)
    }

    func testOutOfRangeFractionIsRefusedNotClamped() {
        for value in ["-0.1", "1.1", "140"] {
            let payload = #"""
            {"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[\#
            {"window":"weekly","remaining_fraction":\#(value),"reset_time":"2026-08-12T19:59:49Z"}]}]}}}
            """#
            XCTAssertTrue(
                AgyNativeCapacityProbe.capacityWindows(fromOutput: payload, observedAt: fixedObservedAt).isEmpty,
                "\(value) must not become a window")
        }
    }

    func testMissingOrUnparseableResetTimeIsSkipped() {
        for resetPayload in [
            #"{"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[{"window":"weekly","remaining_fraction":0.5}]}]}}}"#,
            #"{"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[{"window":"weekly","remaining_fraction":0.5,"reset_time":"not a date"}]}]}}}"#,
        ] {
            XCTAssertTrue(
                AgyNativeCapacityProbe.capacityWindows(fromOutput: resetPayload, observedAt: fixedObservedAt).isEmpty)
        }
    }

    func testGroupWithNoNameOrBucketsIsSkipped() {
        let payload = #"{"status":"SUCCESS","command":{"data":{"groups":[{"buckets":[]},{"name":"X"}]}}}"#
        XCTAssertTrue(
            AgyNativeCapacityProbe.capacityWindows(fromOutput: payload, observedAt: fixedObservedAt).isEmpty)
    }

    // MARK: - Fallback still engages

    /// A native probe against a missing binary must fail closed to `nil`
    /// (never throw, never a fabricated window), leaving `CapacityProbe.windows`
    /// free to fall through to the PTY scrape. Exercises the real acquisition
    /// entry point end to end — same law as the existing spawn-failed test,
    /// just proving the native attempt did not swallow the fallback.
    func testCapacityProbeFallsThroughToSpawnFailedWhenNativeChannelUnavailable() throws {
        #if os(macOS)
        let windows = CapacityProbe.windows(
            source: "agy",
            now: fixedObservedAt,
            timeout: 2,
            executableOverride: "/tmp/alln-agy-native-missing-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unknownReason, .spawnFailed(observedAt: fixedObservedAt))
        XCTAssertNil(windows[0].usedPercent)
        XCTAssertNil(windows[0].remainingPercent)
        #else
        throw XCTSkip("PTY probe is macOS-only")
        #endif
    }
}
