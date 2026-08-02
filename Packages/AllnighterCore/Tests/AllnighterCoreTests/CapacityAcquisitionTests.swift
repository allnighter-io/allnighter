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

    func testCodexReadsNewestRolloutAndStops() throws {
        // Older file first (lower mtime); newer file has the 52% sample.
        try writeCodexRollout(
            year: "2026", month: "07", day: "20",
            name: "rollout-2026-07-20T10-00-00-old.jsonl",
            content: codexOlderLine + "\n",
            mtime: Date(timeIntervalSince1970: 1_753_000_000)
        )
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: Date(timeIntervalSince1970: 1_753_700_000)
        )

        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let codex = windows.filter { $0.source == "codex" }
        XCTAssertEqual(codex.count, 1)
        XCTAssertEqual(codex[0].usedPercent, 52.0)
        XCTAssertEqual(codex[0].planTier, "plus")
        XCTAssertEqual(codex[0].sourceTier, .onDisk)
        XCTAssertNil(codex[0].unknownReason)
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

    func testCodexEmptyFileIsParserFailedNotZero() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-00-00-empty.jsonl",
            content: "\n\n",
            mtime: now
        )
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let codex = windows.first { $0.source == "codex" }
        XCTAssertEqual(codex?.unknownReason, .parserFailed(observedAt: now))
        XCTAssertNil(codex?.usedPercent)
    }

    func testCodexSkipsUnusableNewestThenUsesOlder() throws {
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
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let codex = windows.filter { $0.source == "codex" }
        XCTAssertEqual(codex.count, 1)
        XCTAssertEqual(codex[0].usedPercent, 52.0)
    }

    // MARK: - Grok

    func testGrokReadsBillingFromTailNewestWins() throws {
        // Noise, older billing, noise, newest billing at end.
        let body = [
            #"{"ts":"2026-07-30T00:00:00.000Z","msg":"session start"}"#,
            grokOlderBillingLine,
            #"{"ts":"2026-07-30T00:30:00.000Z","msg":"tool call"}"#,
            grokBillingLine,
            "",
        ].joined(separator: "\n")
        try writeGrokLog(body)

        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let grok = windows.filter { $0.source == "grok" }
        XCTAssertEqual(grok.count, 1)
        XCTAssertEqual(grok[0].usedPercent, 42.0)
        XCTAssertEqual(grok[0].remainingPercent, 58.0)
        XCTAssertEqual(grok[0].planTier, "X Premium+")
        XCTAssertEqual(grok[0].sourceTier, .onDisk)
        XCTAssertNil(grok[0].unknownReason)
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
        let got = CapacityAcquisition.latestGrokWindowReadingBackwards(from: url, chunkSize: 128)
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

    func testGrokEmptyLogIsParserFailed() throws {
        try writeGrokLog("")
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let grok = windows.first { $0.source == "grok" }
        XCTAssertEqual(grok?.unknownReason, .parserFailed(observedAt: now))
        XCTAssertNil(grok?.remainingPercent)
    }

    // MARK: - Tier 3

    /// Tier-3 TUI-probe-only seats (no disk fallback) are `neverSampled` when no refresh.
    /// Codex and Grok are also tier-3 probeable but have disk-read fallbacks:
    /// when the bare/cached path runs, they return disk data (not neverSampled).
    func testTier3SourcesReportNeverSampledNotVendorGap() {
        // Use empty homeRoot so codex/grok disk fallbacks also yield neverSampled.
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let bySource = Dictionary(grouping: windows, by: \.source)

        // Pure-probe seats (no disk fallback): must be neverSampled, tuiProbe tier.
        let pureProbeSources = CapacityAcquisition.tier3DisklessSources.filter {
            $0 != "codex" && $0 != "grok"
        }
        for source in pureProbeSources {
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

    func testCombinedCodexAndGrokWithTier3() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        try writeGrokLog(grokBillingLine + "\n")

        // Use --cached path so disk fallback runs for codex/grok.
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now, refresh: false)
        let codex = windows.filter { $0.source == "codex" }
        let grok = windows.filter { $0.source == "grok" }
        XCTAssertEqual(codex.first?.usedPercent, 52.0)
        XCTAssertEqual(grok.first?.usedPercent, 42.0)
        // Pure-probe seats (not codex/grok) are neverSampled on cached path.
        let pureProbeSources = Set(CapacityAcquisition.tier3DisklessSources).subtracting(["codex", "grok"])
        let neverSampledCount = windows.filter { $0.unknownReason == .neverSampled }.count
        XCTAssertEqual(neverSampledCount, pureProbeSources.count)
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

      Account: emailmike@gmail.com

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

    func testBareCapacityNeverInvokesProbeExecutor() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        let counter = CountingProbeExecutor()
        // Use refresh: false explicitly (the --cached path — no PTY spawns).
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: false,
            probeExecutor: counter
        )
        XCTAssertTrue(counter.calls.isEmpty, "cached capacity must spawn nothing; calls=\(counter.calls)")
        // Codex has a disk fallback, so it returns real data even in cached path.
        XCTAssertEqual(windows.first { $0.source == "codex" }?.usedPercent, 52.0)
        // Pure-probe tier-3 seats (no disk fallback) are still neverSampled.
        let pureProbeSources = CapacityAcquisition.tier3DisklessSources.filter {
            $0 != "codex" && $0 != "grok"
        }
        for source in pureProbeSources {
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
        XCTAssertEqual(called, Set(CapacityAcquisition.tier3ProbeableSources))
        XCTAssertTrue(called.contains("claude_code"), "Claude /usage probe is shipped")
    }

    // MARK: - CAP-S09 targeted --source refresh

    /// `--source` is now valid without `--cached`/`--refresh` flag — the flag
    /// constraint was removed when refresh became the default.
    func testSourceWithoutRefreshIsNowValid() {
        // validateRefreshSourceId only checks that the id is a known source.
        // A nil return means the id is valid.
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

        // Other tier-3 seats: those without disk fallback stay neverSampled.
        // Codex and Grok have disk fallbacks — when not the targeted source,
        // they return disk data (not neverSampled).
        let pureProbeSources = CapacityAcquisition.tier3DisklessSources.filter {
            $0 != "cursor_agent" && $0 != "codex" && $0 != "grok"
        }
        for source in pureProbeSources {
            let row = windows.first { $0.source == source }
            XCTAssertEqual(row?.unknownReason, .neverSampled, source)
            XCTAssertNil(row?.usedPercent, source)
        }

        // Codex and Grok: targeted-source refresh with disk log files → disk data.
        XCTAssertEqual(windows.first { $0.source == "codex" }?.usedPercent, 52.0)
        XCTAssertEqual(windows.first { $0.source == "grok" }?.usedPercent, 42.0)
    }

    /// `--source codex` with a disk log → probe runs (codex is now tier-3),
    /// but only the codex seat is probed. Other tier-3 seats use disk fallbacks
    /// (codex/grok) or neverSampled (pure-probe seats).
    func testRefreshSourceCodexIsNowTier3Probeable() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        let counter = CountingProbeExecutor()
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            refreshSource: "codex",
            probeExecutor: counter
        )
        // Codex IS now tier-3 — probe is called.
        XCTAssertEqual(counter.calls, ["codex"], "must probe exactly codex; calls=\(counter.calls)")
        // CountingProbeExecutor returns parserFailed, not real data.
        XCTAssertEqual(
            windows.first { $0.source == "codex" }?.unknownReason,
            .parserFailed(observedAt: now),
            "probe executor returned parserFailed — no disk fallback since probe was attempted"
        )
        // Full strip still present.
        XCTAssertEqual(
            Set(windows.map(\.source)).intersection(Set(CapacityAcquisition.benchSourceOrder)).count,
            CapacityAcquisition.benchSourceOrder.count
        )
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
           Organization:     emailmike@gmail.com's Organization
        """
        XCTAssertEqual(ClaudeCapacityLog.planTier(fromRender: render), "Max")
    }

    /// A Max multiplier is part of the tier, not noise to be trimmed off.
    func testClaudePlanTierKeepsAMaxMultiplier() {
        XCTAssertEqual(
            ClaudeCapacityLog.planTier(fromRender: "Opus 5 · Claude Max 20x  ~/repo"),
            "Max 20x"
        )
    }

    /// Fail closed: a render with no tier statement must not invent one, and the
    /// promo line's `· clau.de/cc-50-promo` must not read as a plan.
    func testClaudePlanTierIsNilWhenTheRenderDoesNotSayIt() {
        XCTAssertNil(ClaudeCapacityLog.planTier(fromRender: claudeUsageFixture))
    }

    func testRefreshFixtureParsersProduceWindowsAndPreserveTier1() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        try writeGrokLog(grokBillingLine + "\n")

        // Works Test: each parser is fed a captured real render (fixture) via the
        // probe seam — proving probe→parser wiring, not just the parsers alone.
        let agyWindows = CapacityProbe.parse(source: "agy", renderText: agyUsageFixture, now: now)
        let kimiWindows = CapacityProbe.parse(source: "kimi", renderText: kimiUsageFixture, now: now)
        let cursorWindows = CapacityProbe.parse(source: "cursor_agent", renderText: cursorUsageFixture, now: now)
        let claudeWindows = CapacityProbe.parse(source: "claude_code", renderText: claudeUsageFixture, now: now)
        XCTAssertFalse(agyWindows.isEmpty)
        XCTAssertFalse(kimiWindows.isEmpty)
        XCTAssertFalse(cursorWindows.isEmpty)
        XCTAssertFalse(claudeWindows.isEmpty)
        // Agy prefers the high-precision bar float (92.67) over the rounded "93%".
        XCTAssertEqual(agyWindows.first?.remainingPercent, Optional(92.67))
        XCTAssertEqual(kimiWindows.first { $0.scope == .weekly }?.usedPercent, Optional(100.0))
        XCTAssertEqual(cursorWindows.first?.usedPercent, Optional(27.0))
        XCTAssertEqual(claudeWindows.first { $0.scope == .session }?.usedPercent, Optional(83.0))

        let executor = FixtureProbeExecutor(results: [
            "agy": agyWindows,
            "kimi": kimiWindows,
            "cursor_agent": cursorWindows,
            "claude_code": claudeWindows,
        ])
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            probeExecutor: executor
        )

        // Codex and Grok are now tier-3 probeable. With a FixtureProbeExecutor that
        // only has results for agy/kimi/cursor/claude, codex and grok will get
        // parserFailed from the executor. Disk-read fallback applies when probes fail.
        // So here the fixture returns parserFailed for codex/grok — we verify the
        // tier-3 probe path runs (not the disk path) since refresh=true drove it.
        let codexRow = windows.first { $0.source == "codex" }
        let grokRow = windows.first { $0.source == "grok" }
        // The FixtureProbeExecutor returns parserFailed for unknown sources.
        // The disk data from the log files is NOT used when a probe was dispatched
        // (the probe result wins; fail closed to parserFailed, not disk data).
        XCTAssertEqual(codexRow?.unknownReason, .parserFailed(observedAt: now), "codex probe ran and failed closed")
        XCTAssertEqual(grokRow?.unknownReason, .parserFailed(observedAt: now), "grok probe ran and failed closed")

        // Probeable seats carry real numbers.
        XCTAssertNotNil(windows.first { $0.source == "agy" && $0.remainingPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "kimi" && $0.usedPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "cursor_agent" && $0.usedPercent != nil })
        XCTAssertNotNil(windows.first { $0.source == "claude_code" && $0.usedPercent != nil })

        // No seat may claim vendorExposesNothing.
        XCTAssertTrue(
            windows.allSatisfy { $0.unknownReason != .vendorExposesNothing },
            "refresh path must never return vendorExposesNothing for parser-backed seats"
        )
    }

    func testRefreshSpawnFailureIsUnknownAndDoesNotZeroFillOrTouchTier1() throws {
        try writeCodexRollout(
            year: "2026", month: "07", day: "28",
            name: "rollout-2026-07-28T12-09-28-new.jsonl",
            content: codexPlusLine + "\n",
            mtime: now
        )
        try writeGrokLog(grokBillingLine + "\n")

        // All probes fail closed as parserFailed — no percentages, no zeros.
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
        ])
        let windows = CapacityAcquisition.windows(
            homeRoot: homeRoot,
            now: now,
            refresh: true,
            probeExecutor: executor
        )

        // Codex and Grok are now tier-3 probeable.
        // The fixture executor returns parserFailed for codex/grok (no entry in results).
        // Disk-read fallback applies only in the --cached path, not when a probe was dispatched.
        XCTAssertEqual(
            windows.first { $0.source == "codex" }?.unknownReason,
            .parserFailed(observedAt: now),
            "codex probe dispatched → parserFailed (not disk data)"
        )
        XCTAssertEqual(
            windows.first { $0.source == "grok" }?.unknownReason,
            .parserFailed(observedAt: now),
            "grok probe dispatched → parserFailed (not disk data)"
        )

        for source in CapacityAcquisition.tier3ProbeableSources {
            let row = windows.first { $0.source == source }
            XCTAssertEqual(row?.unknownReason, .parserFailed(observedAt: now), source)
            XCTAssertNil(row?.usedPercent, source)
            XCTAssertNil(row?.remainingPercent, source)
        }
    }

    func testProbeRejectsVendorExposesNothingFromExecutor() {
        // Even a buggy executor claiming vendorExposesNothing is rewritten.
        let executor = FixtureProbeExecutor(results: [
            "agy": [
                CapacityWindow.unknown(
                    reason: .vendorExposesNothing,
                    source: "agy",
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ],
            "kimi": [
                CapacityWindow.unknown(
                    reason: .vendorExposesNothing,
                    source: "kimi",
                    scope: .weekly,
                    observedAt: now,
                    sourceTier: .tuiProbe
                ),
            ],
            "cursor_agent": [
                CapacityWindow.unknown(
                    reason: .vendorExposesNothing,
                    source: "cursor_agent",
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
        for source in CapacityAcquisition.tier3ProbeableSources {
            let row = windows.first { $0.source == source }
            XCTAssertNotEqual(row?.unknownReason, .vendorExposesNothing, source)
            XCTAssertEqual(row?.unknownReason, .parserFailed(observedAt: now), source)
        }
    }

    func testNeutralWorkingDirectoryUsesProbeScratch() {
        let path = CapacityProbe.neutralWorkingDirectory()
        XCTAssertNotNil(path)
        XCTAssertTrue(path?.contains("ProbeScratch") == true, "capacity probes must not inherit repo CWD")
    }

    func testLiveProbeMissingBinaryIsSpawnFailedNotZero() {
        // Force a non-existent binary — spawn fails closed with a distinct reason.
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
