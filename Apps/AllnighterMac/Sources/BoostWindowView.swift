import SwiftUI
import AllnighterCore
import AllnighterEngine

/// Settings > **Boost window** — utilization seed placement (matches mockup pack).
struct BoostWindowView: View {
    @Environment(AppModel.self) private var appModel
    @State private var vm = BoostWindowViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                heroCard
                appliesToSection
                honestyFootnote
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ALColor.base)
        .task { reload() }
        .onChange(of: appModel.toolStatuses.count) { reload() }
    }

    private func reload() {
        let boostDrivers = appModel.registry.all
            .filter { BoostWindowProviderBuilder.boostSourceIds.contains($0.id) }
            .map { ($0.id, $0.displayName) }
        let ready = Set(appModel.toolStatuses.filter { $0.status.isReady }.map(\.driverId))
        let kinds = Dictionary(uniqueKeysWithValues: appModel.toolStatuses.map { ($0.driverId, $0.status.kind) })
        let resets = UtilizationCapacityReader.lastObservedResetPerSource()
        let outcomes = UtilizationCapacityReader.recentSeedOutcomes()
        vm.load(
            drivers: boostDrivers,
            readyDrivers: ready,
            probeKinds: kinds,
            observedResets: resets,
            recentSeedOutcomes: outcomes
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BOOST WINDOW").font(ALFont.sans(11, .bold)).tracking(1.3).foregroundStyle(ALColor.accent)
                Text("2× the capacity when you need it most.")
                    .font(ALFont.sans(26, .heavy)).tracking(-0.4).foregroundStyle(ALColor.textPrimary)
                Text("How? Your capacity refills every 5 hours, but that reset usually lands after your busy stretch. Allnighter triggers an early one so a fresh bucket resets mid-window — two full buckets in the same five hours, not one.")
                    .font(ALFont.sans(13)).foregroundStyle(ALColor.textMuted)
                    .frame(maxWidth: 620, alignment: .leading)
            }
            Spacer(minLength: 16)
            Toggle(isOn: Binding(get: { vm.projection.enabled }, set: { vm.setEnabled($0) })) {
                Text(vm.projection.enabled ? "On" : "Off").font(ALFont.sans(13, .semibold))
            }
            .toggleStyle(.switch)
            .tint(ALColor.accent)
        }
        .overlay(alignment: .bottom) { Divider().overlay(ALColor.borderSubtle).padding(.top, 52) }
        .padding(.bottom, 8)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                statColumn.frame(width: 220, alignment: .leading)
                zoomChart.frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            }
            minimapStrip
            softNote
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ALColor.borderDefault, lineWidth: 1))
        .opacity(vm.projection.enabled ? 1 : 0.55)
        .overlay { if vm.displayState == .needsYou { needsYouOverlay } }
    }

    private var statColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PEAK 5 HOURS").font(ALFont.sans(10, .bold)).tracking(0.8).foregroundStyle(ALColor.textFaint)
            Text(vm.projection.bucketHeadline + " buckets")
                .font(ALFont.mono(13, .semibold)).foregroundStyle(ALColor.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(boostMultiplier).font(ALFont.sans(42, .heavy)).foregroundStyle(ALColor.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("the capacity").font(ALFont.sans(14, .semibold)).foregroundStyle(ALColor.textPrimary)
                    Text("same 5 hours").font(ALFont.sans(13)).foregroundStyle(ALColor.accent)
                }
            }
            Text(statSubcopy).font(ALFont.sans(12)).foregroundStyle(ALColor.textMuted)
            if vm.displayState == .estimated {
                Badge(text: "estimated", tone: .warning, dot: false, mono: true)
            }
        }
    }

    private var boostMultiplier: String {
        switch vm.displayState {
        case .noQuietRunUp, .off: return "1×"
        default: return "2×"
        }
    }

    private var statSubcopy: String {
        switch vm.displayState {
        case .noQuietRunUp:
            return "No quiet run-up. Nothing to seed — move it after some downtime."
        case .off:
            return "Off by default — enable when you want a mid-window reset."
        default:
            return "Fresh reset lands \(BoostWindowTiming.formatMinutes(vm.resetMid)) — mid-window, not after."
        }
    }

    private var zoomChart: some View {
        let start = vm.windowStart
        let end = BoostWindowTiming.windowEnd(start)
        let mid = vm.resetMid
        return VStack(alignment: .leading, spacing: 10) {
            Text(BoostWindowTiming.formatWindowRange(start: start))
                .font(ALFont.mono(11, .semibold)).foregroundStyle(ALColor.textFaint)
            chartRow(label: "Normally", tone: .muted, spans: [(start, end)], marker: ("reset \(BoostWindowTiming.formatMinutes(end))", end, "too late"))
            chartRow(
                label: "With boost",
                tone: .accent,
                spans: [(start, mid), (mid, end)],
                marker: ("fresh reset · \(BoostWindowTiming.formatMinutes(mid))", mid, nil),
                tag: vm.displayState == .noQuietRunUp ? nil : "+1 bucket"
            )
        }
        .opacity(vm.displayState == .estimated ? 0.65 : 1)
        .overlay {
            if vm.displayState == .estimated {
                RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(ALColor.borderDefault)
            }
        }
    }

    private enum ChartTone { case muted, accent }

    private func chartRow(
        label: String,
        tone: ChartTone,
        spans: [(Int, Int)],
        marker: (String, Int, String?)?,
        tag: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(ALFont.sans(11, .semibold)).foregroundStyle(ALColor.textMuted)
                if let tag {
                    Text(tag).font(ALFont.mono(9, .bold)).tracking(0.4)
                        .foregroundStyle(ALColor.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(ALColor.accent.opacity(0.12)))
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                        let x0 = CGFloat(span.0 - vm.windowStart) / 300 * w
                        let x1 = CGFloat(span.1 - vm.windowStart) / 300 * w
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tone == .accent ? ALColor.accent.opacity(0.35) : ALColor.active)
                            .frame(width: max(4, x1 - x0), height: 14)
                            .offset(x: x0)
                    }
                    if let marker {
                        let x = CGFloat(marker.1 - vm.windowStart) / 300 * w
                        VStack(spacing: 2) {
                            Text(marker.0).font(ALFont.mono(9)).foregroundStyle(tone == .accent ? ALColor.accent : ALColor.textFaint)
                            if let sub = marker.2 {
                                Text(sub).font(ALFont.mono(8)).foregroundStyle(ALColor.textFaint)
                            }
                        }
                        .offset(x: max(0, x - 20), y: 18)
                    }
                }
            }
            .frame(height: 36)
        }
    }

    private var minimapStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.and.right").font(.system(size: 11))
                Text("When do you go hardest? — drag to set")
                    .font(ALFont.sans(12, .semibold)).foregroundStyle(ALColor.textSecondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(ALColor.active).frame(height: 28)
                    // overnight quiet band
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ALColor.blue500.opacity(0.08))
                        .frame(width: w * 0.33, height: 28)
                    // seed dot
                    let seedX = CGFloat(vm.seedAt) / 1440 * w
                    Circle().fill(ALColor.accent).frame(width: 8, height: 8)
                        .offset(x: seedX - 4, y: -14)
                    Text("seed · \(BoostWindowTiming.formatMinutes(vm.seedAt))")
                        .font(ALFont.mono(9)).foregroundStyle(ALColor.accent)
                        .offset(x: max(0, seedX - 20), y: -28)
                    // draggable window bracket
                    let startX = CGFloat(vm.windowStart) / 1440 * w
                    let bracketW = CGFloat(BoostWindowSettings.windowLengthMinutes) / 1440 * w
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ALColor.accent, lineWidth: 1.5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ALColor.accent.opacity(0.1)))
                        .frame(width: max(24, bracketW), height: 28)
                        .overlay {
                            Text("\(formatClock(vm.windowStart)) – \(formatClock(BoostWindowTiming.windowEnd(vm.windowStart)))")
                                .font(ALFont.mono(10, .semibold)).foregroundStyle(ALColor.textPrimary)
                        }
                        .offset(x: startX)
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    let minutes = Int((value.location.x / w * 1440).rounded())
                                    vm.setWindowStart(minutes - BoostWindowSettings.windowLengthMinutes / 2)
                                }
                        )
                }
            }
            .frame(height: 44)
        }
    }

    private var softNote: some View {
        let overnight = vm.projection.quietRunUp
        return HStack(spacing: 8) {
            Image(systemName: overnight ? "moon.stars" : "exclamationmark.triangle")
            Text(overnight
                 ? "Seeded at \(formatClock(vm.seedAt)), while you're idle — costs you nothing you'd use."
                 : "Seeded at \(formatClock(vm.seedAt)) — only boosts if you're idle then.")
                .font(ALFont.sans(12))
        }
        .foregroundStyle(overnight ? ALColor.blue500 : ALPalette.yellow500)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill((overnight ? ALColor.blue500 : ALPalette.yellow500).opacity(0.12)))
    }

    private var needsYouOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(ALColor.void.opacity(0.72))
            VStack(spacing: 8) {
                Text("Needs you").font(ALFont.sans(16, .heavy)).foregroundStyle(ALColor.textPrimary)
                Text("Sign-in or billing prompt — resolve on CLIs, then return.")
                    .font(ALFont.sans(13)).foregroundStyle(ALColor.textMuted)
            }
            .padding(20)
        }
    }

    // MARK: - Applies to

    private var appliesToSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Applies to").font(ALFont.sans(13, .semibold)).foregroundStyle(ALColor.textSecondary)
            HStack(spacing: 10) {
                ForEach(vm.projection.providers.filter { $0.connected || $0.included }, id: \.sourceId) { p in
                    providerChip(p)
                }
            }
            Text("One window, every CLI you switch on.")
                .font(ALFont.sans(12)).foregroundStyle(ALColor.textFaint)
        }
    }

    private func providerChip(_ p: ProviderBoostStateJSON) -> some View {
        let on = p.included
        return Button { vm.toggleProvider(p.sourceId) } label: {
            HStack(spacing: 8) {
                DriverBrandGlyph(driverId: p.sourceId, boxSize: 18)
                Text(p.displayName).font(ALFont.sans(13, .semibold))
                if on {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(ALColor.accent)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? ALColor.accent.opacity(0.12) : ALColor.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? ALColor.accent.opacity(0.35) : ALColor.borderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(ALColor.textPrimary)
    }

    private var honestyFootnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            Text("Real resets only — never quota, tokens, or cost. Needs downtime before your window, or there's nothing to seed. Off by default.")
                .font(ALFont.sans(11)).foregroundStyle(ALColor.textFaint)
        }
    }

    private func formatClock(_ minutes: Int) -> String {
        let m = BoostWindowTiming.mod1440(minutes)
        let h = m / 60
        let min = m % 60
        let period = h >= 12 ? "PM" : "AM"
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, min, period)
    }
}

// MARK: - Color shim

private extension ALColor {
    static let blue500 = ALPalette.blue500
}
