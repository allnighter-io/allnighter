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
                scheduleHistorySection
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
        let eligible = BoostEligibilityProbe.eligibleSeedDriverIds()
        let boostDrivers = appModel.registry.all
            .filter { eligible.contains($0.id) }
            .map { ($0.id, $0.displayName) }
        // Catalog order when registry omits a seat we still want labeled.
        let ordered: [(id: String, name: String)] = BoostSeatCatalog.seats.compactMap { seat in
            guard eligible.contains(seat.seedDriverId) else { return nil }
            if let hit = boostDrivers.first(where: { $0.0 == seat.seedDriverId }) {
                return (hit.0, hit.1)
            }
            return (seat.seedDriverId, seat.seedDriverId)
        }
        let parked = appModel.parkedDriverIds
        let ready = Set(
            appModel.toolStatuses
                .filter { $0.status.isSmokeReady && !parked.contains($0.driverId) }
                .map(\.driverId)
        )
        let kinds = Dictionary(uniqueKeysWithValues: appModel.toolStatuses.map { ($0.driverId, $0.status.kind) })
        let resets = UtilizationCapacityReader.lastObservedResetPerSource()
        let outcomes = UtilizationCapacityReader.recentSeedOutcomes()
        vm.load(
            drivers: ordered,
            readyDrivers: ready,
            probeKinds: kinds,
            observedResets: resets,
            recentSeedOutcomes: outcomes,
            eligibleSeedDriverIds: eligible
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
            HStack(alignment: .top, spacing: 0) {
                BoostWindowStatColumn(
                    enabled: vm.projection.enabled,
                    displayState: vm.displayState,
                    resetMid: vm.resetMid
                )
                .frame(width: 240, alignment: .leading)
                .padding(.trailing, 20)

                BoostWindowZoomChart(
                    windowStart: vm.windowStart,
                    resetMid: vm.resetMid,
                    displayState: vm.displayState,
                    enabled: vm.projection.enabled
                )
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            }
            minimapStrip
            softNote
            if let receipt = vm.latestReceipt {
                seedReceiptRow(receipt)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ALColor.borderDefault, lineWidth: 1))
        .saturation(vm.projection.enabled ? 1 : 0.5)
        .opacity(vm.projection.enabled ? 1 : 0.5)
        .overlay { heroOverlayView }
    }

    private var heroOverlayStyle: BoostWindowHeroOverlay.Style? {
        if !vm.projection.enabled { return .off }
        if vm.displayState == .needsYou { return .needsYou(attentionLabel) }
        // "No quiet run-up" is NOT a lockout: the window is a recurring daily seed that simply
        // fires whenever you're idle at the seed time (e.g. the next morning). Keep the panel
        // fully adjustable and surface it as a small inline note (softNote) under the slider.
        return nil
    }

    private var attentionLabel: String {
        vm.projection.providers.first(where: \.needsAttention)?.displayName ?? "CLI"
    }

    @ViewBuilder
    private var heroOverlayView: some View {
        if let style = heroOverlayStyle {
            BoostWindowHeroOverlay(style: style) {
                vm.setEnabled(true)
            }
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
                    // A NEGATIVE offset put this label above the header and both strings
                    // became unreadable. Enlarging the frame did not help: GeometryReader
                    // top-aligns its content, so the ZStack keeps its natural 28pt height
                    // at the origin and anything offset upward still escapes. Park the
                    // label BELOW the track instead, where the taller frame gives it room.
                    Text("seed · \(BoostWindowTiming.formatMinutes(vm.seedAt))")
                        .font(ALFont.mono(9)).foregroundStyle(ALColor.accent)
                        .offset(x: max(0, seedX - 20), y: 24)
                    // draggable window bracket — bright amber (mockup SSOT)
                    let startX = CGFloat(vm.windowStart) / 1440 * w
                    let bracketW = CGFloat(BoostWindowSettings.windowLengthMinutes) / 1440 * w
                    windowBracket(
                        label: "\(formatClock(vm.windowStart)) – \(formatClock(BoostWindowTiming.windowEnd(vm.windowStart)))"
                    )
                    .frame(width: max(24, bracketW), height: 28)
                    .offset(x: startX)
                    .gesture(
                        // Draggable whenever boost is on — including the "no quiet run-up" case,
                        // so you can set the window for any time (e.g. the morning) freely. Only
                        // the off / needs-sign-in overlays (which cover the card) block dragging.
                        vm.projection.enabled && heroOverlayStyle == nil
                            ? DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    let minutes = Int((value.location.x / w * 1440).rounded())
                                    vm.setWindowStart(minutes - BoostWindowSettings.windowLengthMinutes / 2)
                                }
                            : nil
                    )
                }
            }
            // 44 left no room above the 28pt track for the seed label, so it escaped the
            // frame and collided with the header. 56 keeps the label inside its own bounds.
            .frame(height: 56)
        }
        // The workspace enables text selection broadly; on this slider that hijacked the drag
        // (it highlighted the "10:00 AM – 3:00 PM" label instead of moving the bracket). Disable
        // selection here so a press-drag always moves the window.
        .textSelection(.disabled)
    }

    private var softNote: some View {
        let overnight = vm.projection.quietRunUp
        return HStack(spacing: 8) {
            Image(systemName: overnight ? "moon.stars" : "exclamationmark.triangle")
            Text(overnight
                 ? "Seeded at \(formatClock(vm.seedAt)), while you're idle — costs you nothing you'd use."
                 : "No quiet run-up right now — it'll seed at \(formatClock(vm.seedAt)) the next morning you're idle (busy mornings are skipped).")
                .font(ALFont.sans(12))
        }
        .foregroundStyle(overnight ? ALColor.blue500 : ALPalette.yellow500)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill((overnight ? ALColor.blue500 : ALPalette.yellow500).opacity(0.12)))
    }

    /// Outcome receipt under the plan soft-note (setting above, what happened below).
    private func seedReceiptRow(_ receipt: BoostSeedReceipt) -> some View {
        let color = receiptToneColor(receipt.tone)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: receiptToneIcon(receipt.tone))
                .font(.system(size: 12))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.headline)
                    .font(ALFont.sans(12, .semibold))
                if let detail = receipt.detail, !detail.isEmpty {
                    Text(detail)
                        .font(ALFont.sans(11))
                        .opacity(0.9)
                }
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(receipt.headline + (receipt.detail.map { ". \($0)" } ?? ""))
    }

    // MARK: - Applies to

    private var appliesToSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Applies to").font(ALFont.sans(13, .semibold)).foregroundStyle(ALColor.textSecondary)
            if vm.projection.providers.isEmpty {
                Text("No CLIs yet — Capacity must record a 5h (or Claude session) window before a seat can boost. Turn Capacity on and refresh.")
                    .font(ALFont.sans(12))
                    .foregroundStyle(ALColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    ForEach(vm.projection.providers, id: \.sourceId) { p in
                        providerChip(p)
                    }
                }
                Text("One window, every CLI you switch on — seats appear when Capacity sees a short rolling window.")
                    .font(ALFont.sans(12)).foregroundStyle(ALColor.textFaint)
            }
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

    // MARK: - Schedule history

    @ViewBuilder
    private var scheduleHistorySection: some View {
        if !vm.scheduleHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Schedule history")
                    .font(ALFont.sans(13, .semibold))
                    .foregroundStyle(ALColor.textSecondary)
                Text("A blank morning usually means the Mac slept through seed time, or alln serve wasn't running — we only mark what we observed.")
                    .font(ALFont.sans(11))
                    .foregroundStyle(ALColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    ForEach(vm.scheduleHistory) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: BoostSeedHistoryEntry) -> some View {
        let color = receiptToneColor(entry.tone)
        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(ALFont.sans(12, .semibold))
                    .foregroundStyle(color)
                Text(entry.detail)
                    .font(ALFont.sans(11))
                    .foregroundStyle(ALColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ALColor.borderSubtle, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title). \(entry.detail)")
    }

    private func receiptToneColor(_ tone: BoostSeedReceiptTone) -> Color {
        switch tone {
        case .success: return ALColor.statusDone
        case .failure: return ALColor.statusFailed
        case .neutral: return ALColor.textMuted
        }
    }

    private func receiptToneIcon(_ tone: BoostSeedReceiptTone) -> String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .neutral: return "circle.dashed"
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

    /// Draggable 5h window on the 24h strip — amber phosphor highlight per mockup.
    private func windowBracket(label: String) -> some View {
        HStack(spacing: 6) {
            bracketGrip
            Text(label)
                .font(ALFont.mono(10, .semibold))
                .foregroundStyle(ALColor.accentText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            bracketGrip
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ALColor.accentSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ALColor.accent, lineWidth: 2)
        )
        .alGlowAmber()
        // The whole bracket is the drag target — not just the grips/gaps between text.
        .contentShape(Rectangle())
    }

    private var bracketGrip: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Circle().fill(ALColor.accentText).frame(width: 2.5, height: 2.5)
                Circle().fill(ALColor.accentText).frame(width: 2.5, height: 2.5)
            }
            HStack(spacing: 2) {
                Circle().fill(ALColor.accentText).frame(width: 2.5, height: 2.5)
                Circle().fill(ALColor.accentText).frame(width: 2.5, height: 2.5)
            }
            HStack(spacing: 2) {
                Circle().fill(ALColor.accentText).frame(width: 2.5, height: 2.5)
                Circle().fill(ALColor.accentText).frame(width: 2.5, height: 2.5)
            }
        }
        .opacity(0.85)
    }
}

// MARK: - Color shim

private extension ALColor {
    static let blue500 = ALPalette.blue500
}
