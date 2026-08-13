import XCTest
@testable import AllnighterCore

/// Pure renderer tests. No IO, no wall clock — `now` is fixture-fixed.
final class CapacityStripRendererTests: XCTestCase {

    /// ~2026-07-30 00:48 UTC — matches the Grok log sample era.
    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    // MARK: - Display names

    func testOpenCodeCLIDisplayNameIsOpenCodeNotOpenCodeGo() {
        // "Go" is the plan tier under the name; the CLI column is just OpenCode.
        XCTAssertEqual(CapacityStripRenderer.displayName(for: "opencode_go"), "OpenCode")
    }

    func testMeterLinesFlattenMultiPoolCLIIntoAdjacentSiblingRows() {
        let windows = [
            remaining(93, source: "agy", scope: .weekly,
                      resetAt: now.addingTimeInterval(6 * 86400),
                      poolLabel: "GEMINI MODELS"),
            remaining(60, source: "agy", scope: .weekly,
                      resetAt: now.addingTimeInterval(2 * 86400),
                      poolLabel: "CLAUDE AND GPT MODELS"),
            used(40, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(5 * 86400)),
        ]
        let rows = CapacityBenchProjection.rows(from: windows, now: now)
        let ordered = CapacityStripRenderer.ordered(rows: rows, notReadyOrParked: [])
        let lines = CapacityStripRenderer.CapacityMeterLine.flatten(rows: ordered)
        let titles = lines.map(\.title)
        XCTAssertEqual(
            titles,
            ["Codex/ChatGPT", "Antigravity · Gemini", "Antigravity · Claude/GPT"],
            "each measured pool is its own row; CLI siblings stay adjacent"
        )
        XCTAssertEqual(lines.filter { $0.source == "agy" }.count, 2)
        XCTAssertTrue(lines.first { $0.source == "agy" }?.isFirstOfSource == true)
        XCTAssertTrue(lines.last { $0.source == "agy" }?.isFirstOfSource == false)
    }

    // MARK: - Helpers

    /// The strip prints an "Expiring soon with headroom" banner above the table,
    /// and those lines carry seat names too. Row assertions must read the table,
    /// not the first line that happens to mention the seat.
    private func table(_ rendered: String) -> String {
        let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false)
        guard let separator = lines.firstIndex(where: { $0.hasPrefix("---") }) else {
            return rendered
        }
        return lines[lines.index(after: separator)...].joined(separator: "\n")
    }

    private func used(
        _ usedPercent: Double,
        source: String,
        scope: CapacityWindowScope,
        resetAt: Date?,
        precision: CapacityResetPrecision = .minute,
        observedAt: Date? = nil,
        poolLabel: String? = nil,
        planTier: String? = nil
    ) -> CapacityWindow {
        CapacityWindow(
            used: usedPercent,
            source: source,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: precision,
            observedAt: observedAt ?? now.addingTimeInterval(-120),
            sourceTier: .onDisk,
            poolLabel: poolLabel,
            planTier: planTier
        )
    }

    private func remaining(
        _ remainingPercent: Double,
        source: String,
        scope: CapacityWindowScope,
        resetAt: Date?,
        precision: CapacityResetPrecision = .minute,
        observedAt: Date? = nil,
        poolLabel: String? = nil,
        planTier: String? = nil
    ) -> CapacityWindow {
        CapacityWindow(
            remaining: remainingPercent,
            source: source,
            scope: scope,
            resetAt: resetAt,
            resetPrecision: precision,
            observedAt: observedAt ?? now.addingTimeInterval(-120),
            sourceTier: .tuiProbe,
            poolLabel: poolLabel,
            planTier: planTier
        )
    }

    private func rows(from windows: [CapacityWindow]) -> [CapacityBenchRow] {
        CapacityBenchProjection.rows(from: windows, now: now)
    }

    // MARK: - Fixed order

    func testFixedDisplayOrderNeverSortedByExpiry() {
        // Grok expires soonest; Codex last. Order must stay product order, not expiry.
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
            used(70, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(6 * 86400), precision: .exact,
                 planTier: "plus"),
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(1.5 * 86400)),
            used(0, source: "kimi", scope: .fiveHour,
                 resetAt: now.addingTimeInterval(3600)),
        ]
        let plain = table(CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now))
        let codexIdx = plain.range(of: "Codex/ChatGPT")!.lowerBound
        let grokIdx = plain.range(of: "Grok")!.lowerBound
        let kimiIdx = plain.range(of: "Kimi")!.lowerBound
        XCTAssertTrue(codexIdx < grokIdx, "Codex before Grok")
        XCTAssertTrue(grokIdx < kimiIdx, "Grok before Kimi")
    }

    // MARK: - Polarity is stated, not implied

    /// Claude and Grok print used, Codex prints left. Normalizing six vendors into
    /// one table means a bare number is unreadable without knowing which way we
    /// normalized — and the header does not survive a screenshotted row.
    func testEveryPercentCellStatesThatItIsCapacityLeft() {
        let windows = [
            used(53, source: "claude_code", scope: .weekly,
                 resetAt: now.addingTimeInterval(4 * 86400)),
            used(14, source: "claude_code", scope: .session,
                 resetAt: now.addingTimeInterval(4 * 3600)),
        ]
        let line = table(CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now))
            .split(separator: "\n").first { $0.contains("Claude") }.map(String.init) ?? ""
        XCTAssertTrue(line.contains("47% left"), "weekly must state polarity: \(line)")
        XCTAssertTrue(line.contains("86% left"), "short must state polarity: \(line)")
    }

    /// The widest realistic weekly cell must not lose its reset clock to `pad`'s
    /// hard cut — a silently clipped clock is the quiet lie this strip exists to
    /// avoid.
    func testWidestWeeklyCellKeepsItsResetClock() {
        let windows = [
            remaining(52.1, source: "agy", scope: .weekly,
                      resetAt: now.addingTimeInterval(20 * 3600 + 47 * 60)),
        ]
        let line = table(CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now))
            .split(separator: "\n").first { $0.contains("Antigravity") }.map(String.init) ?? ""
        XCTAssertTrue(line.contains("52.1% left"), line)
        XCTAssertTrue(line.contains("20h 47m"), "reset clock must survive padding: \(line)")
    }

    // MARK: - Expiring banner

    /// Same number as the strip's `left`, opposite valence: headroom you cannot
    /// reach before the reset is waste. Selection is `isHeroEligible`, so it stays
    /// silent unless there is genuinely something to lose.
    func testExpiringBannerNamesHeadroomOnASoonResettingWindow() {
        let windows = [
            // 30h out with 58% left → hero eligible.
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(30 * 3600), precision: .exact),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.hasPrefix("Expiring soon with headroom:"), plain)
        XCTAssertTrue(plain.contains("58% unused · resets 1d 6h"), plain)
        // The table below still speaks in `left`.
        XCTAssertTrue(table(plain).contains("58% left"), plain)
    }

    /// A window nowhere near its reset is not at risk, and an exhausted one has
    /// nothing left to lose. Neither earns a line.
    func testExpiringBannerStaysSilentWithoutRealHeadroomOrDeadline() {
        let distant = [
            used(10, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(6 * 86400), precision: .exact),
        ]
        XCTAssertFalse(
            CapacityStripRenderer.renderPlain(rows: rows(from: distant), now: now)
                .contains("Expiring soon")
        )

        let exhausted = [
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(20 * 3600)),
        ]
        XCTAssertFalse(
            CapacityStripRenderer.renderPlain(rows: rows(from: exhausted), now: now)
                .contains("Expiring soon")
        )
    }

    /// Claude primary nearly exhausted while Fable still has headroom — banner must
    /// stay silent; Fable is not actionable when the binding pool is at 4%.
    func testExpiringBannerIgnoresSubPoolWhenPrimaryNearlyExhausted() {
        let reset = now.addingTimeInterval(29 * 3600)
        let windows = [
            remaining(4, source: "claude_code", scope: .weekly, resetAt: reset,
                      planTier: "Max"),
            remaining(82, source: "claude_code", scope: .weekly, resetAt: reset,
                      poolLabel: "Fable", planTier: "Max"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertFalse(plain.contains("Expiring soon"), plain)
        XCTAssertFalse(plain.contains("82% unused"), plain)
    }

    /// A pooled seat's banner label is longer than the table's name column, and
    /// borrowing that width hard-cut it to "Antigravity Clau".
    func testExpiringBannerDoesNotClipAPooledSeatLabel() {
        let windows = [
            used(48, source: "agy", scope: .weekly,
                 resetAt: now.addingTimeInterval(29 * 3600), poolLabel: "Claude/GPT"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.contains("Antigravity Claude/GPT"), plain)
    }

    /// Soonest reset first — that is the capacity you lose first.
    func testExpiringBannerOrdersBySoonestReset() {
        let windows = [
            used(30, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(40 * 3600), precision: .exact),
            used(30, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(20 * 3600), precision: .exact),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        let banner = plain.split(separator: "\n").prefix { !$0.hasPrefix("CLI") }.joined(separator: "\n")
        let grokIdx = banner.range(of: "Grok")!.lowerBound
        let codexIdx = banner.range(of: "Codex")!.lowerBound
        XCTAssertTrue(grokIdx < codexIdx, "soonest reset first: \(banner)")
    }

    func testNotReadyOrParkedSeatsLast() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact),
            used(50, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(86400), precision: .exact),
        ]
        let ordered = CapacityStripRenderer.ordered(
            rows: rows(from: windows),
            notReadyOrParked: ["codex"]
        )
        XCTAssertEqual(ordered.map(\.source), ["grok", "codex"])
    }

    // MARK: - Short column reports the short window

    /// Exhaustion is a hard gate. Kimi's vendor surface prints `100%` on a 5h
    /// window sitting under a spent weekly; repeating that would invite seating a
    /// seat that fails on first dispatch. We claim to be more honest than the
    /// vendor surface, so 0 available reads as 0.
    func testKimiShortColumnReadsZeroUnderAnExhaustedWeekly() {
        let windows = [
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(151_380)),
            used(0, source: "kimi", scope: .fiveHour,
                 resetAt: now.addingTimeInterval(3_780)),
        ]
        let projected = rows(from: windows)
        let plain = CapacityStripRenderer.renderPlain(rows: projected, now: now)
        let kimiLine = table(plain).split(separator: "\n").first { $0.contains("Kimi") }.map(String.init) ?? ""
        XCTAssertTrue(kimiLine.contains("0% left"), "weekly must read 0% left: \(kimiLine)")
        XCTAssertFalse(kimiLine.contains("100%"), "must not repeat the vendor's 100%: \(kimiLine)")
        XCTAssertEqual(projected.first?.effectiveRemainingPercent, 0)
        XCTAssertEqual(CapacityStripRenderer.color(for: projected[0], now: now), .red)

        let jsonRow = CapacityStripRenderer.json(rows: projected, now: now).rows[0]
        XCTAssertEqual(jsonRow.shortRemainingPercent, 0)
    }

    /// agy carries independent quota pools on one row. Claude/GPT weekly at 0%
    /// must not zero Gemini's 5h column — that was the founder-visible bug when
    /// Gemini still showed ~98% in the vendor `/usage` screen.
    func testAgyExhaustedSiblingPoolDoesNotZeroGeminiShortColumn() {
        let geminiWeeklyReset = now.addingTimeInterval(6 * 86400 + 18 * 3600)
        let geminiFiveHourReset = now.addingTimeInterval(4 * 3600 + 35 * 60)
        let claudeWeeklyReset = now.addingTimeInterval(4 * 86400 + 2 * 3600)
        let windows = [
            remaining(99.4, source: "agy", scope: .weekly, resetAt: geminiWeeklyReset,
                      poolLabel: "Gemini Models"),
            remaining(98.24, source: "agy", scope: .fiveHour, resetAt: geminiFiveHourReset,
                      poolLabel: "Gemini Models"),
            remaining(0, source: "agy", scope: .weekly, resetAt: claudeWeeklyReset,
                      poolLabel: "Claude and GPT models"),
        ]
        let projected = rows(from: windows)
        let jsonRow = CapacityStripRenderer.json(rows: projected, now: now).rows[0]
        XCTAssertEqual(jsonRow.pools[0].shortRemainingPercent ?? -1, 98.24, accuracy: 0.01)
        XCTAssertEqual(jsonRow.pools[1].dashboardRemainingPercent, 0)
        XCTAssertTrue(jsonRow.pools[1].shortWindowNone)

        let plain = CapacityStripRenderer.renderPlain(rows: projected, now: now)
        let geminiLine = table(plain).split(separator: "\n").first { $0.contains("Gemini") }.map(String.init) ?? ""
        XCTAssertTrue(geminiLine.contains("98.2% left") || geminiLine.contains("98% left"),
                      "Gemini 5h must survive sibling exhaustion: \(geminiLine)")
    }

    /// The gate is exhaustion, not `min()`. A weekly and a 5h percentage have
    /// different denominators, so a merely-tighter weekly must not overwrite the
    /// short window's real number — that is what blanked the Claude 5h figure.
    func testTighterButLiveWeeklyDoesNotOverwriteTheShortNumber() {
        let windows = [
            used(53, source: "claude_code", scope: .weekly,
                 resetAt: now.addingTimeInterval(4 * 86400)),
            used(14, source: "claude_code", scope: .session,
                 resetAt: now.addingTimeInterval(4 * 3600)),
        ]
        let projected = rows(from: windows)
        let line = table(CapacityStripRenderer.renderPlain(rows: projected, now: now))
            .split(separator: "\n").first { $0.contains("Claude") }.map(String.init) ?? ""
        XCTAssertTrue(line.contains("47% left"), line)
        XCTAssertTrue(line.contains("86% left"), "tighter weekly must not floor the session: \(line)")
    }

    /// A wholly-unknown Claude row (bare `alln capacity` never probes tier-3)
    /// printed `-` in the 5h cell — indistinguishable from Grok, which has no
    /// short limit at all. The seat's short limit does not stop existing because
    /// we declined to look.
    func testWhollyUnknownClaudeRowDoesNotClaimNoShortLimit() {
        let windows = [
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let projected = rows(from: windows)
        let line = table(CapacityStripRenderer.renderPlain(rows: projected, now: now))
            .split(separator: "\n").first { $0.contains("Claude") }.map(String.init) ?? ""
        XCTAssertTrue(
            line.contains("not checked yet") || line.contains("not yet"),
            "expected unsampled short cell: \(line)"
        )

        let jsonRow = CapacityStripRenderer.json(rows: projected, now: now).rows[0]
        XCTAssertFalse(jsonRow.shortWindowNone)
        XCTAssertNil(jsonRow.shortRemainingPercent)
    }

    /// CWB-S00b — disabled (feature OFF) rows are loud, not blank or zero-filled.
    func testDisabledRowRendersLoudlyInPlainAndJSON() {
        let windows = [
            CapacityWindow.unknown(
                reason: .disabled,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let projected = rows(from: windows)
        let line = table(CapacityStripRenderer.renderPlain(rows: projected, now: now))
            .split(separator: "\n").first { $0.contains("Claude") }.map(String.init) ?? ""
        XCTAssertTrue(line.contains("disabled"), "disabled row must say disabled: \(line)")

        let jsonRow = CapacityStripRenderer.json(rows: projected, now: now).rows[0]
        XCTAssertEqual(jsonRow.unknownReason, .disabled)
    }

    /// The founder-visible Claude case: session 86% remaining under a 47% weekly
    /// rendered `47%` in a column headed `5h`, so the 5h limit was never shown.
    func testClaudeSessionColumnShowsSessionNotWeekly() {
        let windows = [
            used(53, source: "claude_code", scope: .weekly,
                 resetAt: now.addingTimeInterval(4 * 86400)),
            used(14, source: "claude_code", scope: .session,
                 resetAt: now.addingTimeInterval(4 * 3600)),
        ]
        let projected = rows(from: windows)
        let line = table(CapacityStripRenderer.renderPlain(rows: projected, now: now))
            .split(separator: "\n").first { $0.contains("Claude") }.map(String.init) ?? ""
        XCTAssertTrue(line.contains("47%"), "expected weekly 47% on Claude line: \(line)")
        XCTAssertTrue(line.contains("86%"), "expected session 86% in the 5h column: \(line)")
    }

    /// A seat with no 5h limit says so. Never blank — blank already means "not
    /// applicable to this line" on a pooled seat's continuation rows, and an empty
    /// cell reads as a rendering failure rather than a claim.
    func testGrokShortColumnSaysNotApplicableNotBlank() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        let grokLine = table(plain).split(separator: "\n").first { $0.contains("Grok") }.map(String.init) ?? ""
        XCTAssertTrue(grokLine.contains("n/a"), "no short window → n/a: \(grokLine)")
        XCTAssertTrue(grokLine.contains("X Premium+"), grokLine)
        XCTAssertTrue(grokLine.contains("58% left"), "remaining headroom: \(grokLine)")
    }

    /// Three states, three glyphs. `n/a` (no such limit) must never be confusable
    /// with `unknown` (has one, unsampled) or a number.
    func testNoShortLimitAndUnsampledShortLimitReadDifferently() {
        let noLimit = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact),
        ]
        let unsampled = [
            used(53, source: "claude_code", scope: .weekly,
                 resetAt: now.addingTimeInterval(4 * 86400)),
        ]
        let grokLine = table(CapacityStripRenderer.renderPlain(rows: rows(from: noLimit), now: now))
            .split(separator: "\n").first { $0.contains("Grok") }.map(String.init) ?? ""
        let claudeLine = table(CapacityStripRenderer.renderPlain(rows: rows(from: unsampled), now: now))
            .split(separator: "\n").first { $0.contains("Claude") }.map(String.init) ?? ""
        XCTAssertTrue(grokLine.contains("n/a"), grokLine)
        XCTAssertFalse(grokLine.contains("unknown"), grokLine)
        XCTAssertTrue(claudeLine.contains("unknown") || claudeLine.contains("not yet"), claudeLine)
        XCTAssertFalse(claudeLine.contains("n/a"), claudeLine)
    }

    // MARK: - Unknown reasons read differently

    func testUnknownReasonsRenderDistinctCopy() {
        let windows = [
            CapacityWindow.unknown(
                reason: .vendorExposesNothing,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
            CapacityWindow.unknown(
                reason: .parserFailed(observedAt: now),
                source: "cursor_agent",
                scope: .monthly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "kimi",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.contains("no usage surface"), plain)
        XCTAssertTrue(plain.contains("parser failed"), plain)
        // Compact day stamp — never mid-cut year as "parser failed 202".
        XCTAssertFalse(plain.contains("parser failed 202"), plain)
        XCTAssertTrue(plain.contains("not checked yet"), plain)
        XCTAssertFalse(plain.contains("never sampled"), plain)
    }

    // MARK: - Age on every row

    func testObservedAtAgeOnEveryKnownRow() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 observedAt: now.addingTimeInterval(-120)),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        let grokLine = table(plain).split(separator: "\n").first { $0.contains("Grok") }.map(String.init) ?? ""
        XCTAssertTrue(grokLine.contains("ago") || grokLine.contains("now"), "age required: \(grokLine)")
    }

    // MARK: - Relative clocks

    func testRelativeClockFormats() {
        XCTAssertEqual(
            CapacityStripRenderer.relativeClock(from: now, to: now.addingTimeInterval(6 * 86400 + 3 * 3600)),
            "6d 3h"
        )
        XCTAssertEqual(
            CapacityStripRenderer.relativeClock(from: now, to: now.addingTimeInterval(3 * 3600 + 21 * 60)),
            "3h 21m"
        )
        XCTAssertEqual(
            CapacityStripRenderer.relativeClock(from: now, to: now.addingTimeInterval(41 * 3600)),
            "1d 17h"
        )
        XCTAssertEqual(
            CapacityStripRenderer.relativeClock(from: now, to: now.addingTimeInterval(-10)),
            "now"
        )
    }

    // MARK: - Non-TTY: zero ANSI

    func testPlainOutputContainsNoANSIEscapes() {
        let windows = [
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(151_380)),
            used(0, source: "kimi", scope: .fiveHour,
                 resetAt: now.addingTimeInterval(3_780)),
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
            remaining(0, source: "codex", scope: .weekly,
                      resetAt: now.addingTimeInterval(86400), precision: .exact,
                      planTier: "plus"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertFalse(plain.contains("\u{1B}"), "non-TTY must have zero ANSI: \(plain)")
        // No box-drawing either.
        for ch in ["│", "─", "┌", "┐", "└", "┘", "█", "░", "▓"] {
            XCTAssertFalse(plain.contains(ch), "box/block glyph \(ch) banned in plain")
        }
    }

    /// CAP-S06: the CLI non-TTY path is project → renderPlain (never renderTTY).
    /// Captured into other agents' context windows — zero ANSI is inviolable.
    func testCLINonTTYPathCompositionEmitsNoANSIEscapes() {
        let windows = [
            used(70, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(6 * 86400), precision: .exact,
                 planTier: "plus"),
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
            CapacityWindow.unknown(
                reason: .vendorExposesNothing,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
            CapacityWindow.unknown(
                reason: .vendorExposesNothing,
                source: "cursor_agent",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        // Same composition as `alln capacity` when stdout is not a TTY.
        let projected = CapacityBenchProjection.rows(from: windows, now: now)
        let plain = CapacityStripRenderer.renderPlain(rows: projected, now: now)
        XCTAssertFalse(plain.contains("\u{1B}"), "CLI plain path must have zero ANSI: \(plain)")
        XCTAssertFalse(plain.isEmpty)
    }

    func testTTYMayContainANSIForAmberOrRed() {
        // Grok hero-eligible → amber → ANSI on TTY path.
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact),
        ]
        let tty = CapacityStripRenderer.renderTTY(rows: rows(from: windows), now: now)
        XCTAssertTrue(tty.contains("\u{1B}"), "TTY amber/red may use ANSI")
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertFalse(plain.contains("\u{1B}"))
    }

    // MARK: - Plan tier alongside name

    func testPlanTierRenderedAlongsideSeat() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
            used(52, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(6 * 86400), precision: .exact,
                 planTier: "plus"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.contains("X Premium+"), plain)
        XCTAssertTrue(plain.contains("plus"), plain)
    }

    // MARK: - JSON shape

    func testJSONShapeCodableAndOrdered() throws {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(151_380)),
            used(0, source: "kimi", scope: .fiveHour,
                 resetAt: now.addingTimeInterval(3_780)),
            CapacityWindow.unknown(
                reason: .vendorExposesNothing,
                source: "claude_code",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let payload = CapacityStripRenderer.json(rows: rows(from: windows), now: now)
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.contractVersion, ContractRegistry.contractVersion)
        XCTAssertEqual(payload.generatedAt, now)
        // Order: codex absent, so claude, grok, kimi among present.
        XCTAssertEqual(payload.rows.map(\.source), ["claude_code", "grok", "kimi"])

        let kimi = payload.rows.first { $0.source == "kimi" }!
        XCTAssertEqual(kimi.effectiveRemainingPercent, 0.0)
        // Short reports available capacity: the spent weekly gates the 5h window,
        // so the machine surface must not repeat the vendor's raw 100% either.
        XCTAssertEqual(kimi.shortRemainingPercent, 0.0)
        XCTAssertFalse(kimi.shortWindowNone)

        let grok = payload.rows.first { $0.source == "grok" }!
        XCTAssertEqual(grok.dashboardRemainingPercent, 58.0)
        XCTAssertTrue(grok.shortWindowNone)
        XCTAssertNil(grok.shortRemainingPercent)
        XCTAssertEqual(grok.planTier, "X Premium+")
        XCTAssertEqual(grok.color, .amber)
        XCTAssertNotNil(grok.observedAgeSeconds)

        let claude = payload.rows.first { $0.source == "claude_code" }!
        XCTAssertEqual(claude.unknownReason, .vendorExposesNothing)

        // Round-trip Codable (not ContractRegistry).
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CapacityStripJSON.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testColorRedWhenEmptyAmberWhenExpiringNeutralOtherwise() {
        let empty = rows(from: [
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(86400)),
        ])[0]
        XCTAssertEqual(CapacityStripRenderer.color(for: empty, now: now), .red)

        let expiring = rows(from: [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact),
        ])[0]
        XCTAssertEqual(CapacityStripRenderer.color(for: expiring, now: now), .amber)

        let roomy = rows(from: [
            used(30, source: "codex", scope: .weekly,
                 resetAt: now.addingTimeInterval(6 * 86400), precision: .exact),
        ])[0]
        XCTAssertEqual(CapacityStripRenderer.color(for: roomy, now: now), .neutral)
    }

    func testWidthDegradesGracefullyBelowDefault() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
        ]
        let narrow = CapacityStripRenderer.renderPlain(
            rows: rows(from: windows), now: now, width: 40
        )
        XCTAssertFalse(narrow.isEmpty)
        XCTAssertFalse(narrow.contains("\u{1B}"))
        XCTAssertTrue(narrow.contains("Grok") || narrow.contains("Gro"), narrow)
    }

    func testAgyMultiPoolRendersTwoDashboardLines() {
        let windows = [
            remaining(92.67, source: "agy", scope: .weekly,
                      resetAt: now.addingTimeInterval(593_400),
                      poolLabel: "GEMINI MODELS"),
            remaining(58.48, source: "agy", scope: .fiveHour,
                      resetAt: now.addingTimeInterval(12_060),
                      poolLabel: "GEMINI MODELS"),
            remaining(60.11, source: "agy", scope: .weekly,
                      resetAt: now.addingTimeInterval(186_480),
                      poolLabel: "CLAUDE AND GPT MODELS"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.contains("Antigravity"), plain)
        XCTAssertTrue(plain.contains("Gemini") || plain.contains("GEMINI"), plain)
        // Two lines for two pools.
        let agyLines = plain.split(separator: "\n").filter {
            $0.contains("Antigravity") || $0.contains("Gemini") || $0.contains("Claude/GPT")
        }
        XCTAssertGreaterThanOrEqual(agyLines.count, 2, plain)
    }

    func testNotConfiguredOpenCodeGoSaysNotSetUpAndCarriesConfigureCommand() {
        let windows = [
            CapacityWindow.unknown(
                reason: .notConfigured,
                source: "opencode_go",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape,
                planTier: "Go"
            ),
        ]
        let projected = rows(from: windows)
        let plain = CapacityStripRenderer.renderPlain(rows: projected, now: now)
        XCTAssertTrue(plain.contains("not set up"), plain)
        XCTAssertTrue(plain.contains(CapacityUnknownRemedy.configureOpenCodeGoCommand), plain)
        XCTAssertFalse(plain.contains("never sampled"), plain)

        let jsonRow = CapacityStripRenderer.json(rows: projected, now: now)
            .rows.first { $0.source == "opencode_go" }
        XCTAssertEqual(jsonRow?.unknownReason, .notConfigured)
        XCTAssertEqual(jsonRow?.nextAction?.kind, "configureCapacity")
        XCTAssertEqual(jsonRow?.nextAction?.command, CapacityUnknownRemedy.configureOpenCodeGoCommand)
        XCTAssertNil(jsonRow?.dashboardRemainingPercent)
    }

    func testNotInstalledRowSaysNotInstalledAndCarriesInstallCommand() {
        let windows = [
            CapacityWindow.unknown(
                reason: .notInstalled,
                source: "agy",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let projected = rows(from: windows)
        let plain = CapacityStripRenderer.renderPlain(rows: projected, now: now)
        XCTAssertTrue(plain.contains("not installed"), plain)

        let jsonRow = CapacityStripRenderer.json(rows: projected, now: now)
            .rows.first { $0.source == "agy" }
        XCTAssertEqual(jsonRow?.unknownReason, .notInstalled)
        if let next = jsonRow?.nextAction {
            XCTAssertEqual(next.kind, "installCLI")
            XCTAssertFalse(next.command.isEmpty)
        }
    }

    func testOverlayPromotesNeverSampledDashboardToNotConfigured() {
        let windows = [
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "opencode_go",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape,
                planTier: "Go"
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "bailian_token_plan",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape
            ),
        ]
        let refined = CapacityUnknownRefinement.overlayKnownCauses(
            windows,
            now: now,
            pathEnvironment: "/tmp/alln-empty-path",
            homeDirectory: URL(fileURLWithPath: "/tmp/alln-empty-home", isDirectory: true),
            probeRecords: []
        )
        XCTAssertEqual(refined[0].unknownReason, .notConfigured)
        XCTAssertEqual(refined[1].unknownReason, .notConfigured)
    }

    func testOverlayInstallRecordBeatsDashboardNotConfigured() {
        let windows = [
            CapacityWindow.unknown(
                reason: .notConfigured,
                source: "bailian_token_plan",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "opencode_go",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape,
                planTier: "Go"
            ),
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "agy",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let refined = CapacityUnknownRefinement.overlayKnownCauses(
            windows,
            now: now,
            pathEnvironment: "/tmp/alln-empty-path",
            homeDirectory: URL(fileURLWithPath: "/tmp/alln-empty-home", isDirectory: true),
            probeRecords: [
                ToolProbeRecord(driverId: "qwen", status: .notInstalled, lastProbeAt: now),
                ToolProbeRecord(
                    driverId: "opencode",
                    status: .ready(version: "1.18.16"),
                    lastProbeAt: now
                ),
                ToolProbeRecord(driverId: "antigravity", status: .notInstalled, lastProbeAt: now),
            ]
        )
        XCTAssertEqual(refined[0].unknownReason, .notInstalled)
        XCTAssertEqual(refined[1].unknownReason, .notConfigured)
        XCTAssertEqual(refined[2].unknownReason, .notInstalled)
    }

    func testOverlayPtyMissingBinaryStillNotInstalledWithoutRecord() {
        let windows = [
            CapacityWindow.unknown(
                reason: .neverSampled,
                source: "agy",
                scope: .weekly,
                observedAt: now,
                sourceTier: .tuiProbe
            ),
        ]
        let refined = CapacityUnknownRefinement.overlayKnownCauses(
            windows,
            now: now,
            pathEnvironment: "/tmp/alln-empty-path",
            homeDirectory: URL(fileURLWithPath: "/tmp/alln-empty-home", isDirectory: true),
            probeRecords: []
        )
        XCTAssertEqual(refined[0].unknownReason, .notInstalled)
    }

    func testOverlayDoesNotInventNotInstalledWithoutAProbeRecord() {
        let windows = [
            CapacityWindow.unknown(
                reason: .notConfigured,
                source: "bailian_token_plan",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape
            ),
        ]
        let refined = CapacityUnknownRefinement.overlayKnownCauses(
            windows,
            now: now,
            pathEnvironment: "/tmp/alln-empty-path",
            homeDirectory: URL(fileURLWithPath: "/tmp/alln-empty-home", isDirectory: true),
            probeRecords: []
        )
        XCTAssertEqual(refined[0].unknownReason, .notConfigured)
    }

    func testCapacitySourceDriverIdsMapDashboardSeatsToTheCLI() {
        XCTAssertEqual(CapacityUnknownRemedy.driverId(forCapacitySource: "agy"), "antigravity")
        XCTAssertEqual(CapacityUnknownRemedy.driverId(forCapacitySource: "opencode_go"), "opencode")
        XCTAssertEqual(
            CapacityUnknownRemedy.driverId(forCapacitySource: "bailian_token_plan"),
            "qwen"
        )
        XCTAssertEqual(CapacityUnknownRemedy.driverId(forCapacitySource: "codex"), "codex")
    }

    func testNotInstalledBailianQwenCarriesQwenInstallCommandNotConfigure() {
        let windows = [
            CapacityWindow.unknown(
                reason: .notInstalled,
                source: "bailian_token_plan",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape
            ),
        ]
        let jsonRow = CapacityStripRenderer.json(rows: rows(from: windows), now: now)
            .rows.first { $0.source == "bailian_token_plan" }
        XCTAssertEqual(jsonRow?.unknownReason, .notInstalled)
        XCTAssertEqual(jsonRow?.nextAction?.kind, "installCLI")
        XCTAssertNotEqual(jsonRow?.nextAction?.command, CapacityUnknownRemedy.configureBailianCommand)
        let command = jsonRow?.nextAction?.command ?? ""
        XCTAssertFalse(command.isEmpty)
        XCTAssertFalse(command.contains("bailian-token-plan"), command)
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.contains("not installed"), plain)
        XCTAssertFalse(plain.contains("not set up"), plain)
    }

    func testNotConfiguredBailianQwenCarriesConfigureCommand() {
        let windows = [
            CapacityWindow.unknown(
                reason: .notConfigured,
                source: "bailian_token_plan",
                scope: .weekly,
                observedAt: now,
                sourceTier: .dashboardScrape
            ),
        ]
        let jsonRow = CapacityStripRenderer.json(rows: rows(from: windows), now: now)
            .rows.first { $0.source == "bailian_token_plan" }
        XCTAssertEqual(jsonRow?.unknownReason, .notConfigured)
        XCTAssertEqual(jsonRow?.nextAction?.command, CapacityUnknownRemedy.configureBailianCommand)
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        XCTAssertTrue(plain.contains("Qwen"), plain)
        XCTAssertTrue(plain.contains("not set up"), plain)
    }
}
