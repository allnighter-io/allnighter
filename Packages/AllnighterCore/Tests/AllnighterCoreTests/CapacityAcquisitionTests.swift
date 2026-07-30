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

    func testTier3SourcesReturnVendorExposesNothing() {
        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let bySource = Dictionary(grouping: windows, by: \.source)

        for source in CapacityAcquisition.tier3DisklessSources {
            let group = bySource[source] ?? []
            XCTAssertEqual(group.count, 1, source)
            XCTAssertEqual(group[0].unknownReason, .vendorExposesNothing, source)
            XCTAssertNil(group[0].usedPercent, source)
            XCTAssertNil(group[0].remainingPercent, source)
            XCTAssertEqual(group[0].sourceTier, .tuiProbe, source)
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

        let windows = CapacityAcquisition.windows(homeRoot: homeRoot, now: now)
        let codex = windows.filter { $0.source == "codex" }
        let grok = windows.filter { $0.source == "grok" }
        XCTAssertEqual(codex.first?.usedPercent, 52.0)
        XCTAssertEqual(grok.first?.usedPercent, 42.0)
        XCTAssertEqual(
            windows.filter { $0.unknownReason == .vendorExposesNothing }.count,
            CapacityAcquisition.tier3DisklessSources.count
        )
    }
}
