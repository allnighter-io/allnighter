import SwiftUI
import AllnighterCore

/// Column geometry for the bench table — **one** definition, read by headers
/// and every meter row. No pool-label gutter: pool identity lives in the title
/// (`Antigravity · Gemini`), so every weekly bar shares one left edge.
private enum CapacityStripLayout {
    static let rowInset: CGFloat = 24
    /// Headers sit slightly inboard of the rows — the row's leading chevron is
    /// chrome, not a column, so the label lines up with the CLI glyph instead.
    static let headerInset: CGFloat = 34
    static let columnGap: CGFloat = 18
    static let shortWidth: CGFloat = 72
    static let ageWidth: CGFloat = 72

    static let barWidth: CGFloat = 68
    static let percentWidth: CGFloat = 46
    static let resetWidth: CGFloat = 54
    static let cellGap: CGFloat = 10

    static var weeklyMetricsWidth: CGFloat {
        barWidth + cellGap + percentWidth + cellGap + resetWidth
    }
}

/// Launch-surface capacity strip — renders the same Core projection the CLI prints.
///
/// Product law: **if we measure capacity, it gets a row.** Multi-pool CLIs become
/// adjacent sibling lines (`Antigravity · Gemini`, `Antigravity · Claude/GPT`),
/// not nested columns. Seat count = CLIs. Three colours only (neutral / amber / red).
struct CapacityStripView: View {
    @Bindable var model: CapacityStripModel
    /// Optional CTA: hero "Start a run on X" focuses the composer seat.
    var onHeroStart: ((String) -> Void)? = nil

    @State private var expandedMeters: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if model.featureEnabled {
                heroZone
                stripHeader
                columnHeaders
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.meterLines) { line in
                            CapacityStripMeterRowView(
                                line: line,
                                parent: model.benchRow(for: line),
                                now: model.now,
                                isRefreshing: model.isRefreshing(line.source),
                                showsOwnAge: model.benchRow(for: line).map { model.showsOwnAge($0) } ?? true,
                                isExpanded: expandedMeters.contains(line.id),
                                onToggleExpand: { toggleExpand(line.id) },
                                onRefresh: { model.refreshSource(line.source) }
                            )
                        }
                        parkedFooter
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

    // MARK: - Hero

    @ViewBuilder
    private var heroZone: some View {
        if let hero = model.hero {
            liveHero(hero)
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(heroBackground(hero.mood))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                }
        }
    }

    private func heroBackground(_ mood: CapacityHeroPresentation.Mood) -> some View {
        let wash: [Color] = mood == .expiring
            ? [ALColor.accent.opacity(0.10), ALColor.accent.opacity(0.02), ALColor.base]
            : [ALColor.raised.opacity(0.5), ALColor.raised.opacity(0.12), ALColor.base]
        return LinearGradient(colors: wash, startPoint: .top, endPoint: .bottom)
    }

    private func liveHero(_ hero: CapacityHeroPresentation) -> some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: hero.mood == .expiring ? "bolt.fill" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hero.mood == .expiring ? ALColor.accent : ALColor.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text(hero.mood == .expiring ? "Use it before you lose it" : "Most room on your bench")
                        .font(ALFont.sans(10, .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(hero.mood == .expiring ? ALColor.accentText : ALColor.textFaint)
                    heroHeadline(hero)
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

    private func heroHeadline(_ hero: CapacityHeroPresentation) -> Text {
        let name = Text("\(hero.displayName) — ").foregroundStyle(ALColor.textPrimary)
        let percent = Text(CapacityStripRenderer.formatPercent(hero.remainingPercent))
            .foregroundStyle(hero.mood == .expiring ? ALPalette.amber400 : ALColor.textPrimary)
        switch hero.mood {
        case .expiring:
            return name + percent
                + Text(" of your week expires in ").foregroundStyle(ALColor.textPrimary)
                + Text(clockText(hero.resetAt)).foregroundStyle(ALPalette.amber400)
        case .mostRoom:
            return name + percent
                + Text(" of your week still unspent").foregroundStyle(ALColor.textPrimary)
        }
    }

    private func clockText(_ resetAt: Date?) -> String {
        guard let resetAt else { return "—" }
        return CapacityStripRenderer.relativeClock(from: model.now, to: resetAt)
    }

    // MARK: - Strip chrome

    private var stripHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Your bench")
                .font(ALFont.sans(11, .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(ALColor.textFaint)
            Text("· \(model.onBenchCount) seats")
                .font(ALFont.sans(11))
                .foregroundStyle(ALColor.textFaint)
            Spacer()
            Text(model.freshnessLine)
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
                        .font(ALFont.sans(11, .semibold))
                }
                .foregroundStyle(
                    model.refreshIsElevated ? ALColor.accentText : ALColor.textSecondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    model.refreshIsElevated
                        ? ALColor.accent.opacity(0.14)
                        : ALColor.raised,
                    in: RoundedRectangle(cornerRadius: ALRadius.sm)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ALRadius.sm)
                        .strokeBorder(
                            model.refreshIsElevated
                                ? ALColor.accentBorder
                                : ALColor.borderDefault,
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshingAll)
            .help("Refresh every seat so the strip stays comparable")
            .accessibilityLabel(
                model.refreshIsElevated
                    ? "Refresh bench — samples missing or stale"
                    : "Refresh every seat"
            )
            Menu {
                Button("Turn off capacity checks") { model.disableFeature() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ALColor.textFaint)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .help("Capacity settings")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var parkedFooter: some View {
        let parked = model.parkedDisplayNames
        if !parked.isEmpty {
            Text("\(parked.count) parked — \(parked.joined(separator: ", ")) · not sampled")
                .font(ALFont.sans(11))
                .foregroundStyle(ALColor.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CapacityStripLayout.rowInset)
                .padding(.vertical, 12)
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: CapacityStripLayout.columnGap) {
            Text("CLI")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("This week")
                .frame(width: CapacityStripLayout.weeklyMetricsWidth, alignment: .leading)
            Text("Last 5h")
                .frame(width: CapacityStripLayout.shortWidth, alignment: .trailing)
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

    private func toggleExpand(_ id: String) {
        if expandedMeters.contains(id) {
            expandedMeters.remove(id)
        } else {
            expandedMeters.insert(id)
        }
    }
}

// MARK: - Meter row (one shape for every line)

private struct CapacityStripMeterRowView: View {
    let line: CapacityStripRenderer.CapacityMeterLine
    let parent: CapacityBenchRow?
    let now: Date
    let isRefreshing: Bool
    let showsOwnAge: Bool
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRefresh: () -> Void

    @State private var hovering = false

    private var color: CapacityStripColor {
        guard let parent else { return .neutral }
        return CapacityStripRenderer.color(for: parent, now: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: CapacityStripLayout.columnGap) {
                titleColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                weeklyColumn
                    .frame(width: CapacityStripLayout.weeklyMetricsWidth, alignment: .leading)
                shortColumn
                    .frame(width: CapacityStripLayout.shortWidth, alignment: .trailing)
                trailingColumn
                    .frame(width: CapacityStripLayout.ageWidth, alignment: .trailing)
            }
            .padding(.horizontal, CapacityStripLayout.rowInset)
            .padding(.vertical, 10)

            if isExpanded, let parent {
                detailDisclosure(parent)
                    .padding(.horizontal, CapacityStripLayout.rowInset)
                    .padding(.bottom, 12)
            }
        }
        .background(isExpanded ? ALColor.subtle : (hovering ? ALColor.subtle.opacity(0.5) : Color.clear))
        .overlay(alignment: .bottom) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onToggleExpand() }
    }

    // MARK: Title

    private var titleColumn: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ALColor.textFaint)
                .frame(width: 12)
                .opacity(isExpanded || hovering ? 1 : 0)

            DriverBrandGlyph(
                driverId: glyphDriverId(line.source),
                boxSize: 20,
                iconSize: 11,
                cornerRadius: 5,
                muted: false
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(ALFont.sans(13, .medium))
                    .foregroundStyle(ALColor.textPrimary)
                    .lineLimit(1)
                // Plan on the first sibling only — Antigravity · Gemini and
                // · Claude/GPT share one plan; repeating it is noise.
                if line.isFirstOfSource, let plan = line.planTier, !plan.isEmpty {
                    Text(plan)
                        .font(ALFont.sans(10))
                        .foregroundStyle(ALColor.textFaint)
                }
            }
        }
    }

    // MARK: This week — [bar][%][reset], always the same three slots

    @ViewBuilder
    private var weeklyColumn: some View {
        if line.rowUnknownReason != nil {
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALColor.textFaint)
                .help(line.rowUnknownReason.map { CapacityStripRenderer.unknownCopy($0) } ?? "")
        } else if let pool = line.pool, let remaining = pool.dashboardRemainingPercent {
            HStack(spacing: CapacityStripLayout.cellGap) {
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
            }
        } else if let pool = line.pool, let reason = pool.unknownReason {
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

    // MARK: Last 5h

    @ViewBuilder
    private var shortColumn: some View {
        switch shortPresentation {
        case .none:
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALPalette.ink500)
        case .unknown:
            Text("unknown")
                .font(ALFont.sans(12))
                .foregroundStyle(ALColor.textFaint)
        case .dash:
            Text("—")
                .font(ALFont.mono(13))
                .foregroundStyle(ALColor.textFaint)
        case .known(let remaining):
            Text(CapacityStripRenderer.formatPercent(remaining))
                .font(ALFont.mono(13))
                .foregroundStyle(toneColor)
        }
    }

    private enum ShortPresentation {
        case none
        case unknown
        case dash
        case known(Double)
    }

    /// This meter's own short window, floored by its own weekly/monthly sample —
    /// never by a sibling pool on the same CLI.
    private var shortPresentation: ShortPresentation {
        if line.rowUnknownReason != nil { return .dash }
        guard let pool = line.pool else { return .dash }
        switch pool.shortWindow {
        case .none:
            return .none
        case .unknown:
            return .unknown
        case .known(let shortRemaining, _, _, _, _):
            var floored = shortRemaining
            if let dash = pool.dashboardRemainingPercent {
                floored = min(floored, dash)
            }
            return .known(floored)
        }
    }

    // MARK: Trailing chrome — first sibling of a CLI only

    @ViewBuilder
    private var trailingColumn: some View {
        if line.isFirstOfSource {
            if isRefreshing || showsOwnAge {
                ageChip
            } else if hovering {
                refreshOnlyChip
            }
        }
    }

    private var refreshOnlyChip: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(ALColor.textFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Refresh this seat only")
        .accessibilityLabel("Refresh \(line.title)")
    }

    private var ageChip: some View {
        Button(action: onRefresh) {
            HStack(spacing: 4) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 10, height: 10)
                } else if let parent {
                    Text(CapacityStripRenderer.bareAgeLabel(for: parent, now: now))
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
        .accessibilityLabel("Refresh \(line.title)")
    }

    // MARK: Detail

    private func detailDisclosure(_ row: CapacityBenchRow) -> some View {
        let windows = disclosureWindows(in: row)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                detailLine(window, row: row)
            }
            if windows.isEmpty, let reason = row.unknownReason {
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

    /// Prefer this meter's pool windows; fall back to the whole seat.
    private func disclosureWindows(in row: CapacityBenchRow) -> [CapacityWindow] {
        guard let pool = line.pool else { return row.rawWindows }
        let key = pool.poolLabel ?? ""
        let matched = row.rawWindows.filter { ($0.poolLabel ?? "") == key }
        return matched.isEmpty ? row.rawWindows : matched
    }

    private func detailLine(_ window: CapacityWindow, row: CapacityBenchRow) -> some View {
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
            detailKV("Observed", CapacityStripRenderer.ageLabel(for: row, now: now))
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
        if let pool = window.poolLabel, !pool.isEmpty {
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
        case .headlessJSON: return "native · agy --print /usage"
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
        ZStack(alignment: .leading) {
            Capsule().fill(ALPalette.ink650)
            Capsule()
                .fill(fill)
                .frame(width: max(2, CapacityStripLayout.barWidth * CGFloat(clamped / 100)))
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
