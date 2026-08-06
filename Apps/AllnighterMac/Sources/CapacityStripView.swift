import SwiftUI
import AllnighterCore

/// Column geometry for the bench table — **one** definition, read by the column
/// headers and by every row.
///
/// A width declared in two places is a width that drifts. The weekly bars used
/// to start at a different x on every row because single-pool and multi-pool
/// lines were separate views with separate constants; both now render through
/// `weeklyPoolLine` against these numbers, so the bars share one left edge and
/// are actually comparable down the column.
private enum CapacityStripLayout {
    // Outer table columns.
    static let rowInset: CGFloat = 24
    /// Headers sit slightly inboard of the rows — the row's leading chevron is
    /// chrome, not a column, so the label lines up with the CLI glyph instead.
    static let headerInset: CGFloat = 34
    static let columnGap: CGFloat = 18
    static let shortWidth: CGFloat = 88
    static let ageWidth: CGFloat = 72

    // Weekly-cell sub-columns. Every pool line uses all four, always.
    static let poolLabelWidth: CGFloat = 62
    static let barWidth: CGFloat = 68
    static let percentWidth: CGFloat = 46
    static let resetWidth: CGFloat = 54
    static let cellGap: CGFloat = 10

    /// Pool lines are fixed-height so the weekly and 5h columns stay on shared
    /// baselines however many pools a row carries.
    static let poolLineHeight: CGFloat = 18
    static let poolLineSpacing: CGFloat = 8
}

/// Launch-surface capacity strip — renders the same Core projection the CLI prints.
///
/// Locked product law (`docs/phases/CLI_Capacity_TUI_Sampling.md` §Launch surface):
/// one row per CLI, fixed order, weekly bars + 5h numbers, age chip = per-row
/// refresh, three colours only (neutral / amber / red), no status dots, no green.
struct CapacityStripView: View {
    @Bindable var model: CapacityStripModel
    /// Optional CTA: hero "Start a run on X" focuses the composer seat.
    var onHeroStart: ((String) -> Void)? = nil

    @State private var expandedSources: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if model.featureEnabled {
                heroZone
                stripHeader
                columnHeaders
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows, id: \.source) { row in
                            CapacityStripRowView(
                                row: row,
                                now: model.now,
                                isRefreshing: model.isRefreshing(row.source),
                                isDimmed: model.notReadyOrParked.contains(row.source),
                                isExpanded: expandedSources.contains(row.source),
                                onToggleExpand: { toggleExpand(row.source) },
                                onRefresh: { model.refreshSource(row.source) }
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                disabledState
            }
        }
        .background(ALColor.base)
    }

    // MARK: - Feature OFF (CWB-S01b): Enable CTA, zero rows, zero probes

    private var disabledState: some View {
        VStack(spacing: 14) {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ALColor.textFaint)
            VStack(spacing: 6) {
                Text("Capacity is off")
                    .font(ALFont.sans(16, .semibold))
                    .foregroundStyle(ALColor.textSecondary)
                Text("Allnighter checks each CLI's weekly and 5-hour windows every 30 minutes\nwhile the app is open — silently, no toasts, no Dock bounce.")
                    .font(ALFont.sans(12))
                    .foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            Button {
                model.enableFeature()
            } label: {
                Text("Enable capacity")
                    .font(ALFont.sans(12, .semibold))
                    .foregroundStyle(ALColor.textOnAmber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(ALColor.accent, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Hero (fixed height — layout never shifts)

    private var heroZone: some View {
        Group {
            if let hero = model.hero {
                liveHero(hero)
            } else if model.isRefreshingAll {
                refreshingHero
            } else {
                calmHero
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(heroBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
    }

    private var heroBackground: some View {
        Group {
            if model.hero != nil {
                LinearGradient(
                    colors: [
                        ALColor.accent.opacity(0.10),
                        ALColor.accent.opacity(0.02),
                        ALColor.base,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                ALColor.base
            }
        }
    }

    private func liveHero(_ hero: CapacityHeroPresentation) -> some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ALColor.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Use it before you lose it")
                        .font(ALFont.sans(10, .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(ALColor.accentText)
                    (
                        Text("\(hero.displayName) — ")
                            .foregroundStyle(ALColor.textPrimary)
                        + Text(CapacityStripRenderer.formatPercent(hero.remainingPercent))
                            .foregroundStyle(ALPalette.amber400)
                        + Text(" of your week expires in ")
                            .foregroundStyle(ALColor.textPrimary)
                        + Text(clockText(hero.resetAt))
                            .foregroundStyle(ALPalette.amber400)
                    )
                    .font(ALFont.sans(22, .bold))
                    .tracking(-0.3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    HStack(spacing: 6) {
                        if let plan = hero.planTier {
                            Text(plan).foregroundStyle(ALColor.textMuted)
                        }
                        if let reset = hero.resetAt {
                            Text("· resets \(CapacityStripRenderer.relativeClock(from: model.now, to: reset))")
                                .foregroundStyle(ALColor.textMuted)
                        }
                    }
                    .font(ALFont.mono(11))
                    if let also = hero.alsoLine {
                        Text(also)
                            .font(ALFont.sans(11))
                            .foregroundStyle(ALColor.textFaint)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 12)
            if let onHeroStart {
                Button {
                    onHeroStart(hero.source)
                } label: {
                    Text("Start a run on \(hero.displayName)")
                        .font(ALFont.sans(12, .semibold))
                        .foregroundStyle(ALColor.textOnAmber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(ALColor.accent, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var refreshingHero: some View {
        HStack(alignment: .top, spacing: 14) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text("Checking your bench")
                    .font(ALFont.sans(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(ALColor.textFaint)
                Text("Refreshing capacity…")
                    .font(ALFont.sans(20, .semibold))
                    .foregroundStyle(ALColor.textSecondary)
                Text("Same path as alln capacity — live acquire in flight")
                    .font(ALFont.mono(11))
                    .foregroundStyle(ALColor.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var calmHero: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: model.needsLiveRefresh ? "arrow.clockwise.circle" : "checkmark")
                .font(.system(size: model.needsLiveRefresh ? 18 : 16, weight: .semibold))
                .foregroundStyle(model.needsLiveRefresh ? ALColor.accentText : ALColor.textFaint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.needsLiveRefresh ? "Tap Refresh for live capacity" : "Nothing expiring")
                    .font(ALFont.sans(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(model.needsLiveRefresh ? ALColor.accentText : ALColor.textFaint)
                Text(model.needsLiveRefresh ? "Numbers appear after a live probe" : "Everything has room")
                    .font(ALFont.sans(20, .semibold))
                    .foregroundStyle(ALColor.textSecondary)
                Text(model.needsLiveRefresh
                     ? "Same path as alln capacity — live PTY, no stale history"
                     : "No seat drops below the 48h mark with headroom left")
                    .font(ALFont.mono(11))
                    .foregroundStyle(ALColor.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private func clockText(_ resetAt: Date?) -> String {
        guard let resetAt else { return "—" }
        return CapacityStripRenderer.relativeClock(from: model.now, to: resetAt)
    }

    // MARK: - Strip chrome

    private var stripHeader: some View {
        HStack(alignment: .center) {
            Text("Your bench")
                .font(ALFont.sans(11, .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(ALColor.textFaint)
            Spacer()
            Text(summaryLine)
                .font(ALFont.sans(11))
                .foregroundStyle(ALColor.textFaint)
            Button {
                model.refreshAll()
            } label: {
                HStack(spacing: 5) {
                    if model.isRefreshingAll {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Refresh")
                        .font(ALFont.sans(11, .medium))
                }
                .foregroundStyle(ALColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: ALRadius.sm)
                        .strokeBorder(ALColor.borderDefault, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshingAll)
            .help("Refresh every seat so the strip stays comparable")
            Button {
                model.disableFeature()
            } label: {
                Text("Turn off")
                    .font(ALFont.sans(11, .medium))
                    .foregroundStyle(ALColor.textFaint)
            }
            .buttonStyle(.plain)
            .help("Stop all capacity checks — no probes until you enable it again")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var summaryLine: String {
        let total = model.rows.count
        let unknown = model.rows.filter { $0.unknownReason != nil }.count
        let down = model.notReadyOrParked.count
        let sampled = total - unknown - down
        return "\(total) CLIs · \(max(0, sampled)) sampled · \(unknown) unknown"
    }

    private var columnHeaders: some View {
        HStack(spacing: CapacityStripLayout.columnGap) {
            Text("CLI")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Weekly headroom")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("5h window")
                .frame(width: CapacityStripLayout.shortWidth, alignment: .leading)
            Text("")
                .frame(width: CapacityStripLayout.ageWidth, alignment: .trailing)
        }
        .font(ALFont.sans(10, .semibold))
        .tracking(0.8)
        .textCase(.uppercase)
        .foregroundStyle(ALColor.textFaint)
        .padding(.horizontal, CapacityStripLayout.headerInset)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
    }

    private func toggleExpand(_ source: String) {
        if expandedSources.contains(source) {
            expandedSources.remove(source)
        } else {
            expandedSources.insert(source)
        }
    }
}

// MARK: - Row

private struct CapacityStripRowView: View {
    let row: CapacityBenchRow
    let now: Date
    let isRefreshing: Bool
    let isDimmed: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRefresh: () -> Void

    private var color: CapacityStripColor {
        CapacityStripRenderer.color(for: row, now: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: CapacityStripLayout.columnGap) {
                cliColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                weeklyColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                shortColumn
                    .frame(width: CapacityStripLayout.shortWidth, alignment: .leading)
                ageChip
                    .frame(width: CapacityStripLayout.ageWidth, alignment: .trailing)
            }
            .padding(.horizontal, CapacityStripLayout.rowInset)
            .padding(.vertical, 12)
            .opacity(isDimmed ? 0.42 : 1)

            if isExpanded {
                detailDisclosure
                    .padding(.horizontal, CapacityStripLayout.rowInset)
                    .padding(.bottom, 12)
            }
        }
        .background(isExpanded ? ALColor.subtle : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
    }

    // MARK: CLI name + plan + disclosure

    private var cliColumn: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ALColor.textFaint)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .help("Show provenance")

            DriverBrandGlyph(
                driverId: glyphDriverId(row.source),
                boxSize: 20,
                iconSize: 11,
                cornerRadius: 5,
                muted: isDimmed
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(CapacityStripRenderer.displayName(for: row.source))
                    .font(ALFont.sans(13, .medium))
                    .foregroundStyle(ALColor.textPrimary)
                if let plan = row.planTier, !plan.isEmpty {
                    Text(plan)
                        .font(ALFont.sans(10))
                        .foregroundStyle(ALColor.textFaint)
                } else if row.pools.count > 1 {
                    Text(poolSummary)
                        .font(ALFont.sans(10))
                        .foregroundStyle(ALColor.textFaint)
                }
            }
        }
    }

    private var poolSummary: String {
        let labels = poolLines.map(\.label)
        if labels.isEmpty { return "\(row.pools.count) pools" }
        return "\(row.pools.count) pools · " + labels.joined(separator: ", ")
    }

    // MARK: Pool lines — the one shape both metric columns render

    /// One rendered line inside the weekly and 5h columns.
    ///
    /// Single-pool and multi-pool rows produce the *same* line, label column and
    /// all. That is what keeps the bars aligned: there is no second code path
    /// that can omit a column.
    private struct PoolLine: Identifiable {
        let id: Int
        let label: String
        let pool: CapacityBenchPoolMetrics
    }

    /// Pools in display order, each with its resolved label.
    ///
    /// A pool the vendor did not name is that row's whole allowance, so it reads
    /// `Total` and sorts first. Vendor-named pools (Fable, Gemini, Claude/GPT)
    /// keep their own name and their own order — a named bucket is a vendor fact
    /// and must never be relabelled as a total it does not cover.
    private var poolLines: [PoolLine] {
        let unnamed = row.pools.filter { ($0.poolLabel ?? "").isEmpty }
        let named = row.pools.filter { !($0.poolLabel ?? "").isEmpty }
        return (unnamed + named).enumerated().map { index, pool in
            PoolLine(id: index, label: poolLineLabel(pool), pool: pool)
        }
    }

    private func poolLineLabel(_ pool: CapacityBenchPoolMetrics) -> String {
        guard let label = pool.poolLabel, !label.isEmpty else { return "Total" }
        return compressPoolLabel(label)
    }

    // MARK: Weekly / monthly

    @ViewBuilder
    private var weeklyColumn: some View {
        if isDimmed, row.unknownReason != nil || row.pools.isEmpty {
            Text("not ready — probe failed")
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textFaint)
        } else if let reason = row.unknownReason {
            Text(CapacityStripRenderer.unknownCopy(reason))
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textFaint)
                .lineLimit(2)
        } else if poolLines.isEmpty {
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALColor.textFaint)
        } else {
            VStack(alignment: .leading, spacing: CapacityStripLayout.poolLineSpacing) {
                ForEach(poolLines) { line in
                    weeklyPoolLine(line)
                }
            }
        }
    }

    /// The only weekly line in the strip: `[label][bar][%][resets in]`, every
    /// column a fixed width from `CapacityStripLayout`.
    private func weeklyPoolLine(_ line: PoolLine) -> some View {
        HStack(spacing: CapacityStripLayout.cellGap) {
            Text(line.label)
                .font(ALFont.sans(10))
                .foregroundStyle(ALColor.textFaint)
                .lineLimit(1)
                .frame(width: CapacityStripLayout.poolLabelWidth, alignment: .leading)
            weeklyPoolMetrics(line.pool)
        }
        .frame(height: CapacityStripLayout.poolLineHeight)
    }

    @ViewBuilder
    private func weeklyPoolMetrics(_ pool: CapacityBenchPoolMetrics) -> some View {
        if let remaining = pool.dashboardRemainingPercent {
            CapacityBar(remaining: remaining, color: color)
            Text(CapacityStripRenderer.formatPercent(remaining))
                .font(ALFont.mono(13))
                .foregroundStyle(toneColor)
                .frame(width: CapacityStripLayout.percentWidth, alignment: .trailing)
            Group {
                if let reset = pool.dashboardResetAt {
                    Text(CapacityStripRenderer.relativeClock(from: now, to: reset))
                        .foregroundStyle(toneColor.opacity(color == .neutral ? 0.75 : 1))
                } else {
                    Text("—")
                        .foregroundStyle(ALColor.textFaint)
                }
            }
            .font(ALFont.mono(11))
            .lineLimit(1)
            .frame(width: CapacityStripLayout.resetWidth, alignment: .leading)
        } else if let reason = pool.unknownReason {
            Text(CapacityStripRenderer.unknownCopy(reason))
                .font(ALFont.sans(11))
                .foregroundStyle(ALColor.textFaint)
                .lineLimit(1)
                .help(CapacityStripRenderer.unknownCopy(reason))
        } else {
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALColor.textFaint)
        }
    }

    // MARK: 5h (numbers only — no bar)

    @ViewBuilder
    private var shortColumn: some View {
        if isDimmed, row.unknownReason != nil || row.pools.isEmpty {
            EmptyView()
        } else if row.unknownReason != nil {
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALColor.textFaint)
        } else if poolLines.isEmpty {
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALColor.textFaint)
        } else {
            // Same lines, same order, same heights as the weekly column — that is
            // what keeps a pool's 5h number level with its own weekly bar.
            VStack(alignment: .leading, spacing: CapacityStripLayout.poolLineSpacing) {
                ForEach(poolLines) { line in
                    shortCell(pool: line.pool)
                        .frame(height: CapacityStripLayout.poolLineHeight, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func shortCell(pool: CapacityBenchPoolMetrics) -> some View {
        switch shortPresentation(pool: pool) {
        case .none:
            // Genuine product fact for seats with no short window (Grok, Cursor).
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALPalette.ink500)
        case .unknown:
            Text("unknown")
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textFaint)
        case .known(let remaining):
            Text(CapacityStripRenderer.formatPercent(remaining))
                .font(ALFont.mono(13))
                .foregroundStyle(toneColor)
        }
    }

    private enum ShortCell {
        case none
        case unknown
        case known(Double)
    }

    /// Effective availability for the short column — same law as the CLI renderer.
    private func shortPresentation(pool: CapacityBenchPoolMetrics) -> ShortCell {
        switch pool.shortWindow {
        case .none:
            return .none
        case .unknown:
            return .unknown
        case .known(let shortRemaining, _, _, _, _):
            var floored = row.effectiveRemainingPercent.map { min($0, shortRemaining) } ?? shortRemaining
            if let dash = pool.dashboardRemainingPercent {
                floored = min(floored, dash)
            }
            return .known(floored)
        }
    }

    // MARK: Age chip = per-row refresh

    private var ageChip: some View {
        Button(action: onRefresh) {
            HStack(spacing: 4) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 10, height: 10)
                } else {
                    Text(CapacityStripRenderer.ageLabel(for: row, now: now))
                        .font(ALFont.mono(11))
                        .foregroundStyle(ALColor.textFaint)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ALColor.textFaint)
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help("Refresh this seat only")
        .accessibilityLabel("Refresh \(CapacityStripRenderer.displayName(for: row.source))")
    }

    // MARK: Detail disclosure (provenance)

    private var detailDisclosure: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(row.rawWindows.enumerated()), id: \.offset) { _, window in
                detailLine(window)
            }
            if row.rawWindows.isEmpty, let reason = row.unknownReason {
                detailKV("Unknown", CapacityStripRenderer.unknownCopy(reason))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ALPalette.ink950, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ALColor.accentBorder)
                .frame(width: 2)
        }
    }

    private func detailLine(_ window: CapacityWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let reason = window.unknownReason {
                detailKV(scopeLabel(window), CapacityStripRenderer.unknownCopy(reason))
            } else {
                let pct = window.remainingPercent.map(CapacityStripRenderer.formatPercent) ?? "—"
                let clock = window.resetAt.map {
                    CapacityStripRenderer.relativeClock(from: now, to: $0)
                } ?? "—"
                detailKV(scopeLabel(window), "\(pct) left · resets \(clock)")
            }
            if let path = sourcePath(for: window) {
                detailKV("Source", path)
            }
            if let raw = vendorSnippet(window) {
                detailKV("Vendor said", raw)
            }
            detailKV(
                "Observed",
                CapacityStripRenderer.ageLabel(for: row, now: now)
            )
        }
        .padding(.bottom, 4)
    }

    private func detailKV(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(ALFont.mono(11))
                .foregroundStyle(ALColor.textFaint)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(ALFont.mono(11))
                .foregroundStyle(ALColor.textMuted)
                .textSelection(.enabled)
        }
    }

    private func scopeLabel(_ window: CapacityWindow) -> String {
        var parts: [String] = []
        if let pool = window.poolLabel {
            parts.append(compressPoolLabel(pool))
        }
        switch window.scope {
        case .weekly: parts.append("Weekly")
        case .monthly: parts.append("Monthly")
        case .fiveHour: parts.append("5h")
        case .session: parts.append("Session")
        case .planClass: parts.append("Plan")
        }
        return parts.joined(separator: " · ")
    }

    private func sourcePath(for window: CapacityWindow) -> String? {
        switch window.sourceTier {
        case .onDisk:
            switch window.source {
            case "codex": return "on-disk log · ~/.codex/…"
            case "grok": return "on-disk log · ~/.grok/logs/…"
            default: return "on-disk log"
            }
        case .tuiProbe: return "TUI probe · /usage"
        case .streamPiggyback: return "stream piggyback"
        case .failureClassification: return "failure classification"
        case .dashboardScrape: return "dashboard scrape"
        }
    }

    private func vendorSnippet(_ window: CapacityWindow) -> String? {
        if let used = window.usedPercent {
            return "used \(CapacityStripRenderer.formatPercent(used))"
        }
        if let rem = window.remainingPercent {
            return "remaining \(CapacityStripRenderer.formatPercent(rem))"
        }
        return nil
    }

    // MARK: Tone

    private var toneColor: Color {
        switch color {
        case .neutral: return ALColor.textPrimary
        case .amber: return ALPalette.amber400
        case .red: return ALPalette.red400
        }
    }
}

// MARK: - Bar

private struct CapacityBar: View {
    let remaining: Double
    let color: CapacityStripColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ALPalette.ink650)
                Capsule()
                    .fill(fill)
                    .frame(width: max(2, geo.size.width * CGFloat(clamped / 100)))
            }
        }
        .frame(width: CapacityStripLayout.barWidth, height: 5)
    }

    private var clamped: Double {
        min(100, max(0, remaining))
    }

    private var fill: Color {
        switch color {
        case .neutral: return ALPalette.ink300
        case .amber: return ALColor.accent
        case .red: return ALColor.statusFailed
        }
    }
}

// MARK: - Helpers

private func glyphDriverId(_ source: String) -> String {
    switch source {
    case "agy": return "antigravity"
    default: return source
    }
}

private func compressPoolLabel(_ label: String) -> String {
    let upper = label.uppercased()
    if upper.contains("GEMINI") { return "Gemini" }
    if upper.contains("CLAUDE") && upper.contains("GPT") { return "Claude/GPT" }
    if upper.contains("CLAUDE") { return "Claude" }
    if label.count <= 10 { return label }
    return String(label.prefix(10))
}
