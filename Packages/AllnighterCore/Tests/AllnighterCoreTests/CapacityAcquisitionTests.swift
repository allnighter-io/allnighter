import XCTest
@testable import AllnighterCore

/// Disk acquisition tests. Every case uses an isolated temp home — never `~`.
final class CapacityAcquisitionTests: XCTestCase {

    private var homeRoot: URL!
    private let now = Date(timeIntervalSince1970: 1_753_833_600) // ~2026-07-30 00:48 UTC

    override func setUp() {
        super.setUp()
        homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-acq-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: homeRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: homeRoot)
        homeRoot = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private let codexPlusLine = #"""
    {"timestamp":"2026-07-28T12:09:28.472Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":26983,"cached_input_tokens":0,"output_tokens":300,"total_tokens":27283},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":52.0,"window_minutes":10080,"resets_at":1785904336},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    private let codexOlderLine = #"""
    {"timestamp":"2026-07-20T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1785000000},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"plan_type":"plus"}}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    private let grokBillingLine = #"""
    {"ts":"2026-07-30T00:48:39.329Z","src":"shell","pid":55275,"ver":"0.2.114","lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":42.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-24T18:11:40.374130+00:00","end":"2026-07-31T18:11:40.374130+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true,"billingPeriodStart":"2026-07-24T18:11:40.374130+00:00","billingPeriodEnd":"2026-07-31T18:11:40.374130+00:00","historyLen":0},"onDemandEnabled":null,"subscriptionTier":"X Premium+"}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    private let grokOlderBillingLine = #"""
    {"ts":"2026-07-17T12:00:00.000Z","src":"shell","pid":1,"ver":"0.2.100","lvl":"info","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":41.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-10T18:11:40.374130+00:00","end":"2026-07-17T18:11:40.374130+00:00"},"onDemandCap":{"val":500},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true},"onDemandEnabled":null,"subscriptionTier":"X Premium+"}}
    """#.trimmingCharacters(in: .whitespacesAndNewlines)

    private func writeCodexRollout(
        year: String,
        month: String,
        day: String,
        name: String,
        content: String,
        mtime: Date? = nil
    ) throws {
        let dir = homeRoot
            .appendingPathComponent(".codex/sessions/\(year)/\(month)/\(day)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        if let mtime {
            try FileManager.default.setAttributes(
                [.modificationDate: mtime],
                ofItemAtPath: url.path
            )
        }
    }

    private func writeGrokLog(_ content: String) throws {
        let dir = homeRoot.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("unified.jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Codex

    func testCodexDiskFilesAreIgnoredOnBarePath() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let codex = windows.first { $0.source == "codex" }
        XCTAssertEqual(codex?.unknownReason, .neverSampled)
        XCTAssertNil(codex?.usedPercent, "disk logs are not capacity display (CWB-S00)")
    }

    func testCodexMissingSessionsIsNeverSampledNotZero() {
        // No .codex tree at all.
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let codex = windows.first { $0.source == "codex" }
        XCTAssertNotNil(codex)
        XCTAssertEqual(codex?.unknownReason, .neverSampled)
        XCTAssertNil(codex?.usedPercent)
        XCTAssertNil(codex?.remainingPercent)
    }

    func testCodexEmptyFileOnDiskDoesNotAffectBarePath() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-00-00-empty.jsonl",
            content: "\n\n",
            mtime: now
        )
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let codex = windows.first { $0.source == "codex" }
        XCTAssertEqual(codex?.unknownReason, .neverSampled)
        XCTAssertNil(codex?.usedPercent)
    }

    func testCodexDiskGarbageDoesNotAffectBarePath() throws {
        // Newest file is garbage; older file has a good record.
        try writeCodexRollout(
            year: "2026", month: "07", day: "29",
            name: "rollout-2026-07-29T18-00-00-junk.jsonl",
            content: "{\"type\":\"noise\"}\nnot json\n",
            mtime: Date(timeIntervalSince1970: 1_753_800_000)
        )
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-good.jsonl",
            content: codexPlusLine + "\n",
            mtime: Date(timeIntervalSince1970: 1_753_700_000)
        )
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let codex = windows.first { $0.source == "codex" }
        XCTAssertEqual(codex?.unknownReason, .neverSampled)
        XCTAssertNil(codex?.usedPercent)
    }

    // MARK: - Grok

    func testGrokDiskLogIsIgnoredOnBarePath() throws {
        let body = [
            #"{"ts":"2026-07-30T00:00:00.000Z","msg":"session start"}"#,
            grokOlderBillingLine,
            grokBillingLine,
            "",
        ].joined(separator: "\n")
        try writeGrokLog(body)

        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let grok = windows.first { $0.source == "grok" }
        XCTAssertEqual(grok?.unknownReason, .neverSampled)
        XCTAssertNil(grok?.usedPercent)
    }

    func testGrokBackwardsReaderFindsMatchAcrossChunkBoundary() throws {
        // Force small chunks so the billing line straddles a read boundary.
        let prefix = String(repeating: "x", count: 100) // non-json noise line
        // Build: many noise lines + billing near end
        var lines: [String] = []
        for i in 0..<50 {
            lines.append(
                #"{"ts":"2026-07-30T00:00:\#(String(format: "%02d", i % 60)).000Z","msg":"noise \#(i)","pad":""# +
                String(repeating: "n", count: 80) + #""}"#
            )
        }
        lines.append(grokOlderBillingLine)
        lines.append(prefix + String(repeating: "y", count: 200))
        lines.append(grokBillingLine)
        try writeGrokLog(lines.joined(separator: "\n") + "\n")

        let url = homeRoot.appendingPathComponent(".grok/logs/unified.jsonl")
        let got = GrokCapacityLog.latestWeeklyWindowReadingBackwards(from: url, chunkSize: 128)
        XCTAssertEqual(got?.usedPercent, 42.0)
        XCTAssertEqual(got?.subscriptionTier, "X Premium+")
        // Older 41% / non-zero on-demand must not win.
        XCTAssertEqual(got?.onDemandCap, 0)
    }

    func testGrokMissingLogIsNeverSampled() {
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let grok = windows.first { $0.source == "grok" }
        XCTAssertEqual(grok?.unknownReason, .neverSampled)
        XCTAssertNil(grok?.usedPercent)
    }

    func testGrokEmptyLogOnDiskDoesNotAffectBarePath() throws {
        try writeGrokLog("")
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let grok = windows.first { $0.source == "grok" }
        XCTAssertEqual(grok?.unknownReason, .neverSampled)
        XCTAssertNil(grok?.remainingPercent)
    }

    // MARK: - Tier 3

    /// PTY-only seats are `neverSampled` when no refresh. Disk-only seats with no
    /// files are also neverSampled — never vendorExposesNothing.
    func testTier3SourcesReportNeverSampledNotVendorGap() {
        // Use empty homeRoot so codex/grok disk adapters also yield neverSampled.
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let bySource = Dictionary(grouping: windows, by: \.source)

        for source in CapacityAcquisition.ptyOnlySources {
            let group = bySource[source] ?? []
            XCTAssertEqual(group.count, 1, source)
            XCTAssertEqual(group[0].unknownReason, .neverSampled, source)
            XCTAssertNotEqual(
                group[0].unknownReason, .vendorExposesNothing,
                "\(source) has a usage surface we simply have not probed"
            )
            XCTAssertNil(group[0].usedPercent, source)
            XCTAssertNil(group[0].remainingPercent, source)
            XCTAssertEqual(group[0].sourceTier, .tuiProbe, source)
        }
        // Codex + Grok: no disk files → fall back to neverSampled too.
        for source in ["codex", "grok"] {
            let group = bySource[source] ?? []
            XCTAssertEqual(group.count, 1, source)
            XCTAssertEqual(group[0].unknownReason, .neverSampled, source)
            XCTAssertNil(group[0].usedPercent, source)
        }
    }

    func testWindowsNeverThrowAndCoverBenchSources() {
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let sources = Set(windows.map(\.source))
        for expected in CapacityAcquisition.benchSourceOrder {
            XCTAssertTrue(sources.contains(expected), "missing \(expected)")
        }
        // No zeros invented for unknowns.
        for w in windows where w.unknownReason != nil {
            XCTAssertNil(w.usedPercent)
            XCTAssertNil(w.remainingPercent)
        }
    }

    func testCombinedBenchBarePathNeverReadsDisk() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        try writeGrokLog(grokBillingLine + "\n")

        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        XCTAssertEqual(
            windows.filter { $0.unknownReason == .neverSampled }.count,
            CapacityAcquisition.benchSourceOrder.count
        )
        XCTAssertTrue(
            windows.allSatisfy { $0.unknownReason != .vendorExposesNothing },
            "no seat may claim the vendor exposes nothing while we ship a parser for it"
        )
    }

    // MARK: - CAP-S08 tier-3 probe seam

    /// Counting executor — proves bare capacity never invokes a probe.
    private final class CountingProbeExecutor: CapacityProbeExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] {
            lock.lock(); defer { lock.unlock() }
            return _calls
        }
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            lock.lock(); _calls.append(request.source); lock.unlock()
            return [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    /// Fixture executor — returns canned windows per source (or empty / vendor-gap).
    private struct FixtureProbeExecutor: CapacityProbeExecuting {
        let results: [String: [CapacityWindow]]
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            results[request.source] ?? [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: request.now),
                    source: request.source,
                    scope: .weekly,
                    observedAt: request.now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
    }

    private let agyUsageFixture = """
    Models & Quota

      Account: support@allnighter.io

    GEMINI MODELS
      Models within this group: Gemini Flash, Gemini Pro

      Weekly Limit
        [██████████████████████████████████████████████░░░░] 92.67%
        93% remaining · Refreshes in 164h 50m

      Five Hour Limit
        [█████████████████████████████░░░░░░░░░░░░░░░░░░░░░] 58.48%
        58% remaining · Refreshes in 3h 21m
    """

    private let kimiUsageFixture = """
    Plan usage
      Weekly limit  ████████████████████  100% used  resets in 1d 4h 33m
      5h limit      ░░░░░░░░░░░░░░░░░░░░  0% used    resets in 2h 33m
    """

    private let cursorUsageFixture = """
    ────────────────────────────────────────────────────────────────────────────────
     Usage • Ultra                                                  Resets Aug 25
     Monthly plan and on-demand usage

     Category        Current             Usage
     Included        27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
       Auto          27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
       API           27% used            ███████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     On-Demand       $0 / $1             ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

     $1 remaining

     View in dashboard: cursor.com/dashboard?tab=usage
    """

    /// Real Claude Code `/usage` render (founder capture 2026-07-30, pyte-normalized).
    /// Real boot banner, ANSI-stripped, as it lands in the probe buffer ahead of
    /// the Usage pane.
    private let claudeBannerFixture = """
       ▐▛███▜▌Claude Codev2.1.220▝▜█████▛▘Opus 5 (1M context) with high effort · Claude Max  ▘▘ ▝▝  ~/Documents/GitHub/Allnighter
    """

    private let claudeUsageFixture = """
       Settings  Status   Config   Usage   Stats

       Session

       Total cost:            $0.0000
       Total duration (API):  0s
       Total duration (wall): 3s
       Total code changes:    0 lines added, 0 lines removed
       Usage:                 0 input, 0 output, 0 cache read, 0 cache write

       Current session
       ██████████████████████████████████████▌        83% used
       Resets 8:49am (America/Vancouver)

       Current week (all models)
       ███████████████████████▌                           47% used
       Resets Aug 3 at 8pm (America/Vancouver)
       +50% weekly limits promo through Aug 19 · clau.de/cc-50-promo

       Current week (Fable)
       ███▌                                               7% used
       Resets Aug 3 at 8pm (America/Vancouver)

       What's contributing to your limits usage?
       Approximate, based on local sessions on this machine — does not include other devices or claude.ai

       Usage credits are off · /usage-credits to turn them on
    """

    /// Compact / space-stripped Claude Usage capture (CSI paint shape, dogfood
    /// 2026-08-02): `(allmodels)` primary weekly, `ClaudeMax` banner, no spaces
    /// in headers/reset lines. Must project as one primary pool (weekly + short)
    /// plus a genuine Fable secondary — never a third `allmodels` pool line.
    private let claudeSpaceStrippedUsageFixture = """
    Opus5(1Mcontext)withhigheffort·ClaudeMax  ~/Documents/GitHub/Allnighter
    SettingsStatusConfigUsageStats
    Session
    Totalcost:$0.0000
    Currentsession
    0%used
    Resets4:30pm(America/Vancouver)
    Currentweek(allmodels)
    96%used
    ResetsAug3at8pm(America/Vancouver)
    Currentweek(Fable)
    18%used
    ResetsAug3at8pm(America/Vancouver)
    Whatscontributingtoyourlimitsusage?
    """

    func testBareCapacityNeverInvokesProbeExecutor() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        let counter = CountingProbeExecutor()
        // Bare path (refresh: false) — no PTY spawns.
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: false,
            probeExecutor: counter
        )
        XCTAssertTrue(counter.calls.isEmpty, "bare capacity must spawn nothing; calls=\(counter.calls)")
        for source in CapacityAcquisition.benchSourceOrder {
            let row = windows.first { $0.source == source }
            XCTAssertEqual(row?.unknownReason, .neverSampled, source)
        }
    }

    func testRefreshInvokesProbePerProbeableSourceIncludingClaude() {
        let counter = CountingProbeExecutor()
        _ = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            probeExecutor: counter
        )
        let called = Set(counter.calls)
        XCTAssertEqual(called, Set(CapacityProbe.probeableSources))
        XCTAssertTrue(called.contains("claude_code"))
        XCTAssertTrue(called.contains("codex"))
        XCTAssertTrue(called.contains("grok"))
    }

    func testAllBenchSeatsArePTYProbeable() {
        XCTAssertTrue(CapacityAcquisition.diskOnlySources.isEmpty)
        XCTAssertEqual(
            Set(CapacityAcquisition.ptyOnlySources),
            Set(CapacityProbe.probeableSources)
        )
        XCTAssertTrue(CapacityProbe.probeableSources.contains("codex"))
        XCTAssertTrue(CapacityProbe.probeableSources.contains("grok"))
    }

    // MARK: - CAP-S09 targeted --source refresh

    /// validateRefreshSourceId only checks that the id is a known source.
    /// CLI requires `--refresh` with `--source` separately.
    func testValidateRefreshSourceIdAcceptsKnownBenchIds() {
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("cursor_agent"))
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("codex"))
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("grok"))
    }

    /// Unknown / misspelled source id → CLI_USAGE_ERROR listing valid ids.
    func testUnknownSourceIdIsUsageErrorListingValidIds() {
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("cursor_agent"))
        XCTAssertNil(CapacityAcquisition.validateRefreshSourceId("codex"))
        let message = CapacityAcquisition.validateRefreshSourceId("cursorr_agent")
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("unknown source") == true, message ?? "")
        for id in CapacityAcquisition.validRefreshSourceIds {
            XCTAssertTrue(
                message?.contains(id) == true,
                "error must list valid id \(id); got \(message ?? "nil")"
            )
        }
        // Never a silent accept of garbage.
        XCTAssertNotNil(CapacityAcquisition.validateRefreshSourceId("not_a_seat"))
        XCTAssertNotNil(CapacityAcquisition.validateRefreshSourceId(""))
    }

    /// `--refresh --source X` spawns exactly one probe; strip stays complete.
    func testRefreshSourceSpawnsExactlyOneProbeAndLeavesOtherRowsIntact() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        try writeGrokLog(grokBillingLine + "\n")

        let cursorWindows = CapacityProbe.parse(
            source: "cursor_agent",
            renderText: cursorUsageFixture,
            now: now
        )
        XCTAssertFalse(cursorWindows.isEmpty)

        let counter = CountingProbeExecutor()
        let fixture = FixtureProbeExecutor(results: [
            "cursor_agent": cursorWindows,
        ])
        // Compose: count every call, return fixture windows for the selected seat.
        let countingFixture = CountingThenFixtureExecutor(
            counter: counter,
            fixture: fixture
        )

        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            refreshSource: "cursor_agent",
            probeExecutor: countingFixture
        )

        XCTAssertEqual(counter.calls, ["cursor_agent"], "must probe only the named seat; calls=\(counter.calls)")

        // Full bench still present — never truncated to one row.
        let sources = Set(windows.map(\.source))
        for expected in CapacityAcquisition.benchSourceOrder {
            XCTAssertTrue(sources.contains(expected), "missing row \(expected)")
        }

        // Targeted seat carries real numbers from the probe.
        XCTAssertEqual(
            windows.first { $0.source == "cursor_agent" }?.usedPercent,
            27.0
        )

        // Unprobed seats stay neverSampled this turn.
        for source in CapacityAcquisition.benchSourceOrder where source != "cursor_agent" {
            let row = windows.first { $0.source == source }
            XCTAssertEqual(row?.unknownReason, .neverSampled, source)
            XCTAssertNil(row?.usedPercent, source)
        }
    }

    /// `--source codex` spawns exactly one PTY probe (no disk).
    func testRefreshSourceCodexProbesPTY() throws {
        let codexWindows = CodexCapacityProbe.capacityWindows(
            fromRender: """
            Weekly limit: [████████░░░░░░░░░░░░] 52% left
            (resets 21:32 on 4 Aug)
            Account: user@x.com (Plus)
            """,
            observedAt: now
        )
        XCTAssertFalse(codexWindows.isEmpty)
        let counter = CountingProbeExecutor()
        let fixture = FixtureProbeExecutor(results: ["codex": codexWindows])
        let countingFixture = CountingThenFixtureExecutor(counter: counter, fixture: fixture)
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            refreshSource: "codex",
            probeExecutor: countingFixture
        )
        XCTAssertEqual(counter.calls, ["codex"])
        XCTAssertEqual(windows.first { $0.source == "codex" }?.remainingPercent, 52.0)
        XCTAssertEqual(windows.first { $0.source == "codex" }?.sourceTier, .tuiProbe)
        for source in CapacityAcquisition.benchSourceOrder where source != "codex" {
            XCTAssertEqual(
                windows.first { $0.source == source }?.unknownReason,
                .neverSampled,
                source
            )
        }
    }

    /// Counting wrapper around a fixture executor for targeted-refresh tests.
    private final class CountingThenFixtureExecutor: CapacityProbeExecuting, @unchecked Sendable {
        private let counter: CountingProbeExecutor
        private let fixture: FixtureProbeExecutor
        init(counter: CountingProbeExecutor, fixture: FixtureProbeExecutor) {
            self.counter = counter
            self.fixture = fixture
        }
        func execute(_ request: CapacityProbeRequest) -> [CapacityWindow] {
            _ = counter.execute(request)
            return fixture.execute(request)
        }
    }

    func testClaudeUsageFixtureParsesSessionAndWeekly() {
        let windows = ClaudeCapacityLog.capacityWindows(
            fromRender: claudeUsageFixture,
            observedAt: now
        )
        XCTAssertEqual(windows.count, 3)
        let session = windows.first { $0.scope == .session }
        XCTAssertEqual(session?.usedPercent, 83.0)
        XCTAssertEqual(session?.remainingPercent, 17.0)
        let weeklyAll = windows.first { $0.scope == .weekly && $0.poolLabel == nil }
        XCTAssertEqual(weeklyAll?.usedPercent, 47.0)
        let fable = windows.first { $0.poolLabel == "Fable" }
        XCTAssertEqual(fable?.usedPercent, 7.0)
        // Promo line "+50% weekly limits" must not become a window.
        XCTAssertFalse(windows.contains { $0.usedPercent == 50.0 })
        // Spaced "all models" must never escape as a pool label.
        XCTAssertFalse(windows.contains { label in
            guard let p = label.poolLabel else { return false }
            return ClaudeCapacityLog.collapsedWhitespace(p).contains("allmodel")
        })
    }

    /// Phase 1 PM correction: space-stripped `(allmodels)` is the unlabeled
    /// primary weekly pool, not a third strip line. Session + all-models project
    /// into one primary Claude row; genuine Fable stays secondary.
    func testClaudeSpaceStrippedAllmodelsIsUnlabeledPrimaryNotPoolLabel() {
        let windows = ClaudeCapacityLog.capacityWindows(
            fromRender: claudeSpaceStrippedUsageFixture,
            observedAt: now
        )
        XCTAssertEqual(windows.count, 3, "session + primary weekly + Fable; got \(windows)")
        XCTAssertFalse(
            windows.contains { $0.poolLabel.map(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel) == true
                || $0.poolLabel?.lowercased().contains("allmodel") == true },
            "allmodels must never escape as poolLabel: \(windows.map(\.poolLabel))"
        )
        let session = windows.first { $0.scope == .session }
        XCTAssertEqual(session?.usedPercent, 0.0)
        XCTAssertEqual(session?.remainingPercent, 100.0)
        XCTAssertNil(session?.poolLabel)
        let weeklyPrimary = windows.first { $0.scope == .weekly && $0.poolLabel == nil }
        XCTAssertEqual(weeklyPrimary?.usedPercent, 96.0)
        XCTAssertEqual(weeklyPrimary?.remainingPercent, 4.0)
        let fable = windows.first { $0.poolLabel == "Fable" }
        XCTAssertEqual(fable?.usedPercent, 18.0)
        XCTAssertEqual(fable?.remainingPercent, 82.0)

        // Projection: one primary pool (weekly 4% + short 100%) and one Fable row.
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.pools.count, 2, "primary + Fable only; pools=\(row.pools.map(\.poolLabel))")
        let primary = row.pools.first { $0.poolLabel == nil }
        XCTAssertEqual(primary?.dashboardRemainingPercent, 4.0)
        XCTAssertEqual(primary?.dashboardScope, .weekly)
        guard case .known(let shortRem, _, _, _, _) = primary?.shortWindow else {
            return XCTFail("primary must carry session short window, got \(String(describing: primary?.shortWindow))")
        }
        XCTAssertEqual(shortRem, 100.0)
        let fablePool = row.pools.first { $0.poolLabel == "Fable" }
        XCTAssertEqual(fablePool?.dashboardRemainingPercent, 82.0)
        XCTAssertEqual(row.effectiveRemainingPercent, 4.0)
        XCTAssertEqual(row.planTier, "Max", "space-stripped ·ClaudeMax banner must yield Max")
        XCTAssertFalse(row.pools.contains { $0.poolLabel?.lowercased().contains("allmodel") == true })
    }

    /// Spaced and compact primary-pool names share one identity.
    func testClaudePrimaryWeeklyPoolLabelAliases() {
        XCTAssertTrue(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel("all models"))
        XCTAssertTrue(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel("allmodels"))
        XCTAssertTrue(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel("All Models"))
        XCTAssertTrue(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel(" ALL  MODELS "))
        XCTAssertFalse(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel("Fable"))
        XCTAssertFalse(ClaudeCapacityLog.isPrimaryWeeklyPoolLabel("all models extra"))
        XCTAssertNil(ClaudeCapacityLog.canonicalPoolLabel("allmodels"))
        XCTAssertNil(ClaudeCapacityLog.canonicalPoolLabel("all models"))
        XCTAssertEqual(ClaudeCapacityLog.canonicalPoolLabel("Fable"), "Fable")
    }

    /// The Plan column read `-` for Claude while the vendor stated the tier twice.
    /// The boot banner is already in every successful capture, so no extra pane
    /// navigation is needed to fill it.
    func testClaudePlanTierComesFromTheBootBanner() {
        let render = claudeBannerFixture + "\n" + claudeUsageFixture
        XCTAssertEqual(ClaudeCapacityLog.planTier(fromRender: render), "Max")
        let windows = ClaudeCapacityLog.capacityWindows(fromRender: render, observedAt: now)
        XCTAssertFalse(windows.isEmpty)
        XCTAssertTrue(windows.allSatisfy { $0.planTier == "Max" })
    }

    /// `/status` states it as a labeled field, which beats a banner suffix when
    /// the probe took the fallback path and captured both.
    func testClaudePlanTierPrefersTheLabeledStatusField() {
        let render = """
           Settings  Status   Config   Usage   Stats

           Version:          2.1.220
           Login method:     Claude Max account
           Organization:     support@allnighter.io's Organization
        """
        XCTAssertEqual(ClaudeCapacityLog.planTier(fromRender: render), "Max")
    }

    /// A Max multiplier is part of the tier, not noise to be trimmed off.
    func testClaudePlanTierKeepsAMaxMultiplier() {
        XCTAssertEqual(
            ClaudeCapacityLog.planTier(fromRender: "Opus 5 · Claude Max 20x  ~/repo"),
            "Max 20x"
        )
        // Space-stripped banner form (`ClaudeMax20x`).
        XCTAssertEqual(
            ClaudeCapacityLog.planTier(fromRender: "Opus5·ClaudeMax20x  ~/repo"),
            "Max 20x"
        )
    }

    /// Fail closed: a render with no tier statement must not invent one, and the
    /// promo line's `· clau.de/cc-50-promo` must not read as a plan.
    func testClaudePlanTierIsNilWhenTheRenderDoesNotSayIt() {
        XCTAssertNil(ClaudeCapacityLog.planTier(fromRender: claudeUsageFixture))
        // Compact usage body without a banner still must not invent Max.
        let bodyOnly = """
        Currentsession
        0%used
        Currentweek(allmodels)
        96%used
        """
        XCTAssertNil(ClaudeCapacityLog.planTier(fromRender: bodyOnly))
    }

    /// Space-stripped boot banner `·ClaudeMax` is a real tier statement.
    func testClaudePlanTierFromSpaceStrippedBanner() {
        XCTAssertEqual(
            ClaudeCapacityLog.planTier(fromRender: "Opus5(1Mcontext)·ClaudeMax  ~/repo"),
            "Max"
        )
        XCTAssertEqual(
            ClaudeCapacityLog.planTier(fromRender: "Loginmethod:ClaudeMaxaccount"),
            "Max"
        )
    }

    func testRefreshFixtureParsersProduceWindowsForAllPTYSeats() throws {
        let agyWindows = CapacityProbe.parse(source: "agy", renderText: agyUsageFixture, now: now)
        let kimiWindows = CapacityProbe.parse(source: "kimi", renderText: kimiUsageFixture, now: now)
        let cursorWindows = CapacityProbe.parse(source: "cursor_agent", renderText: cursorUsageFixture, now: now)
        let claudeWindows = CapacityProbe.parse(source: "claude_code", renderText: claudeUsageFixture, now: now)
        let codexWindows = CodexCapacityProbe.capacityWindows(
            fromRender: "Weekly limit: 48% left\n(resets 21:32 on 4 Aug)\nAccount: (Plus)",
            observedAt: now
        )
        let grokWindows = GrokCapacityProbe.capacityWindows(
            fromRender: "Weekly limit: 42%\nNext reset: July 31, 11:11",
            observedAt: now
        )
        XCTAssertFalse(agyWindows.isEmpty)
        XCTAssertFalse(kimiWindows.isEmpty)
        XCTAssertFalse(cursorWindows.isEmpty)
        XCTAssertFalse(claudeWindows.isEmpty)
        XCTAssertFalse(codexWindows.isEmpty)
        XCTAssertFalse(grokWindows.isEmpty)

        let executor = FixtureProbeExecutor(results: [
            "agy": agyWindows,
            "kimi": kimiWindows,
            "cursor_agent": cursorWindows,
            "claude_code": claudeWindows,
            "codex": codexWindows,
            "grok": grokWindows,
        ])
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            probeExecutor: executor
        )

        XCTAssertNotNil(windows.first { $0.source == "codex" && $0.remainingPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "grok" && $0.usedPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "agy" && $0.remainingPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "kimi" && $0.usedPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "cursor_agent" && $0.usedPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "claude_code" && $0.usedPercent != nil })

        XCTAssertTrue(
            windows.allSatisfy { $0.unknownReason != .vendorExposesNothing },
            "refresh path must never return vendorExposesNothing for parser-backed seats"
        )
    }

    func testRefreshSpawnFailureIsUnknownAndDoesNotZeroFill() throws {
        let executor = FixtureProbeExecutor(results: [
            "agy": [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: now),
                    source: "agy",
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ],
            "kimi": [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: now),
                    source: "kimi",
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ],
            "cursor_agent": [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: now),
                    source: "cursor_agent",
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ],
            "claude_code": [
                CapacityWindow.unknown(
                    reason: .parserFailed(observedAt: now),
                    source: "claude_code",
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ],
        ])
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            probeExecutor: executor
        )

        // Every PTY seat fails closed — no percentages, no zeros, no disk
        // fallback. Scoped to the PTY roster: the dashboard seat is not probed
        // by this path, so it is legitimately neverSampled here.
        for source in CapacityAcquisition.ptySourceOrder {
            let row = windows.first { $0.source == source }
            XCTAssertEqual(row?.unknownReason, .parserFailed(observedAt: now), source)
            XCTAssertNil(row?.usedPercent, source)
            XCTAssertNil(row?.remainingPercent, source)
        }
    }

    func testProbeRejectsVendorExposesNothingFromExecutor() {
        // Even a buggy executor claiming vendorExposesNothing is rewritten.
        var results: [String: [CapacityWindow]] = [:]
        for source in CapacityAcquisition.ptyOnlySources {
            results[source] = [
                CapacityWindow.unknown(
                    reason: .vendorExposesNothing,
                    source: source,
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ]
        }
        let executor = FixtureProbeExecutor(results: results)
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            probeExecutor: executor
        )
        for source in CapacityAcquisition.ptyOnlySources {
            let row = windows.first { $0.source == source }
            XCTAssertNotEqual(row?.unknownReason, .vendorExposesNothing, source)
            XCTAssertEqual(row?.unknownReason, .parserFailed(observedAt: now), source)
        }
    }

    // MARK: - Claude trust dialog (space-stripped TUI)

    func testClaudeTrustDialogMatcherHandlesSpaceStrippedRender() {
        // Real ProbeScratch dump shape (spaces stripped by CSI paint).
        let dump = """
        Accessingworkspace:
        /Users/mike/Library/ApplicationSupport/Allnighter/ProbeScratch
        Quicksafetycheck:Isthisaprojectyoucreatedoroneyoutrust?
        ClaudeCode'llbeabletoread,edit,andexecutefileshere.
        ❯1.Yes,Itrustthisfolder
        2.No,exit
        """
        XCTAssertTrue(CapacityProbe.looksLikeWorkspaceTrustDialog(dump))
        XCTAssertFalse(CapacityProbe.looksReadyForUsageCommand(dump))
        // Spaced form also matches.
        XCTAssertTrue(CapacityProbe.looksLikeWorkspaceTrustDialog(
            "Yes, I trust this folder\nDo you trust this folder?"
        ))
        // Usage pane is not trust.
        XCTAssertFalse(CapacityProbe.looksLikeWorkspaceTrustDialog(
            "Current session\n83% used\nCurrent week (all models)"
        ))
    }

    func testClaudeReadyIgnoresStaleTrustTextInBufferHead() {
        // Dogfood 2026-08-02: after accepting trust, the buffer still holds the
        // dialog at the head while welcome chrome paints at the tail. Readiness
        // must use the recent window or we never leave the trust loop.
        let trustDialog = """
        Accessingworkspace:
        /Users/mike/Library/ApplicationSupport/Allnighter/ProbeScratch
        Quicksafetycheck:Isthisaprojectyoucreatedoroneyoutrust?
        ❯1.Yes,Itrustthisfolder
        2.No,exit
        """
        // Neutral paint after trust (no trust keywords) so the recent window is clean.
        let postTrustPaint = String(repeating: "·", count: 2200)
        let welcomeTail = """
        Welcome back Mike!
        Tips for getting started
        Ask Claude to create a new app
        What's new
        Haiku 4.5 · Claude Max
        """
        let combined = trustDialog + postTrustPaint + welcomeTail
        XCTAssertTrue(CapacityProbe.looksLikeWorkspaceTrustDialog(combined))
        XCTAssertTrue(
            CapacityProbe.looksReadyForUsageCommand(combined),
            "welcome tail must beat stale trust head"
        )
        XCTAssertFalse(
            CapacityProbe.looksLikeWorkspaceTrustDialog(
                CapacityProbe.recentPaintWindow(combined)
            )
        )
    }

    func testClaudeUsageFixtureStillParsesAfterTrustCleared() {
        // Prove the canonical Claude parser reaches the usage surface text.
        let windows = ClaudeCapacityLog.capacityWindows(
            fromRender: claudeUsageFixture,
            observedAt: now
        )
        XCTAssertFalse(windows.isEmpty)
        XCTAssertNotNil(windows.first { $0.scope == .session })
        XCTAssertNotNil(windows.first { $0.scope == .weekly })
    }

    func testCodexUpgradePromptMatcherHandlesSpaceStrippedRender() {
        // Real ProbeScratch dump 2026-08-06: Codex 0.146.0 → 0.146.1 nudge blocked /status.
        let dump = """
        ✨ Update available!0.146.0 -> 0.146.1Release notes: https://github.com/openai/codex/releases/latest› 1. Update now (runs `brew upgrade --cask codex`)2.Skip3.SkipuntilnextversionPress enter to continue
        """
        XCTAssertTrue(CapacityProbe.looksLikeCodexUpgradePrompt(dump))
        XCTAssertFalse(CapacityProbe.looksReadyForUsageCommand(dump))
        XCTAssertFalse(CapacityProbe.looksLikeCodexUpgradePrompt(
            "Weekly limit: [░░░░░░░░░░░░░░░░░░░░] 12% left (resets 21:32 on 4 Aug)"
        ))
    }

    func testCodexStatusRenderStillParsesAfterUpgradePromptCleared() {
        let upgrade = """
        Update available! 0.146.0 -> 0.146.1
        1. Update now
        2. Skip
        3. Skip until next version
        """
        let status = """
        Weekly limit: [████░░░░░░░░░░░░░░░░] 12% left
        (resets 21:32 on 4 Aug)
        Account: user@example.com (Plus)
        """
        let combined = upgrade + String(repeating: "·", count: 2200) + status
        XCTAssertTrue(CapacityProbe.looksLikeCodexUpgradePrompt(upgrade))
        XCTAssertFalse(
            CapacityProbe.looksLikeCodexUpgradePrompt(CapacityProbe.recentPaintWindow(combined))
        )
        XCTAssertTrue(CapacityProbe.looksLikeCodexStatusPane(status))
        XCTAssertTrue(CapacityProbe.looksReadyForUsageCommand(combined))
        let windows = CodexCapacityProbe.capacityWindows(fromRender: combined, observedAt: now)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.remainingPercent, 12.0)
        XCTAssertEqual(windows.first?.planTier, "Plus")
    }

    func testCodexBootChromeAndLowQuotaBannerAreNotStatusPane() {
        let boot = """
        │ >_ OpenAI Codex (v0.146.1)                     │
        │ model:     loading   /model to change          │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
        Starting MCP servers (1/2): codex_apps (esc to interrupt)
        """
        XCTAssertFalse(CapacityProbe.looksLikeCodexReadyForStatusCommand(boot))
        XCTAssertFalse(CapacityProbe.looksLikeCodexStatusPane(boot))

        let loaded = """
        │ >_ OpenAI Codex (v0.146.1)                     │
        │ model:     gpt-5.6-sol high   /model to change   │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
        › Summarize recent commits
        """
        XCTAssertTrue(CapacityProbe.looksLikeCodexReadyForStatusCommand(loaded))
        XCTAssertFalse(CapacityProbe.looksLikeCodexStatusPane(loaded))

        let banner = "Heads up, you have less than 25% of your weekly limit left. Run /status for a breakdown."
        XCTAssertFalse(CapacityProbe.looksLikeCodexStatusPane(banner))
    }

    /// An empty parse has two completely different causes and they used to share
    /// one name. `parserFailed` says a surface exists that we could not read —
    /// it sends a human to go fix a parser. On 2026-08-08 both codex and grok
    /// reported it while their parsers were fine: codex never got past MCP
    /// startup, grok never got past its splash animation. Neither had a screen.
    func testEmptyParseIsAttributedToTheThingThatActuallyFailed() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)

        // Pane rendered, parser could not read it — a genuine parser defect.
        XCTAssertEqual(
            CapacityProbe.emptyParseReason(sawUsagePane: true, observedAt: at),
            .parserFailed(observedAt: at))

        // Pane never rendered — nothing to parse. `probeTimeout` already means
        // exactly this: "hit the wall-clock budget before a usable screen".
        XCTAssertEqual(
            CapacityProbe.emptyParseReason(sawUsagePane: false, observedAt: at),
            .probeTimeout(observedAt: at))

        // The two must never collapse back into one answer.
        XCTAssertNotEqual(
            CapacityProbe.emptyParseReason(sawUsagePane: true, observedAt: at),
            CapacityProbe.emptyParseReason(sawUsagePane: false, observedAt: at))
    }

    /// Codex's built-in `codex_apps` MCP server never finishes starting here, so
    /// waiting for it is unbounded. The TUI advertises the way out — "esc to
    /// interrupt" — and taking it turns a 60s timeout into a 4s read.
    func testCodexMCPStartupIsDetectedThenStopsOnceAborted() {
        let spinning = """
        │ model:     gpt-5.6-sol high   /model to change │
        •Starting MCP servers (1/2): codex_apps (0s • esc to interrupt)
        """
        XCTAssertTrue(CapacityProbe.looksLikeCodexMCPStarting(spinning))

        // After the abort, Escape must NOT be sent again — a second press lands
        // on a live composer and reads as "edit previous message", which is
        // exactly what the capture showed ("No previous message to edit.").
        let aborted = """
        Starting MCP servers (1/2): codex_apps (0s • esc to interrupt)
        ⚠ MCP startup interrupted. The following servers were not initialized: codex_apps
        › Use /skills to list available skills
        """
        XCTAssertFalse(
            CapacityProbe.looksLikeCodexMCPStarting(aborted),
            "the spinner text survives in scrollback; the abort must outrank it")
    }

    /// The abort confirmation must be a POSITIVE readiness signal, not merely
    /// "stop blocking". By the time it prints, the boot box carrying
    /// `directory:` + `model:` has scrolled out of the recent paint window, so
    /// the ordinary positive test can no longer fire — codex would sit ready-less
    /// for the whole budget and never send /status. That was the last bug in the
    /// chain, and it is invisible unless the fixture omits the boot box.
    func testCodexIsReadyOnceMCPStartupIsInterrupted() {
        let abortedNoBootBox = """
        ⚠ MCP startup interrupted. The following servers were not initialized: codex_apps
        › Use /skills to list available skills
        gpt-5.6-sol high · ~/Library/Application Support/Allnighter/ProbeScratch
        """
        XCTAssertFalse(
            CapacityProbe.collapsedForMatch(abortedNoBootBox).contains("directory:"),
            "precondition: the boot box is gone — that is what made this subtle")
        XCTAssertTrue(
            CapacityProbe.looksLikeCodexReadyForStatusCommand(abortedNoBootBox))
        XCTAssertTrue(
            CapacityProbe.looksReadyForUsageCommand(abortedNoBootBox, source: "codex"))
    }

    /// A capacity probe reads one screen; it has no use for the user's MCP tool
    /// hosts. Every argument here has to be earned by a measured before/after,
    /// so the test also pins that no other source gained flags by accident.
    func testProbeArgumentsAreCodexOnly() {
        XCTAssertEqual(CapacityProbe.probeArguments(for: "codex"), ["-c", "mcp_servers={}"])
        for source in ["grok", "claude_code", "kimi", "cursor_agent", "agy"] {
            XCTAssertTrue(
                CapacityProbe.probeArguments(for: source).isEmpty,
                "\(source) must launch bare unless a measurement justifies otherwise")
        }
    }

    /// Fixing codex's MCP guard was not enough — the guard was being ROUTED
    /// AROUND. `looksReadyForUsageCommand` matched the generic marker `"tip:"`
    /// against codex's own boot chrome ("Tip: Try the Desktop app") and returned
    /// true before the codex predicate was ever consulted, because that
    /// predicate sat at the end as a positive fallback only.
    ///
    /// The law this pins: a source that ships its own readiness predicate is
    /// authoritative for BOTH answers. A generic chrome marker may never
    /// override a source-specific "still booting".
    func testGenericChromeMarkersCannotOverrideCodexNotReady() {
        let bootingWithTip = """
        │ >_ OpenAI Codex (v0.147.0)                     │
        │ model:     gpt-5.6-sol high   /model to change │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
          Tip: Try the Desktop app. Run 'codex app'
        •Starting MCP servers (1/2): codex_apps(0s • esc to interrupt)
        """
        // The generic path is exactly what shipped the bug.
        XCTAssertTrue(
            CapacityProbe.looksReadyForUsageCommand(bootingWithTip),
            "precondition: generic chrome DOES match here — that was the trap")
        // Source-aware, codex's own verdict wins.
        XCTAssertFalse(
            CapacityProbe.looksReadyForUsageCommand(bootingWithTip, source: "codex"),
            "codex must not be declared ready while MCP servers are still starting")

        // Control: once settled, source-aware readiness still says yes.
        let settled = """
        │ >_ OpenAI Codex (v0.147.0)                     │
        │ model:     gpt-5.6-sol high   /model to change │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
          Tip: Try the Desktop app. Run 'codex app'
        › Summarize recent commits
        """
        XCTAssertTrue(CapacityProbe.looksReadyForUsageCommand(settled, source: "codex"))

        // Other sources keep the generic path untouched.
        XCTAssertTrue(
            CapacityProbe.looksReadyForUsageCommand("? for shortcuts", source: "grok"))
    }

    /// The shape that actually broke capacity on 2026-08-08, taken from the live
    /// dump at Capacity/debug/codex-parseFailed.txt.
    ///
    /// `testCodexBootChromeAndLowQuotaBannerAreNotStatusPane` above looks like it
    /// covers this and does not: its boot fixture also says `model: loading`,
    /// which trips a different guard, so it passed while the MCP guard was
    /// misspelled (`escrtointerrupt`) and dead. Here the model is already
    /// resolved — exactly the real capture — so the MCP guard is the only thing
    /// that can return false.
    func testCodexIsNotReadyWhileMCPServersAreStillStarting() {
        let mcpBooting = """
        │ >_ OpenAI Codex (v0.147.0)                     │
        │ model:     gpt-5.6-sol high   /model to change │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
        •Starting MCP servers (1/2): codex_apps(1s • esc to interrupt)
        """
        XCTAssertFalse(
            CapacityProbe.looksLikeCodexReadyForStatusCommand(mcpBooting),
            "sending /status here makes codex QUEUE it, so the pane never paints")

        // The spinner alone must also hold it back — "Starting MCP servers" can
        // scroll out of the recent paint window while the spinner is still live,
        // which is why the misspelling mattered.
        let spinnerOnly = """
        │ >_ OpenAI Codex (v0.147.0)                     │
        │ model:     gpt-5.6-sol high   /model to change │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
        (1s • esc to interrupt)
        """
        XCTAssertFalse(CapacityProbe.looksLikeCodexReadyForStatusCommand(spinnerOnly))

        // Control: once the spinner clears, the same chrome IS ready.
        let settled = """
        │ >_ OpenAI Codex (v0.147.0)                     │
        │ model:     gpt-5.6-sol high   /model to change │
        │ directory: ~/Library/…/Allnighter/ProbeScratch │
        › Summarize recent commits
        """
        XCTAssertTrue(CapacityProbe.looksLikeCodexReadyForStatusCommand(settled))
        XCTAssertFalse(CapacityProbe.looksLikeCodexStatusPane("›/status gpt-5.6-sol high"))
    }

    func testNeutralWorkingDirectoryUsesProbeScratch() {
        let path = CapacityProbe.neutralWorkingDirectory()
        XCTAssertNotNil(path)
        XCTAssertTrue(path?.contains("ProbeScratch") == true, "capacity probes must not inherit repo CWD")
    }

    func testLiveProbeMissingBinaryIsSpawnFailedNotZero() {
        // A named path that does not exist is a spawn failure (we tried to
        // launch something). A missing PATH install is `notInstalled`.
        let windows = CapacityProbe.windows(
            source: "agy",
            now: now,
            timeout: 2,
            executableOverride: "/tmp/alln-capacity-probe-missing-\(UUID().uuidString)"
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].unknownReason, .spawnFailed(observedAt: now))
        XCTAssertNil(windows[0].usedPercent)
        XCTAssertNil(windows[0].remainingPercent)
        XCTAssertNotEqual(windows[0].unknownReason, .vendorExposesNothing)
        XCTAssertNotEqual(windows[0].unknownReason, .parserFailed(observedAt: now))
    }

    func testUnresolvedExecutableIsNotInstalledNotSpawnFailed() {
        let windows = CapacityProbe.windows(
            source: "agy",
            now: now,
            timeout: 2,
            pathEnvironment: "/tmp/alln-empty-path-\(UUID().uuidString)",
            homeDirectory: URL(fileURLWithPath: "/tmp/alln-empty-home-\(UUID().uuidString)", isDirectory: true)
        )
        XCTAssertEqual(windows[0].unknownReason, .notInstalled)
        XCTAssertNil(windows[0].usedPercent)
    }

    #if os(macOS)
    func testLiveProbeTimeoutTerminatesChildAndReturnsUnknown() throws {
        // Long-sleep wrapper never paints a usage pane. Timeout must kill the
        // child and return unknown — never a fabricated percentage.
        let script = homeRoot.appendingPathComponent("cap-s08-sleeper.sh")
        try """
        #!/bin/sh
        exec /bin/sleep 60
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )

        let started = Date()
        let windows = CapacityProbe.windows(
            source: "kimi",
            now: now,
            timeout: 1.5,
            executableOverride: script.path
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(windows.count, 1)
        XCTAssertNotNil(windows[0].unknownReason)
        XCTAssertNil(windows[0].usedPercent)
        XCTAssertNil(windows[0].remainingPercent)
        XCTAssertNotEqual(windows[0].unknownReason, .vendorExposesNothing)
        // Must not wait anywhere near the 60s sleep.
        XCTAssertLessThan(elapsed, 8.0, "probe must time out and kill the sleeper")

        // No orphan sleeper left behind (best-effort: script path in process list).
        // Write to a file — never Pipe + waitUntilExit (large `ps` output deadlocks
        // when the pipe buffer fills before the parent reads).
        let psOut = homeRoot.appendingPathComponent("cap-s08-ps.txt")
        FileManager.default.createFile(atPath: psOut.path, contents: nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "command="]
        task.standardOutput = try FileHandle(forWritingTo: psOut)
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        try (task.standardOutput as? FileHandle)?.close()
        let ps = (try? String(contentsOf: psOut, encoding: .utf8)) ?? ""
        XCTAssertFalse(
            ps.contains(script.path),
            "sleeper child must be terminated after probe timeout"
        )
    }
    #endif
}
