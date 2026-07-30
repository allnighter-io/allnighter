import XCTest
@testable import AllnighterCore

/// Pure renderer tests. No IO, no wall clock — `now` is fixture-fixed.
final class CapacityStripRendererTests: XCTestCase {

    /// ~2026-07-30 00:48 UTC — matches the Grok log sample era.
    private let now = Date(timeIntervalSince1970: 1_753_833_600)

    // MARK: - Helpers

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
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        let codexIdx = plain.range(of: "Codex/ChatGPT")!.lowerBound
        let grokIdx = plain.range(of: "Grok")!.lowerBound
        let kimiIdx = plain.range(of: "Kimi")!.lowerBound
        XCTAssertTrue(codexIdx < grokIdx, "Codex before Grok")
        XCTAssertTrue(grokIdx < kimiIdx, "Grok before Kimi")
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

    // MARK: - Effective availability in short column

    func testKimiShortColumnShowsEffectiveZeroNotRawHundred() {
        let windows = [
            used(100, source: "kimi", scope: .weekly,
                 resetAt: now.addingTimeInterval(151_380)),
            used(0, source: "kimi", scope: .fiveHour,
                 resetAt: now.addingTimeInterval(3_780)),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        // Short column must show 0%, never 100%.
        XCTAssertTrue(plain.contains("Kimi"), plain)
        // Row line should include 0% for weekly and 0% for short.
        let kimiLine = plain.split(separator: "\n").first { $0.contains("Kimi") }.map(String.init) ?? ""
        XCTAssertTrue(kimiLine.contains("0%"), "expected 0% on Kimi line: \(kimiLine)")
        // Must not advertise raw 5h 100% in the short column.
        // Weekly is also 0%, so count 0% occurrences ≥ 1; forbid a 100% on that line.
        XCTAssertFalse(kimiLine.contains("100%"), "short column must not show raw 100%: \(kimiLine)")
    }

    func testGrokShortColumnIsDashNotBlank() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 planTier: "X Premium+"),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        let grokLine = plain.split(separator: "\n").first { $0.contains("Grok") }.map(String.init) ?? ""
        XCTAssertTrue(grokLine.contains("-"), "no short window → dash: \(grokLine)")
        XCTAssertTrue(grokLine.contains("X Premium+"), grokLine)
        XCTAssertTrue(grokLine.contains("58%"), "remaining headroom: \(grokLine)")
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
        XCTAssertTrue(plain.contains("never sampled"), plain)
    }

    // MARK: - Age on every row

    func testObservedAtAgeOnEveryKnownRow() {
        let windows = [
            used(42, source: "grok", scope: .weekly,
                 resetAt: now.addingTimeInterval(41 * 3600), precision: .exact,
                 observedAt: now.addingTimeInterval(-120)),
        ]
        let plain = CapacityStripRenderer.renderPlain(rows: rows(from: windows), now: now)
        let grokLine = plain.split(separator: "\n").first { $0.contains("Grok") }.map(String.init) ?? ""
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
}
