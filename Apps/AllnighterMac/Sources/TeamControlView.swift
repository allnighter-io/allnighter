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
        RoundedRectangle(cornerRadius: boxSize > 20 ? 7 : 5)
            .fill(ALColor.active)
            .frame(width: boxSize, height: boxSize)
            .overlay { mark.opacity(muted ? 0.5 : 1) }
    }

    private var muted: Bool { false }

    @ViewBuilder private var mark: some View {
        switch asset {
        case .brand(let name, let tint):
            Image(name).renderingMode(.template).resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(tint)
        case .symbol(let system):
            Image(systemName: system).font(.system(size: iconSize * 0.85))
                .foregroundStyle(ALColor.textSecondary)
        }
    }

    private enum Asset { case brand(String, Color); case symbol(String) }

    private var asset: Asset {
        let driver = model.driverId
        let name = model.displayName.lowercased()
        switch driver {
        case "claude_code":
            let tint: Color = name.contains("sonnet") ? ALColor.textSecondary : ALColor.accent
            return .brand("anthropic", tint)
        case "antigravity": return .brand("googlegemini", ALColor.textPrimary)
        case "grok": return .brand("x", ALColor.textPrimary)
        default: return .symbol(glyphSymbol)
        }
    }

    private var glyphSymbol: String {
        let d = model.driverId.lowercased()
        let n = model.displayName.lowercased()
        if d.contains("gemini") || d.contains("antigravity") { return "sparkle" }
        if d.contains("codex") || n.contains("chatgpt") || n.contains("gpt") { return "terminal" }
        if d.contains("cursor") || n.contains("composer") { return "squareshape" }
        if d.contains("grok") || n.contains("grok") { return "bolt.fill" }
        return "cpu"
    }
}

// MARK: - Team control (pill + attached dropdown)

struct TeamControlView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var isOpen: Bool
    var onRepair: (String) -> Void = { _ in }
    var onManageTeam: () -> Void = {}

    @State private var pillHover = false

    private var rows: [BenchDropdownRow] { appModel.benchDropdownRows }
    private var readyCount: Int { rows.filter(\.isReady).count }
    private var stackModels: [Model] { Array(rows.prefix(4).map(\.model)) }

    // Only the pill lives in the title bar. The dropdown panel is presented by
    // RootView as a top-level overlay BELOW the title bar (the proven `showDoctor`
    // pattern), because the title bar's centered ZStack + an intrinsically-tall
    // panel made the open dropdown overflow past the window's top edge.
    var body: some View {
        pillButton
            .fixedSize(horizontal: true, vertical: true)
    }

    private var pillButton: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                avatarStack
                Text("Team")
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
            .overlay { pillShape.stroke(pillBorder, lineWidth: 1) }
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

    private var rows: [BenchDropdownRow] { appModel.benchDropdownRows }
    private var readyCount: Int { rows.filter(\.isReady).count }

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

    var body: some View {
        VStack(spacing: 0) {
            header
            rowList
            footer
        }
        .frame(width: 306)
        .background(ALColor.surface)
        .clipShape(panelShape)
        .overlay { panelShape.stroke(ALColor.borderDefault, lineWidth: 1) }
        .alShadowXl()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Your bench")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(ALColor.textPrimary)
            Text("\(readyCount) of \(rows.count) models ready")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(ALColor.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var rowList: some View {
        // ScrollView needs an explicit height here — without it the list collapses to
        // zero inside the attached popover VStack (header + footer only).
        let height = min(CGFloat(rows.count) * 43 + 12, 248)
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    BenchDropdownRowView(row: row) {
                        isOpen = false
                        onRepair(row.driverId)
                    }
                }
            }
            .padding(6)
        }
        .frame(height: max(height, rows.isEmpty ? 0 : 43))
    }

    private var footer: some View {
        VStack(spacing: 9) {
            // Explicit, user-owned probe trigger. Cold launch is process-quiet
            // (Launch Authority TCC hotfix), so this is the first place a live
            // check of the local CLIs is allowed to run — and the only reachable
            // one in the active UI. Running CLIs may take a moment + spend quota.
            Button {
                appModel.runFullSetupProbe(userInitiated: true)
            } label: {
                Label(appModel.isDetecting ? "Checking tools…" : "Check tools",
                      systemImage: appModel.isDetecting ? "hourglass" : "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.alPrimary(small: true))
            .disabled(appModel.isDetecting)
            .help("Launches your local CLIs to verify which models are ready. May take a moment and use quota.")

            HStack(spacing: 9) {
                Button {
                    isOpen = false
                    onManageTeam()
                } label: {
                    Label("Manage team", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.alSecondary(small: true))
                Text("Add models & build teams in settings.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ALColor.textFaint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ALColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
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
            trailingAction
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
        case "model_chatgpt": return 4
        case "model_composer": return 5
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
            let ready = toolStatus(for: model.driverId)?.status.isReady ?? false
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
        case .detecting, .reprobing, .queued: ("Checking…", .neutral)
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
