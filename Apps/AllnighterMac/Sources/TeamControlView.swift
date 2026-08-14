import SwiftUI
import AllnighterCore

// Top-bar Team control + "Your bench" dropdown (home/app.jsx → TeamControl).
// Reads live source status via AppModel — ready rows get a green dot; broken rows
// show a reason badge + Repair link.

// MARK: - Bench row model

struct BenchDropdownRow: Identifiable {
    let model: Model
    let subtitle: String
    let isReady: Bool
    let issueLabel: String?
    let issueTone: Badge.Tone
    let driverId: String

    var id: String { model.id }
}

// MARK: - Compact model glyph (hm-opt__g / hm-team__stack)

struct ModelBenchGlyph: View {
    let model: Model
    var boxSize: CGFloat = 27
    var iconSize: CGFloat = 15

    var body: some View {
        DriverBrandGlyph(
            driverId: model.driverId,
            boxSize: boxSize,
            iconSize: iconSize,
            cornerRadius: boxSize > 20 ? 7 : 5
        )
    }
}

// MARK: - Team pill frame (positions the dropdown flush under the pill)

struct TeamPillFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Team control (pill trigger; panel anchored in RootView)

struct TeamControlView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isOpen: Bool
    var onRepair: (String) -> Void = { _ in }
    var onManageTeam: () -> Void = {}

    @State private var pillHover = false

    private var rows: [BenchDropdownRow] { appModel.benchDropdownRows }
    private var readyCount: Int { rows.filter(\.isReady).count }
    private var stackModels: [Model] { Array(rows.prefix(4).map(\.model)) }

    // Pill only in the title bar. RootView anchors the dropdown flush beneath it
    // via TeamPillAnchorKey so the panel never clips or floats detached.
    var body: some View {
        pillButton
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TeamPillFrameKey.self,
                        value: geo.frame(in: .global)
                    )
                }
            }
            .fixedSize(horizontal: true, vertical: true)
    }

    private var pillButton: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                avatarStack
                Text(ChromeCopy.models)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALColor.textSecondary)
                Circle().fill(statusDotColor).frame(width: 7, height: 7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ALColor.textFaint)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.leading, 7).padding(.trailing, 9)
            .frame(height: 28)
            .background(pillBackground)
            .clipShape(pillShape)
            .overlay {
                if isOpen {
                    // Attached panel carries the shared edge; omit the pill bottom stroke.
                    pillShape.stroke(pillBorder, lineWidth: 1)
                        .mask(alignment: .top) {
                            Rectangle().frame(height: 28)
                        }
                } else {
                    pillShape.stroke(pillBorder, lineWidth: 1)
                }
            }
        }
        .buttonStyle(TeamPillButtonStyle(isOpen: isOpen))
        .onHover { pillHover = $0 }
        .accessibilityLabel("Your team")
        .help("Your bench — \(readyCount) of \(rows.count) models ready")
    }

    // Honest launch-trust dot: green only when a tool is actually confirmed
    // ready. On a process-quiet cold launch (Launch Authority TCC hotfix) nothing
    // is probed yet, so the dot stays neutral rather than implying readiness.
    private var statusDotColor: Color {
        if appModel.isDetecting { return ALColor.textFaint }
        return readyCount > 0 ? ALPalette.green500 : ALColor.textFaint
    }

    private var pillBackground: Color {
        if isOpen { return ALColor.surface }
        return pillHover ? ALColor.hover : ALColor.raised
    }

    private var pillBorder: Color {
        if isOpen || pillHover { return ALColor.borderStrong }
        return ALColor.borderDefault
    }

    private var pillShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: ALRadius.pill,
            bottomLeadingRadius: isOpen ? 0 : ALRadius.pill,
            bottomTrailingRadius: isOpen ? 0 : ALRadius.pill,
            topTrailingRadius: ALRadius.pill
        )
    }

    private var avatarStack: some View {
        HStack(spacing: -6) {
            ForEach(Array(stackModels.enumerated()), id: \.element.id) { idx, model in
                ModelBenchGlyph(model: model, boxSize: 18, iconSize: 11)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(ALColor.surface, lineWidth: 1.5)
                    }
                    .zIndex(Double(idx))
            }
        }
    }
}

// MARK: - Bench dropdown panel (hm-pop)

struct BenchDropdownPanel: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isOpen: Bool
    var attached: Bool = false
    var onRepair: (String) -> Void = { _ in }
    var onManageTeam: () -> Void = {}
    var onOpenSetup: () -> Void = {}

    private var panelShape: UnevenRoundedRectangle {
        if attached {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: ALRadius.lg,
                bottomTrailingRadius: ALRadius.lg,
                topTrailingRadius: 0
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: ALRadius.lg,
                bottomLeadingRadius: ALRadius.lg,
                bottomTrailingRadius: ALRadius.lg,
                topTrailingRadius: ALRadius.lg
            )
        }
    }

    /// CLI-setup redesign §Models Dropdown: only ON + ready models, flat A→Z. OFF or
    /// not-ready models never appear here — they live on the CLI setup page.
    private var availableModels: [Model] { appModel.availableModels }

    /// Auto's resolved default model name — the same resolution the composer chip
    /// shows ("Auto · Opus 5"). Cached on open (it reads persisted settings).
    @State private var autoModelName: String?

    private func resolveAutoModelName() {
        let settings = DefaultModelSettingsPersistence().load()
        let readyIds = Set(appModel.availableModels.map(\.id))
        let resolved = SubstitutionResolver.resolveAuto(settings: settings, readyModelIds: readyIds).resolvedModelId
        autoModelName = resolved.flatMap { id in appModel.availableModels.first { $0.id == id }?.displayName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            rowList
            footer
        }
        .frame(width: 360)
        .background(ALColor.surface)
        .clipShape(panelShape)
        .overlay { panelShape.stroke(ALColor.borderDefault, lineWidth: 1) }
        .alShadowXl()
        .onAppear { resolveAutoModelName(); appModel.refreshCapacityCooldowns() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(ChromeCopy.models)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(ALColor.textPrimary)
            Text("\(availableModels.count) available · \(appModel.availableModelCLICount) CLIs")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ALColor.textFaint)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var rowList: some View {
        // ScrollView needs an explicit height here — without it the list collapses to
        // zero inside the attached popover VStack (header + footer only). +1 row for the
        // pinned Auto entry that always leads the list.
        let height = min(CGFloat(availableModels.count + 1) * 46 + 12, 322)
        return ScrollView {
            VStack(spacing: 1) {
                // Auto is ALWAYS pinned to the top — the default route every user should
                // see, resolving to their default model.
                AutoDropdownRow(modelName: autoModelName)
                if !availableModels.isEmpty {
                    Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
                ForEach(availableModels) { ModelDropdownRow(model: $0) }
            }
            .padding(6)
        }
        .frame(height: max(height, 46))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                isOpen = false
                // Opens the full Settings shell (sidebar: CLIs · Teams · Skills per
                // lane), landing on CLIs — NOT the sidebarless standalone page.
                onManageTeam()
            } label: {
                Label("Manage in settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.alSecondary(small: true))
            Text("Only models you've turned on appear here.")
                .font(.system(size: 11))
                .foregroundStyle(ALColor.textFaint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ALColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }
}

/// The pinned Auto row at the top of the Models dropdown — the default route that
/// resolves to your default model (substituting within its tier when a CLI is down).
/// Always shown so users always see Auto, even before they touch the bench.
private struct AutoDropdownRow: View {
    let modelName: String?
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "infinity")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ALColor.textSecondary)
                .frame(width: 34, height: 34)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("Auto")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Text(modelName ?? "Default model")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Circle().fill(modelName != nil ? ALPalette.green500 : ALColor.textFaint).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? ALColor.hover : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        .onHover { hover = $0 }
    }
}

/// One model row in the Models dropdown: source-CLI glyph · name · CLI slug · green
/// dot. (Available models are ON + ready, so the dot is always green — broken/repair
/// states live in the CLI dropdown, not here.)
private struct ModelDropdownRow: View {
    let model: Model
    @State private var hover = false

    private var slug: String {
        model.driverId
            .replacingOccurrences(of: "_agent", with: "")
            .replacingOccurrences(of: "_", with: "-")
    }

    var body: some View {
        HStack(spacing: 12) {
            DriverBrandGlyph(driverId: model.driverId, boxSize: 34, iconSize: 17, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                Text(slug)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Circle().fill(ALPalette.green500).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? ALColor.hover : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        .onHover { hover = $0 }
    }
}

private struct TeamPillButtonStyle: ButtonStyle {
    var isOpen: Bool = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(ALMotion.fast, value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

// MARK: - Dropdown row

private struct BenchDropdownRowView: View {
    let row: BenchDropdownRow
    var onRepair: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ModelBenchGlyph(model: row.model)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.model.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(ALColor.textFaint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            trailingAction
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hover ? ALColor.hover : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        .onHover { hover = $0 }
    }

    @ViewBuilder private var trailingAction: some View {
        if row.isReady {
            Circle().fill(ALPalette.green500).frame(width: 7, height: 7)
        } else if let label = row.issueLabel {
            HStack(spacing: 8) {
                Badge(text: label, tone: row.issueTone)
                    .fixedSize(horizontal: true, vertical: false)
                Button(action: onRepair) {
                    Text("Repair")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ALColor.textPrimary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - AppModel bench helpers

extension AppModel {
    var benchModels: [Model] {
        models.filter(\.enabled).sorted { benchSortRank($0) < benchSortRank($1) }
    }

    /// Display order for the bench dropdown (matches home/app.jsx BENCH_ROWS).
    private func benchSortRank(_ model: Model) -> Int {
        switch model.id {
        case "model_opus", "model_claude": return 0
        case "model_sonnet": return 1
        case "model_grok": return 2
        case "model_gemini": return 3
        case "model_gpt_sol": return 4
        case "model_grok_composer_25_fast": return 5
        default:
            switch model.driverId {
            case "claude_code": return model.canWritePlan ? 0 : 1
            case "grok": return model.displayName.lowercased().contains("composer") ? 5 : 2
            case "antigravity": return 3
            case "codex": return 4
            default: return 10
            }
        }
    }

    var readyModelCount: Int { benchDropdownRows.filter(\.isReady).count }

    var benchDropdownRows: [BenchDropdownRow] {
        benchModels.map { model in
            let card = setupCards.first { $0.driverId == model.driverId }
            let ready = toolStatus(for: model.driverId)?.status.isSmokeReady ?? false
            let (issue, tone) = card.map { issueBadge(for: $0.state) } ?? ("Not detected", Badge.Tone.warning)
            return BenchDropdownRow(
                model: model,
                subtitle: benchCLIRoute(for: model, card: card),
                isReady: ready,
                issueLabel: ready ? nil : issue,
                issueTone: ready ? .neutral : tone,
                driverId: model.driverId
            )
        }
    }

    /// The source CLI slug — what Allnighter invokes, not the model name again.
    private func benchCLIRoute(for model: Model, card: SetupCardModel?) -> String {
        if let route = card?.route {
            return route.replacingOccurrences(of: "via ", with: "")
        }
        return model.driverId.replacingOccurrences(of: "_", with: "-")
    }

    private func issueBadge(for state: SetupCardState) -> (String, Badge.Tone) {
        switch state {
        case .ready: ("Ready", .positive)
        case .needsLogin, .waiting: ("Not signed in", .warning)
        case .needsPath: ("Needs a path", .warning)
        case .notInstalled, .installedNotProbed: ("Not detected", .warning)
        case .probeFailed: ("Probe failed", .danger)
        case .rateLimited: ("Rate limited", .warning)
        case .detecting, .reprobing, .queued: ("Checking…", .neutral)
        case .notChecked: ("Not checked", .neutral)
        case .parked: ("Parked", .neutral)
        }
    }
}

// MARK: - Preview

#Preview("Team control") {
    @Previewable @State var open = true
    TeamControlView(isOpen: $open)
        .padding(40)
        .frame(width: 420, height: 520, alignment: .topTrailing)
        .background(ALColor.base)
        .environment(AppModel())
}
