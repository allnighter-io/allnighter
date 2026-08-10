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

    /// Machine-recognized seats only — catalog absences never enter the roster.
    private var rosterCards: [SetupCardModel] {
        CLISetupGrouping.recognizedCards(from: cards)
    }

    private var selectedCard: SetupCardModel? {
        cards.first { $0.driverId == selectedId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                summaryLine
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
        } else if let first = (attentionCards.first ?? rateLimitedCards.first ?? readyCards.first ?? dormantCards.first ?? parkedCards.first)?.driverId {
            selectedId = first
        } else {
            selectedId = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Setup")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(ALColor.textFaint)
                    .padding(.bottom, 7)
                Text("CLI setup")
                    .font(.system(size: 24, weight: .bold)).tracking(-0.48)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Choose which models are available across Allnighter. A CLI is just how a model gets here — turn a model on and it shows up everywhere you pick one.")
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
                    Label(model.isDetecting ? "Checking…" : "Re-check all", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.alSecondary(small: true))
                .disabled(model.isDetecting)
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

    // MARK: - Summary line (replaces the old 4 stat cards)

    private var summaryLine: some View {
        let tally = model.benchTally
        return HStack(spacing: 8) {
            StatusDot(color: ALPalette.green500, halo: ALPalette.green500.opacity(0.15))
            Group {
                Text("\(tally.ready)").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary)
                + Text(" ready").foregroundStyle(ALColor.textMuted)
                + Text("  ·  ").foregroundStyle(ALColor.textFaint)
                + Text("\(tally.needsStep)").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary)
                + Text(" need a step").foregroundStyle(ALColor.textMuted)
                + Text("  ·  ").foregroundStyle(ALColor.textFaint)
                + Text("\(model.availableModels.count)").fontWeight(.semibold).foregroundStyle(ALColor.textSecondary)
                + Text(" models available").foregroundStyle(ALColor.textMuted)
            }
            .font(.system(size: 12.5, design: .monospaced))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    // MARK: - Roster + repair

    // Grouped CLI list (CLI-setup redesign §1): Needs attention → Ready → Dormant,
    // sharing CLIStatusRow with the CLI dropdown. Selectable (amber focus ring).
    // Roster is machine-recognized only — never catalog notInstalled/notChecked.
    private func onModelNames(for driverId: String) -> [String] {
        model.models.filter { $0.enabled && $0.driverId == driverId }.map(\.displayName)
    }
    private var attentionCards: [SetupCardModel] {
        let base = CLISetupGrouping.attentionCards(from: rosterCards, onModelNames: onModelNames(for:))
        let cursorInstall = CLISetupGrouping.cursorInstallPromptCards(from: cards)
        // Prefer Cursor install at the top when the app is present but CLI is missing.
        var seen = Set(base.map(\.driverId))
        var merged = cursorInstall.filter { seen.insert($0.driverId).inserted }
        merged.append(contentsOf: base)
        return merged
    }
    private var readyCards: [SetupCardModel] {
        CLISetupGrouping.readyCards(from: rosterCards, onModelNames: onModelNames(for:))
    }
    private var dormantCards: [SetupCardModel] {
        CLISetupGrouping.dormantCards(from: rosterCards, onModelNames: onModelNames(for:))
    }
    private var parkedCards: [SetupCardModel] {
        CLISetupGrouping.parkedCards(from: rosterCards)
    }
    private var rateLimitedCards: [SetupCardModel] {
        CLISetupGrouping.rateLimitedCards(from: rosterCards)
    }

    private var bodyColumns: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                cliGroup("Needs attention", attentionCards, .attention)
                cliGroup("Rate limited", rateLimitedCards, .rateLimited)
                cliGroup("Ready", readyCards, .ready)
                cliGroup("Dormant", dormantCards, .dormant)
                cliGroup("Parked", parkedCards, .parked)
                censusFallback
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if let card = selectedCard {
                BenchRepairPanel(card: card)
                    .frame(width: 360)
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 40)
    }

    @ViewBuilder private func cliGroup(_ title: String, _ cards: [SetupCardModel], _ kind: CLIStatusGroup) -> some View {
        if !cards.isEmpty {
            SetupGroupLabel(title: title, count: cards.count)
            ForEach(cards) { card in
                CLIStatusRow(
                    card: card, onModels: onModelNames(for: card.driverId), kind: kind,
                    interactive: true, selected: card.driverId == selectedId,
                    onTap: { selectedId = card.driverId })
            }
        }
    }

    /// Agent fallback (onboarding only, never the dropdown): when a CLI we
    /// support isn't found AND a working agent exists, offer to search the
    /// machine for installs in non-standard spots. The quick scan + Spotlight
    /// (Track 0) already cover most cases, so this is a deliberate, framed last
    /// resort — honest about the time it takes and that it's read-only.
    @ViewBuilder private var censusFallback: some View {
        if model.canRunCensus || model.isRunningCensus {
            VStack(alignment: .leading, spacing: 8) {
                Text("Don't see one you installed?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
                Text("Our quick scan checks the usual spots. If you installed a CLI somewhere custom, an installed agent can search your machine and verify it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ALColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { model.runCensusDiscovery() } label: {
                    Label(model.isRunningCensus ? "Searching your machine…" : "Search my machine",
                          systemImage: model.isRunningCensus ? "hourglass" : "magnifyingglass")
                }
                .buttonStyle(.alSecondary(small: true))
                .disabled(!model.canRunCensus)
                Text(model.lastCensusSummary ?? "Read-only · ~30–60s · changes nothing")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(ALColor.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .padding(.top, 6)
        }
    }

}

// MARK: - Repair panel (sticky right column)

struct BenchRepairPanel: View {
    @Environment(AppModel.self) private var model
    let card: SetupCardModel

    @State private var addingModel = false
    @State private var newModelName = ""
    @State private var newModelLabel = ""
    @State private var logCopied = false
    @State private var loginCommandCopied = false

    /// Every model this CLI can honestly run (on-bench + available), A→Z. OpenCode
    /// hides fictional Go inventory rows — those are not serve provider ids.
    private var modelDefs: [ModelDefinition] {
        _ = model.models   // observe roster changes so the list refreshes after a toggle
        return ModelCatalog.list(driverId: card.driverId)
            .filter(OpenCodeModelGate.visibleInCLIRoster)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var isParked: Bool { card.state == .parked }

    /// Model toggles are for a working, signed-in CLI — never for install/login/repair.
    private var showsModelRoster: Bool {
        switch card.state {
        case .ready, .rateLimited:
            return !modelDefs.isEmpty
        default:
            return false
        }
    }

    /// Parking only after the CLI is on the machine and past the install gate.
    private var showsParkControl: Bool {
        switch card.state {
        case .notInstalled, .notChecked, .needsLogin, .waiting,
             .detecting, .reprobing, .queued, .installedNotProbed:
            return false
        default:
            return true
        }
    }

    /// Trust applies to headless runs — show only when the seat can actually run.
    private var showsTrustNotice: Bool {
        !isParked
            && card.showsHeadlessTrustDisclosure
            && card.headlessTrust != nil
            && (card.state == .ready || card.state == .rateLimited)
    }

    /// Last-proof is repair telemetry — hide during the one-job install/login screens.
    private var showsLastProof: Bool {
        switch card.state {
        case .notInstalled, .notChecked, .needsLogin, .waiting:
            return false
        case .reprobing, .detecting, .queued, .installedNotProbed:
            return false
        default:
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BrandGlyph(driverId: card.driverId, muted: isParked)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .opacity(isParked ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isParked ? ALColor.textMuted : ALColor.textPrimary)
                    Text(metaLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                repairPill
                    .opacity(isParked ? 0.55 : 1)
            }
            .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 13)
            .overlay(alignment: .bottom) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }

            VStack(alignment: .leading, spacing: 0) {
                // One job first: copy → primary action. Models/trust only after ready.
                Text(lead)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12).padding(.bottom, 14)

                if !isParked {
                    ForEach(Array(actions.enumerated()), id: \.offset) { idx, act in
                        repairActionRow(act, first: idx == 0)
                    }
                }

                if showsTrustNotice, let trust = card.headlessTrust {
                    HeadlessTrustNotice(policy: trust)
                        .padding(.top, 14)
                }

                if showsModelRoster {
                    detailModels
                        .padding(.top, 16)
                }

                if showsLastProof {
                    lastProof
                }

                if showsParkControl {
                    parkControl
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.xl))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.xl).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var parkControl: some View {
        HStack(spacing: 0) {
            parkSegment(title: "On bench", selected: !isParked) {
                model.setParked(card.driverId, parked: false)
            }
            parkSegment(title: "Parked", selected: isParked) {
                model.setParked(card.driverId, parked: true)
            }
        }
        .background(ALColor.active, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: ALRadius.md)
                .strokeBorder(ALColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CLI mode")
    }

    private func parkSegment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? ALColor.textPrimary : ALColor.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: ALRadius.md - 1)
                            .fill(ALColor.raised)
                            .padding(2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let v = card.version, !v.isEmpty { parts.append(v) }
        if !card.route.isEmpty { parts.append(card.route) }
        return parts.joined(separator: " · ")
    }

    private var detailModels: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Models on this CLI")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(ALColor.textFaint)
                Spacer(minLength: 0)
                Text("on bench")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(ALColor.textFaint)
            }
            ForEach(modelDefs) { def in modelRow(def) }
            if card.driverId == OpenCodeModelGate.driverId {
                openCodeGoRecommend
            }
            addModelControl
        }
    }

    @ViewBuilder
    private var openCodeGoRecommend: some View {
        let connected = OpenCodeModelGate.isGoConnected()
        VStack(alignment: .leading, spacing: 8) {
            Text(connected ? "OpenCode Go · connected" : "OpenCode Go")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(ALColor.textFaint)
            Text(connected ? OpenCodeModelGate.goConnectedDetail : OpenCodeModelGate.goRecommendDetail)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(ALColor.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if connected {
                    Button(OpenCodeModelGate.goConnectedPrimaryTitle) {
                        NSWorkspace.shared.open(OpenCodeModelGate.goPlanURL)
                    }
                    .buttonStyle(.alSecondary(small: true))
                } else {
                    Button(OpenCodeModelGate.goRecommendPrimaryTitle) {
                        NSWorkspace.shared.open(OpenCodeModelGate.goPlanURL)
                    }
                    .buttonStyle(.alPrimary(small: true))
                }
                Button("See the math") {
                    NSWorkspace.shared.open(OpenCodeModelGate.goDocsURL)
                }
                .buttonStyle(.alSecondary(small: true))
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func modelRow(_ def: ModelDefinition) -> some View {
        HStack(spacing: 8) {
            Text(def.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ALColor.textPrimary).lineLimit(1)
            Text(def.modelLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ALColor.textFaint).lineLimit(1)
            if def.origin == .custom {
                Text("custom").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ALColor.accent)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(ALColor.accent.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 8)
            if def.origin == .custom {
                Button { try? model.deleteCustomModel(modelId: def.id) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                }
                .buttonStyle(.plain).help("Delete this custom model")
            }
            Toggle("", isOn: Binding(
                get: { ModelCatalog.isEnabled(def.id) },
                set: { try? model.setModelEnabled(modelId: def.id, enabled: $0) }
            ))
            .labelsHidden().toggleStyle(.switch).tint(ALColor.accent)
            .help("On the bench — usable by teams")
        }
    }

    @ViewBuilder private var addModelControl: some View {
        if addingModel {
            VStack(alignment: .leading, spacing: 6) {
                addField("Model name", text: $newModelName)        // e.g. "Opus 5"
                addField("CLI model label", text: $newModelLabel)  // e.g. "opus" — what the CLI expects
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel") { resetAdd() }.buttonStyle(.alSecondary(small: true))
                    Button("Add") {
                        try? model.addCustomModel(driverId: card.driverId,
                                                  displayName: newModelName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  modelLabel: newModelLabel.trimmingCharacters(in: .whitespacesAndNewlines))
                        resetAdd()
                    }
                    .buttonStyle(.alPrimary(small: true))
                    .disabled(newModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || newModelLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.top, 4)
        } else {
            Button { addingModel = true } label: {
                Label("Add model", systemImage: "plus").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(ALColor.accentText).padding(.top, 2)
        }
    }

    private func addField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(ALColor.textPrimary)
            .padding(.horizontal, 9).frame(height: 30)
            .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }

    private func resetAdd() { addingModel = false; newModelName = ""; newModelLabel = "" }

    @ViewBuilder private var repairPill: some View { card.state.repairPill }

    private var isProbingThisCard: Bool {
        model.isDetecting && (model.probingDriverId == nil || model.probingDriverId == card.driverId)
    }

    private var lead: String {
        switch card.state {
        case .parked:
            return "Parked — won’t alert, won’t offer models, and won’t re-check until you put it back on the bench."
        case .reprobing:
            if card.driverId == CursorAgentCLIInstall.driverId, model.isInstallingCursorAgentCLI {
                return "Installing Cursor Agent CLI with Cursor’s official installer, then re-checking automatically."
            }
            if card.driverId == "opencode" {
                return "Starting OpenCode’s local server, then a short Zen smoke (opencode/big-pickle). First run can take 1–3 minutes — nothing else to install."
            }
            return "Running detect and smoke test for \(card.name)…"
        case .needsLogin, .waiting:
            if card.driverId == CursorAgentCLIInstall.driverId {
                return "Copy `cursor-agent login`, open a new Terminal window (don’t reuse a Grok session), paste, press Return. Finish browser sign-in if asked — then tap Re-check."
            }
            if card.driverId == "claude_code" {
                return "Login expired — open Terminal, start Claude Code with `claude`, then type `/login` inside Claude Code and finish browser sign-in. Then tap Re-check. `claude` alone is not the login command."
            }
            return "Copy the sign-in command, open a new Terminal window, paste, press Return. Then tap Re-check."
        case .needsPath:
            return "Found as a shell function, not a plain command. Point us at the binary, or run it through your login shell."
        case .probeFailed:
            if card.driverId == "opencode" {
                return "OpenCode is on PATH and the local serve is up — smoke used a bad model/provider label before. Re-try probe (Zen). Locate binary won’t help."
            }
            return "Detect passed but the smoke run failed — this is not a sign-in problem. Re-try the probe or copy the log for the real error."
        case .rateLimited:
            return card.probeReason ?? "Installed and healthy, but the vendor quota wall blocked the smoke run. It should clear on its own — re-check after the reset time."
        case .notInstalled:
            if card.driverId == CursorAgentCLIInstall.driverId {
                if let err = model.cursorAgentInstallError, !err.isEmpty {
                    return err
                }
                if CursorAgentCLIInstall.isCursorAppInstalled() {
                    return "You have Cursor. Alln needs the Agent CLI (the app is not the seat) — install once and Composer can join the bench."
                }
                return "Install the Cursor Agent CLI to use Composer. Prefer cursor-agent — bare agent may be Grok Build."
            }
            return "No binary resolved on PATH or known locations. Install it, then re-scan — it joins the bench automatically."
        case .notChecked:
            return "Not checked yet on this machine. Run a scan to detect it — most CLIs resolve with no further action."
        case .ready:
            if card.driverId == OpenCodeModelGate.driverId {
                return OpenCodeModelGate.isGoConnected()
                    ? "Go is connected — default Go seats are on the bench. Re-check reloads the local serve if it started before you subscribed."
                    : "OpenCode Zen is ready — subscribe to Go, connect the key in OpenCode, then Re-check to unlock seats here."
            }
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
            if card.driverId == "claude_code" {
                return [
                    RepairAction(
                        icon: "doc.on.doc",
                        title: "Copy `/login`",
                        subtitle: "Type this inside Claude Code after it opens — not a shell command",
                        button: loginCommandCopied ? "Copied" : "Copy",
                        primary: true,
                        secondary: false
                    ) {
                        SetupActions.copyToPasteboard("/login")
                        loginCommandCopied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            loginCommandCopied = false
                        }
                    },
                    RepairAction(
                        icon: "terminal",
                        title: "Open Terminal",
                        subtitle: "Run `claude` to open Claude Code, then paste `/login`",
                        button: "Open",
                        primary: false,
                        secondary: true
                    ) {
                        SetupActions.openTerminalApp()
                    },
                    RepairAction(
                        icon: "arrow.clockwise",
                        title: "Re-check",
                        subtitle: "After browser sign-in finishes, confirm Claude Code is ready",
                        button: isProbingThisCard ? "Checking…" : "Run",
                        primary: false,
                        secondary: false
                    ) {
                        model.runSetupProbe(userInitiated: true, onlyDriverId: card.driverId)
                    },
                ]
            }
            let loginCmd = resolvedLoginCommand
            return [
                RepairAction(
                    icon: "doc.on.doc",
                    title: "Copy sign-in command",
                    subtitle: loginCmd,
                    button: loginCommandCopied ? "Copied" : "Copy",
                    primary: true,
                    secondary: false
                ) {
                    SetupActions.copyToPasteboard(loginCmd)
                    loginCommandCopied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        loginCommandCopied = false
                    }
                },
                RepairAction(
                    icon: "terminal",
                    title: "Open Terminal",
                    subtitle: "Opens Terminal.app — paste into a new window, then press Return",
                    button: "Open",
                    primary: false,
                    secondary: true
                ) {
                    SetupActions.openTerminalApp()
                },
                RepairAction(
                    icon: "arrow.clockwise",
                    title: "Re-check",
                    subtitle: card.driverId == CursorAgentCLIInstall.driverId
                        ? "After sign-in finishes, confirm Cursor Agent is ready"
                        : "After sign-in finishes, confirm this CLI is ready",
                    button: isProbingThisCard ? "Checking…" : "Run",
                    primary: false,
                    secondary: false
                ) {
                    model.runSetupProbe(userInitiated: true, onlyDriverId: card.driverId)
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
            if card.driverId == "opencode" {
                return [
                    RepairAction(
                        icon: "arrow.clockwise",
                        title: "Re-try probe",
                        subtitle: "Runs a short OpenCode Zen smoke through the local serve on :4096",
                        button: isProbingThisCard ? "Running…" : "Run",
                        primary: true,
                        secondary: false
                    ) {
                        model.runSetupProbe(userInitiated: true, onlyDriverId: card.driverId)
                    },
                    RepairAction(
                        icon: "doc.on.doc",
                        title: "Copy log",
                        subtitle: "Copy the smoke error for support",
                        button: logCopied ? "Copied" : "Copy",
                        primary: false,
                        secondary: true
                    ) {
                        SetupActions.copyToPasteboard(card.probeLogText)
                        logCopied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            logCopied = false
                        }
                    },
                ]
            }
            return [
                RepairAction(icon: "arrow.clockwise", title: "Re-try probe", subtitle: probeRetrySubtitle, button: isProbingThisCard ? "Running…" : "Run", primary: true, secondary: false) {
                    model.runSetupProbe(userInitiated: true, onlyDriverId: card.driverId)
                },
                RepairAction(icon: "doc.on.doc", title: "Copy log", subtitle: "Copy probe details to the clipboard", button: logCopied ? "Copied" : "Copy", primary: false, secondary: true) {
                    SetupActions.copyToPasteboard(card.probeLogText)
                    logCopied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        logCopied = false
                    }
                },
                RepairAction(icon: "folder", title: "Locate the binary…", subtitle: "In case the wrong binary resolved", button: "Locate", primary: false, secondary: false) {
                    SetupActions.locateBinary()
                },
            ]
        case .rateLimited:
            return [
                RepairAction(icon: "arrow.clockwise", title: "Re-check", subtitle: "Probe again after the vendor limit resets", button: isProbingThisCard ? "Running…" : "Run", primary: true, secondary: false) {
                    model.runSetupProbe(userInitiated: true, onlyDriverId: card.driverId)
                },
            ]
        case .notInstalled:
            if card.driverId == CursorAgentCLIInstall.driverId {
                let installing = model.isInstallingCursorAgentCLI
                // Missing CLI: Install is the only job. Docs/re-check are noise until it exists.
                return [
                    RepairAction(
                        icon: "arrow.down.circle",
                        title: "Install Cursor Agent CLI",
                        subtitle: CursorAgentCLIInstall.isCursorAppInstalled()
                            ? "Runs Cursor’s official installer, then re-checks"
                            : "Downloads Cursor’s Agent CLI, then re-checks",
                        button: installing ? "Installing…" : "Install",
                        primary: true,
                        secondary: false
                    ) {
                        model.installCursorAgentCLI()
                    },
                ]
            }
            return [
                RepairAction(icon: "arrow.up.right.square", title: "Open install page", subtitle: "Opens the source's install docs", button: "Open", primary: true, secondary: false) {
                    if let url = card.docsURL, let u = URL(string: url) { NSWorkspace.shared.open(u) }
                },
                RepairAction(icon: "arrow.clockwise", title: "Re-scan", subtitle: "Look again once it's installed", button: "Run", primary: false, secondary: false) {
                    model.runFullSetupProbe(userInitiated: true)
                },
            ]
        case .notChecked:
            return [
                RepairAction(icon: "magnifyingglass", title: "Scan for this CLI", subtitle: "Runs Re-check all to detect every tool", button: "Scan", primary: true, secondary: false) {
                    model.runFullSetupProbe(userInitiated: true)
                },
            ]
        case .ready:
            if card.driverId == OpenCodeModelGate.driverId {
                return [
                    RepairAction(
                        icon: "arrow.clockwise",
                        title: "Re-check OpenCode",
                        subtitle: OpenCodeModelGate.isGoConnected()
                            ? "Reloads local serve if Go was connected after it started, then re-smokes Zen"
                            : "Re-smoke Zen — after you subscribe to Go and /connect, tap again to unlock seats",
                        button: isProbingThisCard ? "Checking…" : "Run",
                        primary: true,
                        secondary: false
                    ) {
                        model.runSetupProbe(userInitiated: true, onlyDriverId: card.driverId)
                    },
                ]
            }
            return []
        default:
            return []
        }
    }

    private var probeRetrySubtitle: String {
        card.driverId == "opencode"
            ? "Short OpenCode Zen smoke via local serve (:4096)"
            : "Run the smoke test again"
    }

    /// Prefer catalog login command; Cursor falls back to unambiguous `cursor-agent login`.
    private var resolvedLoginCommand: String {
        if let cmd = card.loginCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            return cmd
        }
        if card.driverId == CursorAgentCLIInstall.driverId {
            return "cursor-agent login"
        }
        return card.driverId
    }

    private func repairActionRow(_ act: RepairAction, first: Bool) -> some View {
        let probing = isProbingThisCard && (act.title == "Re-try probe" || act.title == "Install Cursor Agent CLI")
        return HStack(spacing: 12) {
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
                .disabled(probing || (act.title == "Install Cursor Agent CLI" && model.isInstallingCursorAgentCLI))
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
        }
    }

    private var lastProof: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Last proof")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
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
        case .reprobing:
            if card.driverId == CursorAgentCLIInstall.driverId {
                return [
                    [.init(text: "… ", tone: .prompt), .init(text: "Installing Cursor Agent CLI + re-check", tone: .normal)],
                ]
            }
            if card.driverId == "opencode" {
                return [
                    [.init(text: "… ", tone: .prompt), .init(text: "Starting local OpenCode server", tone: .normal)],
                    [.init(text: "… ", tone: .prompt), .init(text: "Running Zen smoke (big-pickle) — up to ~3 min", tone: .normal)],
                ]
            }
            return [
                [.init(text: "… ", tone: .prompt), .init(text: "Running detect + smoke probe", tone: .normal)],
            ]
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
        case .rateLimited:
            return [
                [.init(text: "⏳ ", tone: .prompt), .init(text: card.probeReason ?? "rate limited", tone: .normal)],
                [.init(text: "detected: ", tone: .normal), .init(text: card.version ?? card.name, tone: .normal), .init(text: " · install ", tone: .normal), .init(text: "ok", tone: .ok)],
            ]
        case .notInstalled:
            if card.driverId == CursorAgentCLIInstall.driverId {
                return [
                    [.init(text: "$ ", tone: .prompt), .init(text: CursorAgentCLIInstall.shellCommand, tone: .normal)],
                    [.init(text: "status: ", tone: .normal), .init(text: "not found", tone: .err)],
                ]
            }
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
