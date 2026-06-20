import SwiftUI
import AppKit
import AllnighterCore

// Unified routing composer (Unified Run Model). One surface: message + optional
// team + worker + effort. Default send runs the Default Team in the project repo.

enum ComposeEffort: String, CaseIterable { case low, med, high }
enum ComposeLane: String, CaseIterable { case code, design, copy, signal }

/// Everything the composer arms when the user clicks Send.
struct ComposeRouting: Equatable {
    /// `nil` ⇒ the Default Team (`TeamCatalog.defaultRunTeam`).
    var team: String?
    var to: String
    var effort: ComposeEffort
    var lane: ComposeLane
    var text: String
}

/// A bench model as the composer sees it (maps from AppModel).
struct ComposeBenchModel: Identifiable, Equatable {
    let id: String
    let name: String
    let driverId: String
    let cli: String
    let sub: String
    let ready: Bool
    var notReadyReason: String?
}

/// A saved team for a lane (maps from TeamCatalog).
struct ComposeTeam: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let isFavorite: Bool
}

extension ComposeEffort { var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() } }
extension ComposeLane {
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var icon: String { switch self { case .code: "hammer"; case .design: "photo"; case .copy: "doc.text"; case .signal: "antenna.radiowaves.left.and.right" } }
    var workLane: WorkLane { switch self { case .code: .code; case .design: .design; case .copy: .copy; case .signal: .signal } }
}

/// Proof/specimen container — shows the composer on the dark canvas for the GUI
/// proof gate + the dev GUI-routes sheet.
struct ComposeSpecimen: View {
    var openTarget: Bool = false
    /// Proof hook: pre-select a team so the target chip renders in team mode.
    var team: String? = nil
    var body: some View {
        VStack {
            Spacer()
            RoutingComposer(team: team, openTarget: openTarget, showsProject: true)
                .frame(maxWidth: 680)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}

struct RoutingComposer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(ProjectsViewModel.self) private var projects
    @Environment(CommandCenter.self) private var commands
    @State var team: String?
    @State var to: String
    @State var effort: ComposeEffort
    @State var lane: ComposeLane
    @State private var text: String = ""
    @State private var targetOpen = false
    /// Which form the route popover shows — never both at once.
    @State private var targetTab: TargetTab = .team
    enum TargetTab { case team, worker }

    @State private var composerFocused = false
    @State private var editorHeight = ComposeEditorMetrics.minHeight

    let placeholder: String
    private let big: Bool
    /// Lock the team (Send-to-team launcher modal — team already chosen).
    private let locksTeam: Bool
    private let showsProject: Bool
    var onSend: ((ComposeRouting) -> Void)?

    init(
        team: String? = nil,
        lane: ComposeLane = .code,
        openTarget: Bool = false,
        big: Bool = false,
        locksTeam: Bool = false,
        showsProject: Bool = false,
        onSend: ((ComposeRouting) -> Void)? = nil
    ) {
        _team = State(initialValue: team)
        _to = State(initialValue: "")
        _effort = State(initialValue: .med)
        _lane = State(initialValue: lane)
        _targetOpen = State(initialValue: openTarget)
        self.big = big
        self.locksTeam = locksTeam
        self.showsProject = showsProject
        self.onSend = onSend
        self.placeholder = big
            ? "Describe the work — a question, a screen to redesign, a change to ship…"
            : "Reply, or start the next turn…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsProject { projectScope }
            box
        }
        .onAppear(perform: seedDefaults)
        .onAppear(perform: consumePendingPrefillIfNeeded)
        .onChange(of: threads.pendingQuickCaptureText) { _, _ in
            consumePendingPrefillIfNeeded()
        }
        // Picking a different team re-points the worker to THAT team's worker, so
        // the chip never drifts from the team it names.
        .onChange(of: team) { _, newTeam in
            if let w = resolvedWorkerId(forTeam: newTeam) { to = w }
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onSend != nil
    }

    private func seedDefaults() {
        let bench = appModel.composeBench
        // SSOT: the worker shown is the SELECTED team's configured worker (what
        // Settings shows), not an arbitrary first-ready model. Only fall back to a
        // ready bench model if the team pins no worker.
        if to.isEmpty || !bench.contains(where: { $0.id == to }) {
            to = resolvedWorkerId(forTeam: team)
                ?? bench.first(where: \.ready)?.id ?? bench.first?.id ?? ""
        }
        if !locksTeam, team == nil, let preset = TeamCatalog.defaultRunTeam() {
            lane = ComposeLane(rawValue: preset.lane.rawValue) ?? lane
        }
    }

    /// The model a team actually runs — its first worker's pinned model (or the
    /// lead's). This is the SSOT the composer chip must mirror, exactly as the Team
    /// Studio editor shows it. Returns nil only if the team pins nothing.
    private func resolvedWorkerId(forTeam team: String?) -> String? {
        let preset = team.flatMap { TeamCatalog.get($0) } ?? TeamCatalog.defaultRunTeam()
        guard let id = preset?.workerSpecs.first?.preferredModelId ?? preset?.lead.preferredModelId else { return nil }
        // Only honor it if it's actually on the bench (else the chip would show a
        // model the user can't run); otherwise the ready-fallback applies.
        return appModel.composeBench.contains(where: { $0.id == id }) ? id : nil
    }

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
            targetChip
            Spacer(minLength: 8)
            IconButton(systemImage: "photo", accessibilityLabel: "Attach image", small: true) {}
            sendButton
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
    }

    // Scope, not control: the active project · branch floats ABOVE the box as quiet
    // read-only context (reflects what's active — you switch projects in the sidebar,
    // not here). No box, no helper line restating it.
    @ViewBuilder private var projectScope: some View {
        if let active = projects.activeProject {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                Text(active.displayName).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ALColor.textSecondary).lineLimit(1)
                if let branch = active.gitBranch, !branch.isEmpty {
                    Text("·").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
                    Text(branch).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // Two honest modes, never crossed: a single model reads `model · effort`; a team
    // reads its own identity — team glyph + `name · N workers` (or `1 agent`) — and
    // never a fake model · effort that hides the worker count.
    private var targetChip: some View {
        Button { targetOpen.toggle() } label: {
            HStack(spacing: 6) {
                targetChipContent
                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .alPopover(isPresented: $targetOpen, arrowEdge: .top) { targetPopoverPanel }
    }

    @ViewBuilder private var targetChipContent: some View {
        if let id = team, let preset = TeamCatalog.get(id) {
            Image(systemName: "person.2").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            Text(preset.displayName).font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
            Text(teamWorkerLabel(preset)).font(ALFont.mono).foregroundStyle(ALColor.textMuted)
        } else {
            Text(singleModelName).font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
            Text(effort.label).font(ALFont.mono).foregroundStyle(ALColor.textFaint)
        }
    }

    /// The model the single-model route runs (the resolved/picked worker).
    private var singleModelName: String {
        appModel.composeBench.first(where: { $0.id == to })?.name ?? "Auto"
    }

    /// A team's honest size: execution teams are one agent; answer teams show their
    /// worker count.
    private func teamWorkerLabel(_ preset: TeamPreset) -> String {
        if preset.runShape == .execution { return "1 agent" }
        let n = preset.workerSpecs.count
        return "\(n) \(n == 1 ? "worker" : "workers")"
    }

    // Round, small, and deliberately not bright-white — a soft circle, not a loud
    // square. Restraint over theater (founder: "learn from the leader").
    private var sendButton: some View {
        Button(action: performSend) {
            Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSend ? ALColor.textOnLight : ALColor.textFaint)
                .frame(width: 28, height: 28)
                .background(canSend ? ALPalette.ink150 : ALColor.active, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send")
    }

    private func performSend() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        onSend?(ComposeRouting(team: team, to: to, effort: effort, lane: lane, text: body))
        text = ""
        targetOpen = false
        editorHeight = ComposeEditorMetrics.minHeight
    }

    // MARK: target popover

    private var targetPopoverPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if locksTeam {
                // Send-to-team launcher: team is fixed, so just the worker + effort.
                popHeader("Worker", "Override the resolved worker when needed")
                modelList(appModel.composeBench.map(\.id))
            } else {
                targetTabs
                if targetTab == .team {
                    laneTabs
                    defaultTeamRow
                    teamList
                    customizeFooter
                } else {
                    modelList(appModel.composeBench.map(\.id))
                }
            }
            effortRow(note: "Higher effort = more reasoning time.")
        }
        .padding(6)
        .frame(width: locksTeam ? 300 : 320)
        .background(ALColor.surface)
    }

    // One toggle, two forms — Team OR Worker, never both stacked (the old overflow).
    private var targetTabs: some View {
        HStack(spacing: 0) {
            ForEach([TargetTab.team, .worker], id: \.self) { tab in
                Button { targetTab = tab } label: {
                    Text(tab == .team ? "Team" : "Worker")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tab == targetTab ? ALColor.textPrimary : ALColor.textMuted)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(tab == targetTab ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 7)
    }

    private func popHeader(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text(sub).font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 7)
    }

    private var laneTabs: some View {
        HStack(spacing: 6) {
            ForEach(ComposeLane.allCases, id: \.self) { l in
                Button { lane = l } label: {
                    HStack(spacing: 6) {
                        Image(systemName: l.icon).font(.system(size: 12)).foregroundStyle(l == lane ? ALColor.textPrimary : ALColor.textMuted)
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

    // "Auto" is pinned to the very top — the default route, the 95% case.
    private var defaultTeamRow: some View {
        Button { team = nil; targetOpen = false } label: {
            HStack(spacing: 10) {
                Image(systemName: "infinity").font(.system(size: 13)).foregroundStyle(ALColor.textSecondary)
                    .frame(width: 27, height: 27)
                    .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(TeamCatalog.defaultRunTeam()?.displayName ?? "Auto")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    Text("The default route — your go-to agent").font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                }
                Spacer(minLength: 8)
                if team == nil { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(team == nil ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(team == nil ? ALColor.borderDefault : ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    // Favorites featured first, then the rest. The whole list is height-bounded so
    // the popover can't balloon past the screen (the old "both forms" overflow bug).
    private var teamList: some View {
        let teams = appModel.composeTeams(for: lane)
        let favs = teams.filter(\.isFavorite)
        let rest = teams.filter { !$0.isFavorite }
        return ScrollView {
            VStack(spacing: 1) {
                if !favs.isEmpty {
                    teamSectionLabel("FAVORITES")
                    ForEach(favs) { teamButton($0) }
                    if !rest.isEmpty { teamSectionLabel("ALL TEAMS") }
                }
                ForEach(rest) { teamButton($0) }
            }
        }
        .frame(maxHeight: 196)
    }

    private func teamSectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.top, 6).padding(.bottom, 2)
    }

    private func teamButton(_ t: ComposeTeam) -> some View {
        HStack(spacing: 6) {
            Button { team = t.id; targetOpen = false } label: { teamRowBody(t) }.buttonStyle(.plain)
            // Star toggles favorite without selecting the team. Neutral fill — the
            // shape says "favorite", no color needed (color earns its place).
            Button { appModel.toggleFavorite(t.id) } label: {
                Image(systemName: t.isFavorite ? "star.fill" : "star").font(.system(size: 12))
                    .foregroundStyle(t.isFavorite ? ALColor.textSecondary : ALColor.textFaint)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(t.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(team == t.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
    }

    private func teamRowBody(_ t: ComposeTeam) -> some View {
        HStack(spacing: 10) {
            Image(systemName: lane.icon).font(.system(size: 14)).foregroundStyle(ALColor.textMuted)
                .frame(width: 27, height: 27)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                Text(t.summary).font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
            }
            Spacer(minLength: 8)
            if team == t.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var customizeFooter: some View {
        HStack(spacing: 8) {
            Button {
                targetOpen = false
                let teamId = team ?? TeamCatalog.defaultRunTeam()?.id ?? ""
                commands.customizeTeamRequest = CustomizeTeamRequest(lane: lane, teamId: teamId)
            } label: {
                Label("Customize…", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.alGhost)
            Text("Tune this team's workers + skills.").font(.system(size: 10.5)).foregroundStyle(ALColor.textFaint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func modelList(_ ids: [String]) -> some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(ids, id: \.self) { id in
                    if let m = appModel.composeBench.first(where: { $0.id == id }) {
                        Button { if m.ready { to = id; targetOpen = false } } label: { modelRow(m) }
                            .buttonStyle(.plain)
                            .disabled(!m.ready)
                    }
                }
            }
        }
        .frame(maxHeight: 176)
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
                if to == m.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
            } else if let reason = m.notReadyReason {
                Badge(text: reason, tone: .warning)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(to == m.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
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
}
