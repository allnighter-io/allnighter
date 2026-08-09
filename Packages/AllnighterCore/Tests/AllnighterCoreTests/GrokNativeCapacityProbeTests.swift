import XCTest
@testable import AllnighterCore

/// Tests for `GrokNativeCapacityProbe` — grok's on-disk log channel
/// (`Capacity_Native_Channels.md` §2). Fixtures below are REAL bytes cut
/// verbatim from `~/.grok/logs/unified.jsonl` on the dogfood host on
/// 2026-08-09 (`realTailSegment`, `noBillingSegment`), not invented
/// payloads — `pid`/`sid` values are real process/session identifiers, not
/// secrets; no auth material is included (checked before use).
final class GrokNativeCapacityProbeTests: XCTestCase {

    // MARK: - Real fixtures

    /// The 7 real trailing lines of `unified.jsonl` on this host, in file
    /// order (not sorted by `ts` — note lines 6–7 carry an EARLIER `ts` than
    /// line 5's billing record, a real example of why "most recent" must be
    /// judged by each record's own `ts`, never by position in the file).
    /// Line 5 is the real newest `billing: fetched credits config` line.
    private let realTailSegment = #"""
    {"ts":"2026-08-09T05:55:52.239Z","src":"shell","pid":91250,"ver":"1.0.0","lvl":"info","msg":"scan_source: git sync done","ctx":{"url":"https://github.com/anthropics/claude-plugins-official.git","git_sync_ms":104}}
    {"ts":"2026-08-09T05:55:52.240Z","src":"shell","pid":91250,"ver":"1.0.0","lvl":"info","msg":"marketplace handle_list: source scanned","ctx":{"source_index":0,"source_name":"xAI Official","scan_ms":0,"plugin_count":17,"catalog_loaded":true,"components_present":17,"components_absent":0,"error":null}}
    {"ts":"2026-08-09T05:55:52.241Z","src":"shell","pid":91250,"ver":"1.0.0","lvl":"info","msg":"marketplace handle_list: source scanned","ctx":{"source_index":1,"source_name":"claude-plugins-official","scan_ms":0,"plugin_count":282,"catalog_loaded":false,"components_present":0,"components_absent":282,"error":null}}
    {"ts":"2026-08-09T05:55:52.241Z","src":"shell","pid":91250,"ver":"1.0.0","lvl":"info","msg":"marketplace handle_list: complete","ctx":{"total_ms":107}}
    {"ts":"2026-08-09T05:55:52.257Z","src":"shell","pid":91250,"ver":"1.0.0","lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":8.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-07T18:11:40.374130+00:00","end":"2026-08-14T18:11:40.374130+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true,"billingPeriodStart":"2026-08-07T18:11:40.374130+00:00","billingPeriodEnd":"2026-08-14T18:11:40.374130+00:00","historyLen":0},"onDemandEnabled":null,"subscriptionTier":"X Premium+"}}
    {"ts":"2026-08-09T05:55:52.013Z","src":"grok-pager","pid":91250,"ver":"1.0.0","lvl":"info","msg":"prompt.enqueue","ctx":{"len":6}}
    {"ts":"2026-08-09T05:55:52.134Z","src":"grok-pager","pid":91250,"ver":"1.0.0","lvl":"info","sid":"019fe517-848d-79b2-b754-0b9e8cecf31a","msg":"session.create.done","ctx":{"elapsed_ms":572,"mcp_server_count":1}}

    """#

    /// 5 real consecutive lines from the middle of the largest observed gap
    /// between billing records on this host (2026-08-02, 1,578 lines with
    /// no billing fetch) — a genuine "grok ran but never fetched billing"
    /// stretch, not a contrived one.
    private let noBillingSegment = #"""
    {"ts":"2026-08-02T04:36:02.996Z","src":"grok-pager","pid":55743,"ver":"0.2.118","lvl":"info","msg":"prompt.enqueue","ctx":{"len":6}}
    {"ts":"2026-08-02T04:36:03.284Z","src":"grok-pager","pid":55743,"ver":"0.2.118","lvl":"info","sid":"019fc0c1-ed76-7ef1-8771-18a947895bdc","msg":"session.create.done","ctx":{"elapsed_ms":736,"mcp_server_count":1}}
    {"ts":"2026-08-02T04:36:04.117Z","src":"shell","pid":55743,"ver":"0.2.118","lvl":"info","msg":"scan_source: git sync done","ctx":{"url":"https://github.com/xai-org/plugin-marketplace.git","git_sync_ms":829}}
    {"ts":"2026-08-02T04:36:04.119Z","src":"shell","pid":55743,"ver":"0.2.118","lvl":"info","msg":"marketplace handle_list: source scanned","ctx":{"source_index":0,"source_name":"xAI Official","scan_ms":0,"plugin_count":15,"catalog_loaded":true,"components_present":15,"components_absent":0,"error":null}}
    {"ts":"2026-08-02T04:36:04.213Z","src":"shell","pid":55743,"ver":"0.2.118","lvl":"info","msg":"scan_source: git sync done","ctx":{"url":"https://github.com/xai-org/plugin-marketplace.git","git_sync_ms":925}}

    """#

    private var expectedObservedAt: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-08-09T05:55:52.257Z")!
    }

    private var expectedPeriodEnd: Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: "2026-08-14T18:11:40.374130+00:00")!
    }

    /// Comfortably inside `maxAge` of the real record's `ts`.
    private var freshNow: Date {
        expectedObservedAt.addingTimeInterval(60)
    }

    // MARK: - capacityWindows(fromTailContent:) — the real record

    func testRealTailParsesToTheExpectedWindow() throws {
        let windows = try XCTUnwrap(
            GrokNativeCapacityProbe.capacityWindows(fromTailContent: realTailSegment, now: freshNow)
        )
        XCTAssertEqual(windows.count, 1)
        let window = windows[0]
        XCTAssertEqual(window.source, "grok")
        XCTAssertEqual(window.scope, .weekly)
        XCTAssertEqual(window.usedPercent ?? -1, 8.0, accuracy: 1e-9)
        XCTAssertEqual(window.remainingPercent ?? -1, 92.0, accuracy: 1e-9)
        XCTAssertEqual(window.resetAt, expectedPeriodEnd)
        XCTAssertEqual(window.resetPrecision, .exact)
        XCTAssertEqual(window.observedAt, expectedObservedAt)
        XCTAssertEqual(window.sourceTier, .onDisk)
        XCTAssertEqual(window.planTier, "X Premium+")
        XCTAssertNil(window.unknownReason)
    }

    /// The two `grok-pager` lines AFTER the billing line in file order carry
    /// an EARLIER `ts` than it. If "most recent" were judged by position
    /// rather than each record's own `ts`, this would still pick the right
    /// line by luck (billing is a distinct msg from those two) — but it
    /// proves ordering is not what selects the winner here.
    func testFileOrderIsNotUsedToPickTheLatestRecord() throws {
        let reversed = realTailSegment
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reversed()
            .joined(separator: "\n")
        let windows = try XCTUnwrap(
            GrokNativeCapacityProbe.capacityWindows(fromTailContent: reversed, now: freshNow)
        )
        XCTAssertEqual(windows[0].observedAt, expectedObservedAt)
        XCTAssertEqual(windows[0].usedPercent ?? -1, 8.0, accuracy: 1e-9)
    }

    // MARK: - No billing line in tail → no observation, never escalates

    func testTailWithNoBillingLineYieldsNoObservation() {
        XCTAssertNil(
            GrokNativeCapacityProbe.capacityWindows(fromTailContent: noBillingSegment, now: freshNow)
        )
    }

    func testEmptyTailYieldsNoObservation() {
        XCTAssertNil(GrokNativeCapacityProbe.capacityWindows(fromTailContent: "", now: freshNow))
    }

    // MARK: - Malformed JSON never throws

    func testMalformedTailYieldsNoObservationWithoutThrowing() {
        for garbage in ["", "not json", "{", "null", "[]", "   \n\t  ", "{\"msg\":\"billing: fetched credits config\""] {
            XCTAssertNil(
                GrokNativeCapacityProbe.capacityWindows(fromTailContent: garbage, now: freshNow),
                "must fail closed on: \(garbage)"
            )
        }
    }

    func testMalformedLineMixedWithRealBillingLineStillFindsTheRealOne() throws {
        let mixed = "{not json at all\n" + realTailSegment + "\n{\"ts\":\"broken"
        let windows = try XCTUnwrap(
            GrokNativeCapacityProbe.capacityWindows(fromTailContent: mixed, now: freshNow)
        )
        XCTAssertEqual(windows[0].usedPercent ?? -1, 8.0, accuracy: 1e-9)
    }

    // MARK: - Staleness: fail closed on the record's OWN ts

    func testRecordJustPastMaxAgeYieldsNoObservation() {
        let staleNow = expectedObservedAt.addingTimeInterval(GrokNativeCapacityProbe.maxAge + 1)
        XCTAssertNil(
            GrokNativeCapacityProbe.capacityWindows(fromTailContent: realTailSegment, now: staleNow)
        )
    }

    func testRecordJustInsideMaxAgeStillParses() {
        let almostStaleNow = expectedObservedAt.addingTimeInterval(GrokNativeCapacityProbe.maxAge - 1)
        XCTAssertNotNil(
            GrokNativeCapacityProbe.capacityWindows(fromTailContent: realTailSegment, now: almostStaleNow)
        )
    }

    // MARK: - Bounded tail IO: real bytes, a truncated leading line

    /// Writes the real `realTailSegment` bytes to disk and reads it back
    /// through `readTail` with a budget deliberately smaller than the whole
    /// file — computed from the fixture's own first-line length, not a
    /// hardcoded offset — so the read must start partway through the real
    /// first line. Proves the truncated leading fragment is dropped rather
    /// than either crashing or being mistaken for a record, and that the
    /// real billing line later in the same read still parses.
    func testReadTailDropsATruncatedLeadingLineAndStillFindsTheRealRecord() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("unified.jsonl")
        let data = try XCTUnwrap(realTailSegment.data(using: .utf8))
        try data.write(to: fileURL)

        let firstLine = try XCTUnwrap(
            realTailSegment.split(separator: "\n", omittingEmptySubsequences: true).first
        )
        let firstLineByteCount = try XCTUnwrap(String(firstLine).data(using: .utf8)?.count)
        XCTAssertGreaterThan(firstLineByteCount, 20, "sanity: the real first line must be long enough to slice mid-line")

        // Deliberately smaller than the whole fixture so the read must begin
        // partway through the real first line, never at its start.
        let budget = data.count - (firstLineByteCount / 2)
        let tail = try XCTUnwrap(GrokNativeCapacityProbe.readTail(url: fileURL, byteBudget: budget))

        XCTAssertFalse(
            tail.contains(String(firstLine)),
            "the truncated leading fragment must be dropped, not kept as if it were a whole line"
        )

        let windows = try XCTUnwrap(GrokNativeCapacityProbe.capacityWindows(fromTailContent: tail, now: freshNow))
        XCTAssertEqual(windows[0].usedPercent ?? -1, 8.0, accuracy: 1e-9)
        XCTAssertEqual(windows[0].observedAt, expectedObservedAt)
    }

    func testReadTailOnMissingFileYieldsNilWithoutThrowing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-missing-\(UUID().uuidString).jsonl")
        XCTAssertNil(GrokNativeCapacityProbe.readTail(url: missing, byteBudget: 1024))
    }

    func testReadTailOnEmptyFileYieldsNilWithoutThrowing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("unified.jsonl")
        try Data().write(to: fileURL)
        XCTAssertNil(GrokNativeCapacityProbe.readTail(url: fileURL, byteBudget: 1024))
    }

    /// Not a real capture — the log on this host happens to be pure ASCII
    /// (verified), so no real fixture can demonstrate this. Constructed to
    /// prove why the tail is split into lines at the byte level BEFORE
    /// decoding, rather than decoded as one whole-tail `String` and then
    /// split: a whole-tail decode fails outright (returns `nil` for
    /// EVERYTHING) if the read boundary happens to fall inside a
    /// multi-byte UTF-8 character, which would silently lose a perfectly
    /// good billing line later in the same read. Splitting on `\n` at the
    /// `Data` level first is safe because `0x0A` never appears as a lead or
    /// continuation byte of a multi-byte character, so only the corrupted
    /// fragment fails to decode — and it is dropped anyway because it is
    /// also the truncated leading line.
    func testReadTailSurvivesAReadBoundaryInsideAMultiByteCharacter() throws {
        let junkLine = #"{"ts":"2026-08-01T00:00:00.000Z","msg":"noise","note":"🚀 multi-byte marker"}"#
        let emojiRange = try XCTUnwrap(junkLine.range(of: "🚀"))
        let emojiByteOffset = junkLine.utf8.distance(from: junkLine.utf8.startIndex, to: emojiRange.lowerBound)
        // "🚀" is 4 UTF-8 bytes; +2 lands squarely inside it, never on a
        // character boundary.
        let splitPoint = emojiByteOffset + 2
        XCTAssertGreaterThan(junkLine.utf8.count, splitPoint + 1, "sanity: split point must fall before end of junk line")

        var fileData = Data(junkLine.utf8)
        fileData.append(0x0A)
        fileData.append(try XCTUnwrap(realTailSegment.data(using: .utf8)))

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-utf8-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("unified.jsonl")
        try fileData.write(to: fileURL)

        // Sanity: a naive whole-blob decode of exactly this byte range
        // fails — proving the split point really does sit mid-character.
        let naiveSlice = fileData.suffix(from: splitPoint)
        XCTAssertNil(String(data: naiveSlice, encoding: .utf8), "sanity: split point must break naive whole-blob decode")

        let budget = fileData.count - splitPoint
        let tail = try XCTUnwrap(GrokNativeCapacityProbe.readTail(url: fileURL, byteBudget: budget))
        let windows = try XCTUnwrap(GrokNativeCapacityProbe.capacityWindows(fromTailContent: tail, now: freshNow))
        XCTAssertEqual(windows[0].usedPercent ?? -1, 8.0, accuracy: 1e-9)
    }

    // MARK: - fetch(homeDirectory:) end to end, and CapacityProbe wiring

    func testFetchOnMissingFileYieldsNilWithoutThrowing() {
        let emptyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyHome) }
        XCTAssertNil(GrokNativeCapacityProbe.fetch(homeDirectory: emptyHome, now: freshNow))
    }

    func testFetchReadsARealLogPlacedAtTheExpectedPath() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-live-\(UUID().uuidString)", isDirectory: true)
        let logsDir = home.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try realTailSegment.write(
            to: logsDir.appendingPathComponent("unified.jsonl"), atomically: true, encoding: .utf8
        )

        let windows = try XCTUnwrap(GrokNativeCapacityProbe.fetch(homeDirectory: home, now: freshNow))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].usedPercent ?? -1, 8.0, accuracy: 1e-9)
        XCTAssertEqual(windows[0].sourceTier, .onDisk)
    }

    /// A native probe with no `unified.jsonl` in the given home (and no
    /// resolvable binary) must fail closed to nil, leaving
    /// `CapacityProbe.windows` free to fall through to the PTY scrape —
    /// same law as the `claude_code`/`agy` equivalents.
    func testCapacityProbeFallsThroughToSpawnFailedWhenNativeChannelUnavailable() throws {
        #if os(macOS)
        let emptyHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyHome) }

        let windows = CapacityProbe.windows(
            source: "grok",
            now: freshNow,
            timeout: 2,
            homeDirectory: emptyHome,
            executableOverride: "/tmp/alln-grok-native-missing-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unknownReason, .spawnFailed(observedAt: freshNow))
        XCTAssertNil(windows[0].usedPercent)
        #else
        throw XCTSkip("PTY probe is macOS-only")
        #endif
    }

    /// The primary acceptance case for the whole slice: given a real log on
    /// disk, `CapacityProbe.windows` must answer from the native channel —
    /// never spawning grok — and produce the exact same numbers as the pure
    /// parser test above.
    func testCapacityProbeAnswersFromNativeLogWithoutAnyExecutableResolution() throws {
        #if os(macOS)
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-grok-native-live-\(UUID().uuidString)", isDirectory: true)
        let logsDir = home.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try realTailSegment.write(
            to: logsDir.appendingPathComponent("unified.jsonl"), atomically: true, encoding: .utf8
        )

        // executableOverride deliberately points nowhere — if the native
        // channel required the grok binary at all, this call would fail
        // closed instead of answering.
        let windows = CapacityProbe.windows(
            source: "grok",
            now: freshNow,
            timeout: 2,
            homeDirectory: home,
            executableOverride: "/tmp/alln-grok-native-unused-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].sourceTier, .onDisk)
        XCTAssertEqual(windows[0].usedPercent ?? -1, 8.0, accuracy: 1e-9)
        XCTAssertEqual(windows[0].resetAt, expectedPeriodEnd)
        XCTAssertNil(windows[0].unknownReason)
        #else
        throw XCTSkip("PTY probe is macOS-only")
        #endif
    }
}
