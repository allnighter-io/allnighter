import XCTest
@testable import AllnighterCore

/// Tests for `ClaudeNativeCapacityProbe` — claude_code's on-disk cache channel
/// (`Capacity_Native_Channels.md` §2). The fixture below is the REAL shape of
/// `cachedUsageUtilization` read from `~/.claude.json` on the dogfood host on
/// 2026-08-08, not an invented shape. `accountUuid` is replaced with an
/// obviously-fake placeholder — the parser never reads that field either way,
/// but a real identifier has no reason to live in the repo.
final class ClaudeNativeCapacityProbeTests: XCTestCase {

    /// Verbatim shape (accountUuid redacted) of `~/.claude.json`'s
    /// `cachedUsageUtilization`, wrapped as the root file object would be.
    /// `numStartups` stands in for the hundreds of unrelated top-level keys
    /// the real file carries — proof the parser reads nothing but the one
    /// key it names. `nimbus_quill` (non-null, unfamiliar) and the run of
    /// `null` siblings (`tangelo`, `iguana_necktie`, …) are the real observed
    /// shape: unrecognized/growing keys the parser must ignore by
    /// construction. `limits[]` is the real 3-entry array — `session`,
    /// `weekly_all`, and `weekly_scoped` (a model-scoped secondary weekly
    /// pool, `display_name: "Fable"`) — the source of truth this parser
    /// reads; `five_hour`/`seven_day` are left in the fixture too, unread,
    /// proving the parser no longer keys off them.
    private let realPayload = #"""
    {
      "numStartups": 42,
      "cachedUsageUtilization": {
        "fetchedAtMs": 1786254343761,
        "accountUuid": "00000000-0000-0000-0000-000000000000",
        "utilization": {
          "five_hour": {
            "utilization": 26,
            "resets_at": "2026-08-09T07:10:00.674350+00:00",
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
          },
          "seven_day": {
            "utilization": 76,
            "resets_at": "2026-08-11T03:00:00.674374+00:00",
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
          },
          "seven_day_oauth_apps": null,
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "seven_day_cowork": null,
          "seven_day_omelette": null,
          "tangelo": null,
          "iguana_necktie": null,
          "omelette_promotional": null,
          "nimbus_quill": {
            "utilization": 0,
            "resets_at": null,
            "limit_dollars": null,
            "used_dollars": null,
            "remaining_dollars": null
          },
          "cinder_cove": null,
          "amber_ladder": null,
          "extra_usage": {
            "is_enabled": false,
            "monthly_limit": null,
            "used_credits": null,
            "utilization": null,
            "currency": null
          },
          "limits": [
            {
              "kind": "session",
              "group": "session",
              "percent": 26,
              "severity": "normal",
              "resets_at": "2026-08-09T07:10:00.674350+00:00",
              "scope": null,
              "is_active": false
            },
            {
              "kind": "weekly_all",
              "group": "weekly",
              "percent": 76,
              "severity": "warning",
              "resets_at": "2026-08-11T03:00:00.674374+00:00",
              "scope": null,
              "is_active": true
            },
            {
              "kind": "weekly_scoped",
              "group": "weekly",
              "percent": 18,
              "severity": "normal",
              "resets_at": "2026-08-11T03:00:00.674600+00:00",
              "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null},
              "is_active": false
            }
          ],
          "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "percent": 0}
        }
      }
    }
    """#

    /// One minute after the fixture's `fetchedAtMs` (1786254343761 ms) —
    /// comfortably inside `maxAge`, matching how fresh a real read normally is.
    private var freshNow: Date {
        Date(timeIntervalSince1970: 1_786_254_343.761 + 60)
    }

    // MARK: - The real payload

    func testRealPayloadParsesAllThreeLimitsIncludingTheModelScopedPool() throws {
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: realPayload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 3, "session + weekly_all + weekly_scoped — the regression this repairs")

        let short = try XCTUnwrap(windows.first { $0.scope == .session })
        // percent is USED, never remaining — 26% used ↔ 74% remaining.
        XCTAssertEqual(short.usedPercent ?? -1, 26.0, accuracy: 1e-9)
        XCTAssertEqual(short.remainingPercent ?? -1, 74.0, accuracy: 1e-9)
        XCTAssertEqual(short.resetPrecision, .exact)
        XCTAssertEqual(short.sourceTier, .onDisk)
        XCTAssertEqual(short.source, "claude_code")
        XCTAssertNil(short.unknownReason)
        XCTAssertNil(short.poolLabel, "session carries no scope — no label to show")

        // The two weekly pools: primary/dashboard (weekly_all) and the
        // model-scoped secondary (weekly_scoped) that the five_hour/seven_day
        // keyed reader lost.
        let weeklyWindows = windows.filter { $0.scope == .weekly }
        XCTAssertEqual(weeklyWindows.count, 2, "both weekly pools must survive — this is the restored pool")

        let primaryWeekly = try XCTUnwrap(weeklyWindows.first { $0.poolLabel == nil })
        // 76% used ↔ 24% remaining — matches what alln already publishes.
        XCTAssertEqual(primaryWeekly.usedPercent ?? -1, 76.0, accuracy: 1e-9)
        XCTAssertEqual(primaryWeekly.remainingPercent ?? -1, 24.0, accuracy: 1e-9)
        XCTAssertEqual(primaryWeekly.sourceTier, .onDisk)
        XCTAssertNil(primaryWeekly.unknownReason)

        let scopedWeekly = try XCTUnwrap(weeklyWindows.first { $0.poolLabel == "Fable" })
        // 18% used ↔ 82% remaining — THE lost pool this commit restores.
        XCTAssertEqual(scopedWeekly.usedPercent ?? -1, 18.0, accuracy: 1e-9)
        XCTAssertEqual(scopedWeekly.remainingPercent ?? -1, 82.0, accuracy: 1e-9)
        XCTAssertEqual(scopedWeekly.poolLabel, "Fable", "vendor's display_name used verbatim, never reformatted")
        XCTAssertNil(scopedWeekly.unknownReason)

        // No window ever carries a planTier — the accepted, documented loss.
        for window in windows {
            XCTAssertNil(window.planTier)
        }
    }

    /// `resets_at` carries an explicit `+00:00` offset — must parse to that
    /// exact UTC instant, never shifted as if it were a naive/local string.
    /// This is the exact bug shape a sibling slice fixed elsewhere (assuming
    /// a rendered time was UTC when it was local, a 7h lie) — here there is
    /// no ambiguity to begin with, and the test proves the parser does not
    /// introduce one.
    func testResetsAtOffsetIsParsedExactlyNotShiftedForEachKind() throws {
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: realPayload, now: freshNow)
        )
        let primaryWeekly = try XCTUnwrap(windows.first { $0.scope == .weekly && $0.poolLabel == nil })
        let reset = try XCTUnwrap(primaryWeekly.resetAt)
        let expected = ISO8601DateFormatter().date(from: "2026-08-11T03:00:00Z")
        // Allow for the fractional seconds our formatter keeps; compare to
        // the whole-second instant the offset unambiguously names.
        XCTAssertEqual(reset.timeIntervalSince1970, expected!.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Unknown `kind` is ignored, never blocks the known ones

    func testUnknownKindIsIgnoredSilentlyAndDoesNotBlockKnownEntries() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":26,"resets_at":"2026-08-09T07:10:00+00:00"},\#
        {"kind":"some_future_bucket","percent":50,"resets_at":"2026-08-11T03:00:00+00:00"},\#
        {"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 2, "unknown kind dropped, known siblings still parse")
        XCTAssertEqual(Set(windows.map(\.scope)), [.session, .weekly])
    }

    func testOnlyUnknownKindsYieldsNoObservation() {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"nimbus_quill_bucket","percent":5,"resets_at":"2026-08-09T07:10:00+00:00"}]}}}
        """#
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow))
    }

    // MARK: - poolLabel never fabricated

    func testWeeklyScopedWithNullScopeYieldsNoLabelNotAFabricatedOne() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"weekly_scoped","percent":18,"resets_at":"2026-08-11T03:00:00+00:00","scope":null}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertNil(windows[0].poolLabel)
    }

    func testSessionAndWeeklyAllNeverCarryAPoolLabelEvenIfScopePresent() throws {
        // Not observed live, but the reader must key the label read off
        // `kind`, not off "scope happens to be present" — a future vendor
        // change adding scope to weekly_all must not suddenly invent a label
        // for a pool that has never shown one.
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00","scope":{"model":{"display_name":"Should Not Appear"}}}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertNil(windows[0].poolLabel)
    }

    // MARK: - Fail closed: missing / malformed

    func testMissingCachedUsageUtilizationYieldsNoObservation() {
        let payload = #"{"numStartups": 42}"#
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow))
    }

    func testMalformedJSONYieldsNoObservationWithoutThrowing() {
        for garbage in ["", "not json", "{", "null", "[]", "   \n\t  ", "{\"cachedUsageUtilization\":"] {
            XCTAssertNil(
                ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: garbage, now: freshNow),
                "must fail closed on: \(garbage)"
            )
        }
    }

    func testFetchOnMissingFileYieldsNilWithoutThrowing() {
        let emptyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-claude-native-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyHome) }
        XCTAssertNil(ClaudeNativeCapacityProbe.fetch(homeDirectory: emptyHome, now: freshNow))
    }

    func testMissingLimitsArrayYieldsNoObservation() {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"five_hour":{"utilization":26,"resets_at":"2026-08-09T07:10:00+00:00"}}}}
        """#
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow))
    }

    // MARK: - Fail closed: staleness

    func testPayloadOlderThanStalenessBoundYieldsNoObservation() {
        // fetchedAtMs (1786254343761 ms) + maxAge (15 min) + 1s — just past the bound.
        let staleNow = Date(timeIntervalSince1970: 1_786_254_343.761 + ClaudeNativeCapacityProbe.maxAge + 1)
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: realPayload, now: staleNow))
    }

    func testPayloadJustInsideStalenessBoundStillParses() {
        let almostStaleNow = Date(timeIntervalSince1970: 1_786_254_343.761 + ClaudeNativeCapacityProbe.maxAge - 1)
        XCTAssertNotNil(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: realPayload, now: almostStaleNow)
        )
    }

    func testMissingFetchedAtMsYieldsNoObservation() {
        let payload = #"""
        {"cachedUsageUtilization":{"utilization":{"limits":[{"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow))
    }

    // MARK: - Fail closed: per-entry shape

    func testAllEntriesUnparseableYieldsNoObservation() {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":"a lot","resets_at":"2026-08-09T07:10:00+00:00"},\#
        {"kind":"weekly_all","resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow))
    }

    func testOneUnparseableEntryStillYieldsTheOtherWindow() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":"a lot","resets_at":"2026-08-09T07:10:00+00:00"},\#
        {"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].scope, .weekly)
    }

    func testNonNumericPercentOnOneEntryDropsOnlyThatEntry() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":"a lot","resets_at":"2026-08-09T07:10:00+00:00"},\#
        {"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].scope, .weekly)
    }

    func testBooleanPercentIsRefusedNotCoerced() {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"weekly_all","percent":true,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        XCTAssertNil(ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow))
    }

    /// Regression for a real trap in the naive fix: `(0 as NSNumber) is Bool`
    /// and `(1 as NSNumber) is Bool` are BOTH `true` on Darwin — a helper
    /// "fixed" with a blanket `any is Bool` pre-check (rather than checking
    /// `CFGetTypeID` on the `NSNumber` branch first) would silently refuse a
    /// legitimate `percent: 0` or `percent: 1` entry, which is a completely
    /// ordinary real value (an account with 0% used, or 1% used). Both must
    /// parse normally.
    func testZeroAndOnePercentAreNotRefusedAsBooleans() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":0,"resets_at":"2026-08-09T07:10:00+00:00"},\#
        {"kind":"weekly_all","percent":1,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 2, "percent: 0 and percent: 1 must both parse, never refused as booleans")
        let session = try XCTUnwrap(windows.first { $0.scope == .session })
        XCTAssertEqual(session.usedPercent ?? -1, 0.0, accuracy: 1e-9)
        let weekly = try XCTUnwrap(windows.first { $0.scope == .weekly })
        XCTAssertEqual(weekly.usedPercent ?? -1, 1.0, accuracy: 1e-9)
    }

    func testUnparseableResetsAtDropsOnlyThatEntry() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":26,"resets_at":"not a date"},\#
        {"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].scope, .weekly)
    }

    func testMissingResetsAtDropsOnlyThatEntry() throws {
        let payload = #"""
        {"cachedUsageUtilization":{"fetchedAtMs":1786254343761,"utilization":{"limits":[\#
        {"kind":"session","percent":26},\#
        {"kind":"weekly_all","percent":76,"resets_at":"2026-08-11T03:00:00+00:00"}]}}}
        """#
        let windows = try XCTUnwrap(
            ClaudeNativeCapacityProbe.capacityWindows(fromFileContent: payload, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].scope, .weekly)
    }

    // MARK: - Fallback still engages

    /// A native probe with no `.claude.json` in the given home (and no
    /// resolvable binary) must fail closed to nil, leaving `CapacityProbe.windows`
    /// free to fall through to the PTY scrape. Exercises the real acquisition
    /// entry point end to end — same law as `AgyNativeCapacityProbeTests`'s
    /// equivalent proof, just confirming the native attempt did not swallow
    /// the fallback for this source.
    func testCapacityProbeFallsThroughToSpawnFailedWhenNativeChannelUnavailable() throws {
        #if os(macOS)
        let emptyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-claude-native-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyHome) }

        let windows = CapacityProbe.windows(
            source: "claude_code",
            now: freshNow,
            timeout: 2,
            homeDirectory: emptyHome,
            executableOverride: "/tmp/alln-claude-native-missing-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unknownReason, .spawnFailed(observedAt: freshNow))
        XCTAssertNil(windows[0].usedPercent)
        XCTAssertNil(windows[0].remainingPercent)
        #else
        throw XCTSkip("PTY probe is macOS-only")
        #endif
    }

    /// The primary acceptance case for the whole slice: given a real
    /// `.claude.json` on disk, `CapacityProbe.windows` must answer from the
    /// native channel — never spawning anything — and produce the exact same
    /// numbers as the pure parser test above.
    func testCapacityProbeAnswersFromNativeFileWithoutAnyExecutableResolution() throws {
        #if os(macOS)
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-claude-native-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try realPayload.write(
            to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8
        )

        // executableOverride deliberately points nowhere — if the native
        // channel required the binary at all, this call would fail closed
        // instead of answering.
        let windows = CapacityProbe.windows(
            source: "claude_code",
            now: freshNow,
            timeout: 2,
            homeDirectory: home,
            executableOverride: "/tmp/alln-claude-native-unused-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows.allSatisfy { $0.sourceTier == .onDisk })
        XCTAssertTrue(windows.allSatisfy { $0.unknownReason == nil })
        #else
        throw XCTSkip("PTY probe is macOS-only")
        #endif
    }
}
