import SwiftUI
import AllnighterCore

/// Settings › **Default model**. Renders `DefaultSettingsJSON` (the same projection as
/// `alln defaults --json`) and drives every change back through Core. Membership is
/// many-to-many, so moves are add/remove-per-tier (a model can appear in several
/// columns); "Make default" sends it to the top of a tier.
struct DefaultModelView: View {
    @Environment(AppModel.self) private var appModel
    @State private var vm = DefaultModelViewModel()

    private let tiers: [SubstitutionTier] = [.flagship, .balanced, .fast]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                autoCard
                substitutionsSection
                rostersSection
            }
            .padding(28)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ALColor.base)
        .task { reload() }
    }

    private func reload() {
        let readyDrivers = Set(appModel.toolStatuses.filter { $0.status.isReady }.map(\.driverId))
        let readyIds = Set(appModel.models.filter { readyDrivers.contains($0.driverId) }.map(\.id))
        let names = Dictionary(appModel.models.map { ($0.driverId, appModel.driverName(for: $0)) },
                               uniquingKeysWith: { a, _ in a })
        vm.load(benchModels: appModel.models, sourceReadyIds: readyIds, driverName: { names[$0] ?? $0 })
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEFAULT").font(ALFont.sans(11, .bold)).tracking(1.3).foregroundStyle(ALColor.accent)
            Text("Default model").font(ALFont.sans(27, .heavy)).tracking(-0.5).foregroundStyle(ALColor.textPrimary)
            Text("What answers when you don’t pick a team or a model. Every chat starts here unless you say otherwise.")
                .font(ALFont.sans(13)).foregroundStyle(ALColor.textMuted).frame(maxWidth: 620, alignment: .leading)
            Divider().overlay(ALColor.borderSubtle).padding(.top, 8)
        }
    }

    // MARK: - Section 1 — Auto card

    private var autoCard: some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 14)
                .fill(ALColor.accent.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ALColor.accent.opacity(0.32), lineWidth: 1))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "infinity").font(.system(size: 24, weight: .bold)).foregroundStyle(ALColor.accent))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Auto").font(ALFont.sans(18, .heavy)).foregroundStyle(ALColor.textPrimary)
                    Text("DEFAULT").font(ALFont.mono(10, .semibold)).tracking(0.5)
                        .foregroundStyle(ALColor.accent)
                        .padding(.vertical, 2).padding(.horizontal, 9)
                        .background(Capsule().fill(ALColor.accent.opacity(0.12)))
                        .overlay(Capsule().stroke(ALColor.accent.opacity(0.32), lineWidth: 1))
                }
                HStack(spacing: 7) {
                    Text("Your go-to model, used in chat by default.")
                        .font(ALFont.sans(13)).foregroundStyle(ALColor.textMuted)
                    resolvedPill
                }
            }
            Spacer(minLength: 0)
            tierSegment
        }
        .padding(.vertical, 18).padding(.horizontal, 20)
        .background(RoundedRectangle(cornerRadius: 14).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ALColor.borderDefault, lineWidth: 1))
    }

    private var resolvedPill: some View {
        let auto = vm.projection.auto
        return Group {
            if let name = auto.resolvedModelName {
                HStack(spacing: 7) {
                    Text(name).font(ALFont.sans(13, .semibold)).foregroundStyle(ALColor.textSecondary)
                    Text(vm.defaultTier.displayName).font(ALFont.sans(13)).foregroundStyle(ALColor.textFaint)
                    if auto.substituted {
                        Text("· substituted").font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 13)
                .background(Capsule().fill(ALColor.active))
                .overlay(Capsule().stroke(ALColor.borderSubtle, lineWidth: 1))
            } else {
                Text(auto.waitsMessage ?? "No model on \(vm.defaultTier.displayName) — waits")
                    .font(ALFont.sans(13, .semibold)).foregroundStyle(ALPalette.amber400)
                    .padding(.vertical, 4).padding(.horizontal, 13)
                    .background(Capsule().fill(ALColor.active))
            }
        }
    }

    private var tierSegment: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Pick the tier").font(ALFont.sans(11, .semibold)).foregroundStyle(ALColor.textMuted)
            HStack(spacing: 0) {
                ForEach(tiers, id: \.self) { tier in
                    let on = vm.defaultTier == tier
                    Button { vm.setDefaultTier(tier) } label: {
                        Text(tier.displayName).font(ALFont.sans(12, .semibold))
                            .foregroundStyle(on ? ALColor.textOnAmber : ALColor.textMuted)
                            .padding(.vertical, 6).padding(.horizontal, 14)
                            .background(on ? ALColor.accent : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(ALColor.active))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ALColor.borderDefault, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Section 2 — Substitutions

    private var substitutionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("SUBSTITUTIONS")
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow healthy substitutions").font(ALFont.sans(14.5, .bold)).foregroundStyle(ALColor.textPrimary)
                    Text("If your model is down, fall back to another ready model on the same tier — across any CLI. Never upgrades, never downgrades.")
                        .font(ALFont.sans(12.5)).foregroundStyle(ALColor.textMuted).frame(maxWidth: 560, alignment: .leading)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { vm.projection.allowHealthySubstitutions },
                    set: { vm.setSubstitutions($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(ALColor.accent)
            }
            .padding(.vertical, 16).padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 12).fill(ALColor.raised))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ALColor.borderSubtle, lineWidth: 1))
        }
    }

    // MARK: - Section 3 — rosters

    private var rostersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("DEFAULT MODEL PER TIER")
                Spacer()
                Button("Reset to defaults") { vm.reset() }
                    .buttonStyle(.plain).font(ALFont.sans(11.5, .semibold)).foregroundStyle(ALColor.textMuted)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(tiers, id: \.self) { tier in tierColumn(tier) }
            }
            unassignedShelf
        }
    }

    private func tierColumn(_ tier: SubstitutionTier) -> some View {
        let view = vm.tierView(tier)
        let isDefault = vm.defaultTier == tier
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if tier == .flagship { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(ALColor.accent) }
                Text(tier.displayName).font(ALFont.sans(15, .heavy)).foregroundStyle(ALColor.textPrimary)
                if isDefault {
                    Text("AUTO").font(ALFont.mono(9.5, .bold)).tracking(0.4).foregroundStyle(ALColor.accent)
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background(Capsule().fill(ALColor.accent.opacity(0.12)))
                        .overlay(Capsule().stroke(ALColor.accent.opacity(0.32), lineWidth: 1))
                }
                Spacer(minLength: 0)
                Text("\(view?.readyCount ?? 0)/\(view?.members.count ?? 0)")
                    .font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 15).padding(.top, 14).padding(.bottom, 8)
            Text(caption(tier)).font(ALFont.sans(12)).foregroundStyle(ALColor.textMuted)
                .padding(.horizontal, 15).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(ALColor.borderSubtle)

            VStack(spacing: 8) {
                let members = view?.members ?? []
                if members.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 16)).foregroundStyle(ALPalette.amber400)
                        Text("Empty — work waits").font(ALFont.sans(12.5, .semibold)).foregroundStyle(ALColor.textMuted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                } else {
                    ForEach(members, id: \.id) { m in memberCard(m, tier: tier) }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(ALColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ALColor.borderSubtle, lineWidth: 1))
    }

    private func memberCard(_ m: DefaultSettingsJSON.ModelRef, tier: SubstitutionTier) -> some View {
        HStack(spacing: 11) {
            glyphTile(m.driverId)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.displayName).font(ALFont.sans(13.5, .bold)).foregroundStyle(ALColor.textPrimary)
                    if m.isTierDefault {
                        Text("DEFAULT").font(ALFont.mono(9, .bold)).foregroundStyle(ALColor.accent)
                            .padding(.vertical, 1).padding(.horizontal, 6)
                            .background(Capsule().fill(ALColor.accent.opacity(0.12)))
                    }
                }
                Text(m.driverId).font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 0)
            statusDot(ready: m.ready, enabled: m.enabled)
            if !m.isTierDefault {
                iconButton("arrow.up.to.line") { vm.makeDefault(m.id, in: tier) }
            }
            iconButton("xmark") { vm.unassign(m.id, from: tier) }
        }
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ALColor.borderSubtle, lineWidth: 1))
    }

    private var unassignedShelf: some View {
        let items = vm.projection.unassigned
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("UNASSIGNED").font(ALFont.mono(10.5, .bold)).tracking(1.0).foregroundStyle(ALColor.textFaint)
                Text("\(items.count)").font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
                Text("· pickable by hand · Auto never uses these · they never substitute.")
                    .font(ALFont.sans(12)).foregroundStyle(ALColor.textMuted)
            }
            if items.isEmpty {
                Text("Every on model is on a tier.").font(ALFont.sans(12)).foregroundStyle(ALColor.textFaint)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 248), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(items, id: \.id) { m in unassignedCard(m) }
                }
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 15)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(ALColor.borderDefault))
    }

    private func unassignedCard(_ m: DefaultSettingsJSON.ModelRef) -> some View {
        HStack(spacing: 11) {
            glyphTile(m.driverId)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.displayName).font(ALFont.sans(13.5, .bold)).foregroundStyle(ALColor.textPrimary)
                Text(m.driverId).font(ALFont.mono(11)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(tiers, id: \.self) { tier in
                    Button { vm.assign(m.id, to: tier) } label: {
                        Text("+\(String(tier.displayName.prefix(1)))").font(ALFont.mono(10, .bold))
                            .foregroundStyle(ALColor.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ALColor.active))
                    }
                    .buttonStyle(.plain).help("Add to \(tier.displayName)")
                }
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(ALColor.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ALColor.borderSubtle, lineWidth: 1))
    }

    // MARK: - Small parts

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(ALFont.mono(10.5, .bold)).tracking(1.2).foregroundStyle(ALColor.textFaint)
    }

    private func glyphTile(_ driverId: String) -> some View {
        RoundedRectangle(cornerRadius: 8).fill(ALColor.active).frame(width: 30, height: 30)
            .overlay(Image(systemName: "cpu").font(.system(size: 13)).foregroundStyle(ALColor.textMuted))
    }

    private func statusDot(ready: Bool, enabled: Bool) -> some View {
        Circle().fill(ready ? ALPalette.green500 : (enabled ? ALPalette.yellow500 : ALColor.textFaint))
            .frame(width: 7, height: 7)
            .help(ready ? "ready" : (enabled ? "down" : "off"))
    }

    private func iconButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(ALColor.textMuted)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(ALColor.active))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(ALColor.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func caption(_ tier: SubstitutionTier) -> String {
        switch tier {
        case .flagship: "Your best. Slowest and priciest — use when only the smartest will do."
        case .balanced: "Strong all-rounders. The everyday workhorses."
        case .fast: "Quick and cheap. Great for simple, high-volume work."
        }
    }
}
