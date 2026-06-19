import SwiftUI
import AppKit
import AllnighterCore

// Compose Routing composer (docs/phases/wiring/design_handoff_compose_routing).
// The composer reads as a sentence: [verb] → [who] → [effort].
//   - Mode pill (Chat / Fan out / Execute) with ⌘1/⌘2/⌘3, opening the mode menu.
//   - Adaptive target chip carrying who + effort (model for chat/exec, lane team
//     for fan out).
//   - Send button whose label reflects the armed verb.
// CR1: the bar + mode menu. Target popovers + effort row = CR2; real-model
// wiring = CR3; thread integration = CR4. Until then it runs on local prototype
// data that mirrors reference/app.jsx, so the surface is provable in isolation.

enum ComposeMode: String, CaseIterable { case chat, sendToTeam, exec }
enum ComposeEffort: String, CaseIterable { case low, med, high }
enum ComposeLane: String, CaseIterable { case code, design, copy, signal }

/// Everything the composer arms when the user clicks Send.
struct ComposeRouting: Equatable {
    var mode: ComposeMode
    var to: String
    var effort: ComposeEffort
    var lane: ComposeLane
    var team: String
    var text: String
}

/// Thread-aware defaults for the routing composer (verb re-seeds on switch;
/// effort/team persist in the composer's local state).
enum ComposeRoutingDefaults {
    /// Spec/board ready → Execute; everything else → Chat.
    static func mode(for thread: WorkThread?) -> ComposeMode {
        guard let thread else { return .chat }
        return ThreadsPresenter.routingDefaultMode(for: thread)
    }
}

/// A bench model as the composer sees it (CR3 maps this from AppModel).
struct ComposeBenchModel: Identifiable, Equatable {
    let id: String
    let name: String
    let driverId: String      // for DriverBrandGlyph
    let cli: String           // slug shown on the bench chip (e.g. "claude-code")
    let sub: String
    let ready: Bool
    var notReadyReason: String?
}

/// A saved team for a lane (CR3 maps this from presets).
struct ComposeTeam: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let isDefault: Bool
}

extension ComposeMode {
    var label: String { switch self { case .chat: "Chat"; case .sendToTeam: "Send to team"; case .exec: "Execute" } }
    var icon: String { switch self { case .chat: "message"; case .sendToTeam: "rectangle.stack"; case .exec: "hammer" } }
    var kbd: String { switch self { case .chat: "⌘1"; case .sendToTeam: "⌘2"; case .exec: "⌘3" } }
    var desc: String {
        switch self {
        case .chat: "One model answers — route the turn to anyone."
        case .sendToTeam: "A team answers in parallel → a board to compare and pick."
        case .exec: "An agent runs it in your repo and the result returns here."
        }
    }
}

extension ComposeEffort { var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() } }
extension ComposeLane {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var icon: String { switch self { case .code: "hammer"; case .design: "photo"; case .copy: "doc.text"; case .signal: "antenna.radiowaves.left.and.right" } }
    var workLane: WorkLane { switch self { case .code: .code; case .design: .design; case .copy: .copy; case .signal: .signal } }
}

/// Proof/specimen container — shows the composer on the dark canvas, anchored
/// like the thread pane, for the GUI proof gate + the dev GUI-routes sheet.
/// Real placement in the thread workspace lands in CR4.
struct ComposeSpecimen: View {
    var openModeMenu: Bool = false
    var openTarget: Bool = false
    var mode: ComposeMode = .chat
    var body: some View {
        VStack {
            Spacer()
            RoutingComposer(mode: mode, openModeMenu: openModeMenu, openTarget: openTarget)
                .frame(maxWidth: 680)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

struct RoutingComposer: View {
    enum Popover { case mode, target }

    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(CommandCenter.self) private var commands
    @State var mode: ComposeMode
    @State var to: String
    @State var effort: ComposeEffort
    @State var lane: ComposeLane
    @State var team: String
    @State private var text: String = ""
    @State private var pop: Popover?

    @State private var composerFocused = false
    @State private var editorHeight = ComposeEditorMetrics.minHeight

    let placeholder: String
    private let big: Bool
    /// Re-seeded when the active thread changes; effort/team are left alone.
    let defaultMode: ComposeMode
    /// Lock the turn to Send-to-team (hide the Chat/Send/Execute mode pill). Used by
    /// the launcher's team modal, where the team is already chosen.
    private let lockedSendToTeam: Bool
    var onSend: ((ComposeRouting) -> Void)?

    init(
        mode: ComposeMode = .chat,
        lane: ComposeLane = .design,
        team: String = "",
        openModeMenu: Bool = false,
        openTarget: Bool = false,
        big: Bool = false,
        defaultMode: ComposeMode = .chat,
        lockedSendToTeam: Bool = false,
        onSend: ((ComposeRouting) -> Void)? = nil
    ) {
        _mode = State(initialValue: mode)
        _to = State(initialValue: "")     // seeded from the real bench in onAppear
        _effort = State(initialValue: .med)
        _lane = State(initialValue: lane)
        _team = State(initialValue: team) // empty → seeded from the real catalog in onAppear
        _pop = State(initialValue: openModeMenu ? .mode : (openTarget ? .target : nil))
        self.big = big
        self.defaultMode = defaultMode
        self.lockedSendToTeam = lockedSendToTeam
        self.onSend = onSend
        self.placeholder = big
            ? "Describe the work — a question, a screen to redesign, a change to ship…"
            : "Reply, or start the next turn…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            box
            hint
        }
        .onAppear(perform: seedDefaults)
        .onAppear(perform: consumePendingPrefillIfNeeded)
        .onChange(of: defaultMode) { _, next in mode = next }
        .onChange(of: threads.pendingQuickCaptureText) { _, _ in
            consumePendingPrefillIfNeeded()
        }
        // ⌘1/⌘2/⌘3 (and the palette) request a mode; the on-screen composer
        // applies it via the same path as clicking the mode pill, then clears.
        .onChange(of: commands.requestedMode) { _, requested in
            guard let requested else { return }
            selectMode(requested)
            commands.requestedMode = nil
        }
    }

    /// Bridges the single `pop` selection to the per-trigger `Bool` bindings the
    /// native popover expects. Selecting elsewhere or tapping out flips it off.
    private func popBinding(_ which: Popover) -> Binding<Bool> {
        Binding(get: { pop == which }, set: { pop = $0 ? which : nil })
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onSend != nil
    }

    /// Seed the routing target from the REAL bench/catalog (init can't read the
    /// environment). Prefer a ready model; fall back to the first model.
    private func seedDefaults() {
        let bench = appModel.composeBench
        if to.isEmpty || !bench.contains(where: { $0.id == to }) {
            to = bench.first(where: \.ready)?.id ?? bench.first?.id ?? ""
        }
        if team.isEmpty { team = appModel.composeDefaultTeam(for: lane) }
    }

    /// Adopt a pending quick-capture clipboard value (from global hotkey) into
    /// this composer's editor when the editor is empty. Also focuses it so the
    /// user can immediately edit or send. Safe to call multiple times; only
    /// acts when there is a non-empty pending and local text is blank.
    private func consumePendingPrefillIfNeeded() {
        guard let pending = threads.pendingQuickCaptureText,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        text = pending
        threads.pendingQuickCaptureText = nil
        composerFocused = true
    }

    // MARK: composer box

    private var box: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                        .padding(.horizontal, 14).padding(.top, 8).allowsHitTesting(false)
                }
                ALTextEditor(
                    text: $text,
                    contentHeight: $editorHeight,
                    isFocused: $composerFocused,
                    maxHeight: ComposeEditorMetrics.maxHeight
                )
                .padding(.horizontal, 10).padding(.top, 6)
                .frame(height: editorHeight)
            }
            bar
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var bar: some View {
        HStack(spacing: 9) {
            if !lockedSendToTeam { modePill }
            if mode != .sendToTeam {
                Text("to").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            targetChip
            Spacer(minLength: 8)
            IconButton(systemImage: "photo", accessibilityLabel: "Attach image", small: true) {}
            sendButton
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
    }

    private var modePill: some View {
        Button { pop = (pop == .mode ? nil : .mode) } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.icon).font(.system(size: 13)).foregroundStyle(ALColor.accentText)
                Text(mode.label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 11).frame(height: 31)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .alPopover(isPresented: popBinding(.mode), arrowEdge: .top) { modeMenuPanel }
    }

    private var targetChip: some View {
        Button { pop = (pop == .target ? nil : .target) } label: {
            HStack(spacing: 7) {
                switch mode {
                case .chat, .exec:
                    if let m = appModel.composeBench.first(where: { $0.id == to }) {
                        DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5)
                        Text(m.name).font(ALFont.mono).foregroundStyle(ALColor.textPrimary)
                    }
                case .sendToTeam:
                    Image(systemName: lane.icon).font(.system(size: 12)).foregroundStyle(ALColor.accentText)
                    Text("\(lane.label) team").font(ALFont.mono).foregroundStyle(ALColor.textPrimary)
                }
                Text("· \(effort.label)").font(ALFont.mono).foregroundStyle(ALColor.textMuted)
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 10).frame(height: 31)
            .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .alPopover(isPresented: popBinding(.target), arrowEdge: .top) { targetPopoverPanel }
    }

    private var sendButton: some View {
        Button(action: performSend) {
            Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canSend ? ALColor.textOnLight : ALColor.textFaint)
                .frame(width: 34, height: 34)
                .background(canSend ? ALColor.actionLight : ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.sm))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send — \(mode.label)")
    }

    private func performSend() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        onSend?(ComposeRouting(mode: mode, to: to, effort: effort, lane: lane, team: team, text: body))
        text = ""
        pop = nil
        editorHeight = ComposeEditorMetrics.minHeight
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            Text(mode.desc).font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.leading, 2)
    }

    // MARK: actions

    private func selectMode(_ m: ComposeMode) {
        mode = m
        if m == .exec, !appModel.composeExecutorIds.contains(to) { to = appModel.composeBench.first(where: { appModel.composeExecutorIds.contains($0.id) && $0.ready })?.id ?? to }
        // Picking Fan out drops the user straight into the lane/team picker.
        pop = (m == .sendToTeam) ? .target : nil
    }

    // MARK: popovers

    // MARK: target popover (who + effort)

    private var targetPopoverPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch mode {
            case .chat:
                popHeader("Route to model", "One model answers this turn")
                modelList(appModel.composeBench.map(\.id))
                effortRow(note: "Higher effort = more reasoning time.")
            case .exec:
                popHeader("Hand to executor", "An agent runs it in your repo")
                modelList(appModel.composeBench.filter { appModel.composeExecutorIds.contains($0.id) }.map(\.id))
                effortRow(note: "Higher effort = more reasoning time.")
            case .sendToTeam:
                popHeader("Send to team", "Pick the lane, then the lineup")
                laneTabs
                teamList
                customizeFooter
                effortRow(note: "Higher effort = more reasoning time.")
            }
        }
        .padding(6)
        .frame(width: mode == .sendToTeam ? 320 : 300)
        .background(ALColor.surface)
    }

    private func popHeader(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text(sub).font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 7)
    }

    private func modelList(_ ids: [String]) -> some View {
        VStack(spacing: 1) {
            ForEach(ids, id: \.self) { id in
                if let m = appModel.composeBench.first(where: { $0.id == id }) {
                    Button { if m.ready { to = id; pop = nil } } label: { modelRow(m) }
                        .buttonStyle(.plain)
                        .disabled(!m.ready)
                }
            }
        }
    }

    private func modelRow(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 10) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 27, iconSize: 15, cornerRadius: 7).opacity(m.ready ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m.ready ? ALColor.textPrimary : ALColor.textMuted)
                Text(m.sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 8)
            if m.ready {
                if to == m.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
            } else if let reason = m.notReadyReason {
                Badge(text: reason, tone: .warning)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(to == m.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private var laneTabs: some View {
        HStack(spacing: 6) {
            ForEach(ComposeLane.allCases, id: \.self) { l in
                Button { lane = l; team = appModel.composeDefaultTeam(for: l) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: l.icon).font(.system(size: 12)).foregroundStyle(l == lane ? ALColor.accentText : ALColor.textMuted)
                        Text(l.label).font(.system(size: 12, weight: .medium)).foregroundStyle(l == lane ? ALColor.textPrimary : ALColor.textMuted)
                    }
                    .frame(maxWidth: .infinity).frame(height: 31)
                    .background(l == lane ? ALColor.active : ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
                    .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(l == lane ? ALColor.borderDefault : .clear, lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    private var teamList: some View {
        VStack(spacing: 1) {
            ForEach(appModel.composeTeams(for: lane)) { t in
                Button { team = t.id; pop = nil } label: { teamRow(t) }.buttonStyle(.plain)
            }
        }
    }

    private func teamRow(_ t: ComposeTeam) -> some View {
        HStack(spacing: 10) {
            Image(systemName: lane.icon).font(.system(size: 14)).foregroundStyle(ALColor.accentText)
                .frame(width: 27, height: 27)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    if t.isDefault {
                        Text("default").font(.system(size: 9, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay { RoundedRectangle(cornerRadius: ALRadius.xs).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                    }
                }
                Text(t.summary).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 8)
            if team == t.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(team == t.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private var customizeFooter: some View {
        HStack(spacing: 8) {
            Button {
                // Open Team Studio at this lane's Teams page with the team selected
                // (its editor opens in place — see RootView.customizeTeamRequest).
                pop = nil
                commands.customizeTeamRequest = CustomizeTeamRequest(lane: lane, teamId: team)
            } label: {
                Label("Customize…", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.alGhost)
            .disabled(team.isEmpty)
            Text("Tune this team's workers + skills.").font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func effortRow(note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("EFFORT").font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(ALColor.textFaint)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    ForEach(ComposeEffort.allCases, id: \.self) { e in
                        Button { effort = e } label: {
                            Text(e.label).font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(e == effort ? ALColor.textPrimary : ALColor.textMuted)
                                .frame(width: 44, height: 24)
                                .background(e == effort ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
            Text(note).font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private var modeMenuPanel: some View {
        VStack(spacing: 2) {
            ForEach(ComposeMode.allCases, id: \.self) { m in
                Button { selectMode(m) } label: { modeRow(m) }
                    .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 300)
        .background(ALColor.surface)
    }

    private func modeRow(_ m: ComposeMode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: m.icon).font(.system(size: 15)).foregroundStyle(ALColor.accentText).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    if m == mode { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
                    Spacer(minLength: 8)
                    Text(m.kbd).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.xs))
                        .overlay { RoundedRectangle(cornerRadius: ALRadius.xs).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
                Text(m.desc).font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(m == mode ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }
}
