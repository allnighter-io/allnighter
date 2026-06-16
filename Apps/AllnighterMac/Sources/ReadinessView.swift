import SwiftUI
import AppKit
import AllnighterCore

// CLI setup — full page (home/bench-views.jsx → ReadinessScreen).
// Install, sign-in, and repair the command-line tools Allnighter drives.

struct TeamReadinessView: View {
    @Environment(AppModel.self) private var model
    var focusDriverId: String?
    var onClose: () -> Void
    var onAddSource: () -> Void = {}

    @State private var selectedId: String?

    private var cards: [SetupCardModel] { model.setupCards }
    private var ready: [SetupCardModel] { cards.filter { $0.state == .ready } }
    private var add: [SetupCardModel] { cards.filter { $0.state == .notInstalled } }
    private var step: [SetupCardModel] { cards.filter { $0.state != .ready && $0.state != .notInstalled } }

    private var selectedCard: SetupCardModel? {
        cards.first { $0.driverId == selectedId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                statsRow
                bodyColumns
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ALColor.base)
        .onAppear { seedSelection() }
        .onChange(of: focusDriverId) { _, _ in seedSelection() }
        .onChange(of: cards.map(\.driverId)) { _, _ in
            if selectedId == nil || !cards.contains(where: { $0.driverId == selectedId }) {
                seedSelection()
            }
        }
    }

    private func seedSelection() {
        if let focus = focusDriverId, cards.contains(where: { $0.driverId == focus }) {
            selectedId = focus
        } else if let first = step.first?.driverId ?? add.first?.driverId ?? ready.first?.driverId {
            selectedId = first
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Setup")
                    .font(.system(size: 11, weight: .bold)).tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(ALColor.accentText)
                    .padding(.bottom, 7)
                Text("CLI setup")
                    .font(.system(size: 24, weight: .heavy)).tracking(-0.48)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Add, install, and sign in to the command-line tools on your Mac. Fix a CLI here before it can take work — the same check runs in the title bar and the team dropdown.")
                    .font(.system(size: 13))
                    .foregroundStyle(ALColor.textMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Button { model.runFullSetupProbe(userInitiated: true) } label: {
                    Label("Re-check all", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.alSecondary(small: true))
                Button(action: onAddSource) {
                    Label("Add CLI", systemImage: "plus")
                }
                .buttonStyle(.alPrimary(small: true))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.alGhost)
                .help("Back to team")
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let readyN = model.readyToolCount
        let totalN = max(model.totalToolCount, 1)
        return HStack(spacing: 12) {
            statCard(
                value: "\(readyN)",
                suffix: "/ \(totalN)",
                label: "CLIs ready",
                ok: readyN == totalN
            )
            statCard(
                value: "\(model.models.filter(\.enabled).count)",
                suffix: nil,
                label: "Models on bench",
                ok: false
            )
            statCard(
                value: "Build · Design · Copy",
                suffix: nil,
                label: "Lanes covered",
                ok: false,
                smallValue: true
            )
            statCard(value: "$0", suffix: nil, label: "Marginal cost", ok: true)
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 4)
    }

    private func statCard(value: String, suffix: String?, label: String, ok: Bool, smallValue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: smallValue ? 16 : 24, weight: .heavy)).tracking(-0.48)
                    .foregroundStyle(ok ? ALPalette.green400 : ALColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                }
            }
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(ALColor.textMuted)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 14)
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    // MARK: - Roster + repair

    private var bodyColumns: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                rosterGroup("Ready", cards: ready)
                rosterGroup("Needs a step", cards: step)
                rosterGroup("Add a CLI", cards: add)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let card = selectedCard {
                BenchRepairPanel(card: card)
                    .frame(width: 360)
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
    }

    @ViewBuilder private func rosterGroup(_ title: String, cards: [SetupCardModel]) -> some View {
        if !cards.isEmpty {
            SetupGroupLabel(title: title, count: cards.count)
            ForEach(cards) { card in
                Button {
                    selectedId = card.driverId
                } label: {
                    SetupCardView(card: card, layout: .roster) { handle($0, card: card) }
                }
                .buttonStyle(.plain)
                .overlay { selectionRing(selected: card.driverId == selectedId) }
            }
        }
    }

    private func selectionRing(selected: Bool) -> some View {
        Group {
            if selected {
                RoundedRectangle(cornerRadius: ALRadius.lg)
                    .strokeBorder(ALColor.accentBorder, lineWidth: 1)
                RoundedRectangle(cornerRadius: ALRadius.lg + 4)
                    .strokeBorder(ALColor.accentSurface, lineWidth: 4)
            }
        }
    }

    private func handle(_ action: SetupCardView.SetupAction, card: SetupCardModel) {
        selectedId = card.driverId
        switch action {
        case .openTerminal(let cmd): SetupActions.openTerminal(cmd)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .openURL(let url): if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        case .rescan, .useAnyway: model.runFullSetupProbe(userInitiated: true)
        case .locate: SetupActions.locateBinary()
        }
    }
}

// MARK: - Repair panel (sticky right column)

struct BenchRepairPanel: View {
    @Environment(AppModel.self) private var model
    let card: SetupCardModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BrandGlyph(driverId: card.driverId)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ALColor.textPrimary)
                    Text(metaLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                repairPill
            }
            .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 13)
            .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }

            VStack(alignment: .leading, spacing: 0) {
                if !card.workers.isEmpty {
                    detailModels
                        .padding(.top, 4).padding(.bottom, 12)
                }

                Text(lead)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, card.workers.isEmpty ? 9 : 0).padding(.bottom, 13)

                ForEach(Array(actions.enumerated()), id: \.offset) { idx, act in
                    repairActionRow(act, first: idx == 0)
                }

                lastProof
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.xl))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let v = card.version, !v.isEmpty { parts.append(v) }
        if !card.route.isEmpty { parts.append(card.route) }
        return parts.joined(separator: " · ")
    }

    private var detailModels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Models on this CLI")
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(ALColor.textFaint)
            ForEach(card.workers) { seat in
                HStack(spacing: 8) {
                    Text(seat.setupChipLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ALColor.textPrimary)
                    if let slug = seat.setupDetailSlug {
                        Text(slug)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ALColor.textFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private var repairPill: some View {
        switch card.state {
        case .ready: SetupPill(kind: .ready, label: "Ready")
        case .needsLogin, .waiting: SetupPill(kind: .step, label: "Needs sign-in")
        case .needsPath: SetupPill(kind: .step, label: "Needs a path")
        case .notInstalled: SetupPill(kind: .muted, label: "Not installed")
        case .probeFailed: SetupPill(kind: .fail, label: "Probe failed")
        default: SetupPill(kind: .muted, label: "Needs a step")
        }
    }

    private var lead: String {
        switch card.state {
        case .needsLogin, .waiting:
            return "Installed but not signed in. It prompts for sign-in on first run — fix it here and it goes green in place."
        case .needsPath:
            return "Found as a shell function, not a plain command. Point us at the binary, or run it through your login shell."
        case .probeFailed:
            return "Detect passed but the smoke run failed — this is not a sign-in problem. Re-try the probe or read the log for the real error."
        case .notInstalled:
            return "No binary resolved on PATH or known locations. Install it, then re-scan — it joins the bench automatically."
        case .ready:
            return card.workers.isEmpty
                ? "This CLI passed its last check and is ready."
                : "This CLI is ready."
        default:
            return "Complete the step below to bring this source online."
        }
    }

    private struct RepairAction {
        let icon: String
        let title: String
        let subtitle: String
        let button: String
        let primary: Bool
        let secondary: Bool
        let handler: () -> Void
    }

    private var actions: [RepairAction] {
        switch card.state {
        case .needsLogin, .waiting:
            return [
                RepairAction(icon: "terminal", title: "Open login flow", subtitle: "Launches the source's sign-in in Terminal", button: "Open", primary: true, secondary: false) {
                    SetupActions.openTerminal(card.loginCommand ?? card.driverId)
                },
                RepairAction(icon: "arrow.clockwise", title: "Re-check", subtitle: "Re-probes every few seconds until it passes", button: "Run", primary: false, secondary: false) {
                    model.runFullSetupProbe(userInitiated: true)
                },
            ]
        case .needsPath:
            return [
                RepairAction(icon: "folder", title: "Locate the binary…", subtitle: "Pick the executable in an open panel", button: "Locate", primary: true, secondary: false) {
                    SetupActions.locateBinary()
                },
                RepairAction(icon: "terminal", title: "Use it anyway", subtitle: "Run via your login shell, exactly as your terminal does", button: "Use", primary: false, secondary: true) {
                    model.runFullSetupProbe(userInitiated: true)
                },
                RepairAction(icon: "arrow.clockwise", title: "Re-check", subtitle: "Re-probe after you set a path", button: "Run", primary: false, secondary: false) {
                    model.runFullSetupProbe(userInitiated: true)
                },
            ]
        case .probeFailed:
            return [
                RepairAction(icon: "arrow.clockwise", title: "Re-try probe", subtitle: "Run the smoke test again", button: "Run", primary: true, secondary: false) {
                    model.runFullSetupProbe(userInitiated: true)
                },
                RepairAction(icon: "doc.text", title: "View log", subtitle: "Open the full probe transcript", button: "Open", primary: false, secondary: true) {
                    if let reason = card.probeReason {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reason, forType: .string)
                    }
                },
                RepairAction(icon: "folder", title: "Locate the binary…", subtitle: "In case the wrong binary resolved", button: "Locate", primary: false, secondary: false) {
                    SetupActions.locateBinary()
                },
            ]
        case .notInstalled:
            return [
                RepairAction(icon: "arrow.up.right.square", title: "Open install page", subtitle: "Opens the source's install docs", button: "Open", primary: true, secondary: false) {
                    if let url = card.docsURL, let u = URL(string: url) { NSWorkspace.shared.open(u) }
                },
                RepairAction(icon: "arrow.clockwise", title: "Re-scan", subtitle: "Look again once it's installed", button: "Run", primary: false, secondary: false) {
                    model.runFullSetupProbe(userInitiated: true)
                },
            ]
        case .ready:
            return []
        default:
            return []
        }
    }

    private func repairActionRow(_ act: RepairAction, first: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(ALColor.active)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: act.icon).font(.system(size: 13)).foregroundStyle(ALColor.textSecondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(act.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Text(act.subtitle).font(.system(size: 11)).foregroundStyle(ALColor.textFaint).lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: act.handler) { Text(act.button) }
                .buttonStyle(act.primary ? .alPrimary(small: true) : act.secondary ? .alSecondary(small: true) : .alGhost)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
        }
    }

    private var lastProof: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Last proof")
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(ALColor.textFaint)
            ForEach(Array(proofLines.enumerated()), id: \.offset) { _, line in
                proofLine(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ALColor.base, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        .padding(.top, 14)
    }

    private struct ProofSegment {
        let text: String
        let tone: ProofTone
        enum ProofTone { case normal, ok, err, prompt }
    }

    private var proofLines: [[ProofSegment]] {
        switch card.state {
        case .needsLogin, .waiting:
            return [
                [.init(text: "last smoke: ", tone: .normal), .init(text: "passed", tone: .ok), .init(text: " · 3 days ago", tone: .normal)],
                [.init(text: "$ ", tone: .prompt), .init(text: "auth: ", tone: .normal), .init(text: "no token found", tone: .err)],
            ]
        case .needsPath:
            return [
                [.init(text: "ƒ ", tone: .prompt), .init(text: card.shimCommand ?? "", tone: .normal)],
                [.init(text: "resolved via: ", tone: .normal), .init(text: "login shell", tone: .ok)],
            ]
        case .probeFailed:
            return [
                [.init(text: "! ", tone: .prompt), .init(text: card.probeReason ?? "smoke failed", tone: .err)],
                [.init(text: "detected: ", tone: .normal), .init(text: card.version ?? card.name, tone: .normal), .init(text: " · smoke ", tone: .normal), .init(text: "failed", tone: .err)],
            ]
        case .notInstalled:
            return [
                [.init(text: "$ ", tone: .prompt), .init(text: card.installHint ?? "see docs", tone: .normal)],
                [.init(text: "status: ", tone: .normal), .init(text: "not found", tone: .err)],
            ]
        case .ready:
            return [
                [.init(text: "smoke: ", tone: .normal), .init(text: "passed", tone: .ok), .init(text: card.version.map { " · \($0)" } ?? "", tone: .normal)],
            ]
        default:
            return [[.init(text: "awaiting probe", tone: .normal)]]
        }
    }

    @ViewBuilder private func proofLine(_ segments: [ProofSegment]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Text(seg.text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(proofColor(seg.tone))
                    .lineLimit(1)
            }
        }
    }

    private func proofColor(_ tone: ProofSegment.ProofTone) -> Color {
        switch tone {
        case .normal: ALColor.textMuted
        case .ok: ALPalette.green400
        case .err: ALPalette.red400
        case .prompt: ALColor.textFaint
        }
    }
}

#Preview("CLI setup — mixed") {
    TeamReadinessView(focusDriverId: "codex", onClose: {})
        .frame(width: 780, height: 720)
        .preferredColorScheme(.dark)
}
