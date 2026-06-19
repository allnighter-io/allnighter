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
    let isDefault: Bool
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
    var body: some View {
        VStack {
            Spacer()
            RoutingComposer(openTarget: openTarget)
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
        VStack(alignment: .leading, spacing: 6) {
            box
            hint
        }
        .onAppear(perform: seedDefaults)
        .onAppear(perform: consumePendingPrefillIfNeeded)
        .onChange(of: threads.pendingQuickCaptureText) { _, _ in
            consumePendingPrefillIfNeeded()
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onSend != nil
    }

    private func seedDefaults() {
        let bench = appModel.composeBench
        if to.isEmpty || !bench.contains(where: { $0.id == to }) {
            to = bench.first(where: \.ready)?.id ?? bench.first?.id ?? ""
        }
        if !locksTeam, team == nil, let preset = TeamCatalog.defaultRunTeam() {
            lane = ComposeLane(rawValue: preset.lane.rawValue) ?? lane
        }
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
            if showsProject { projectChip }
            Text("with").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            targetChip
            Spacer(minLength: 8)
            IconButton(systemImage: "photo", accessibilityLabel: "Attach image", small: true) {}
            sendButton
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
    }

    private var projectChip: some View {
        let active = projects.activeProject
        return Button { cycleProject() } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11))
                    .foregroundStyle(active != nil ? ALColor.accentText : ALColor.textFaint)
                Text(active?.displayName ?? "No project")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active != nil ? ALColor.textPrimary : ALColor.textFaint).lineLimit(1)
                if let branch = active?.gitBranch, !branch.isEmpty {
                    Text("· \(branch)").font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
                }
            }
            .padding(.horizontal, 10).frame(height: 31)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        }
        .buttonStyle(.plain).fixedSize()
    }

    private func cycleProject() {
        let all = projects.projects
        guard !all.isEmpty else { projects.addProjectViaPicker(); return }
        let idx = all.firstIndex { $0.id == projects.activeProjectId } ?? -1
        projects.select(all[(idx + 1) % all.count].id)
    }

    private var targetChip: some View {
        Button { targetOpen.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: lane.icon).font(.system(size: 12)).foregroundStyle(ALColor.accentText)
                Text(teamDisplayName).font(ALFont.mono).foregroundStyle(ALColor.textPrimary).lineLimit(1)
                if let m = appModel.composeBench.first(where: { $0.id == to }) {
                    Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
                    DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5)
                    Text(m.name).font(ALFont.mono).foregroundStyle(ALColor.textPrimary)
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
        .alPopover(isPresented: $targetOpen, arrowEdge: .top) { targetPopoverPanel }
    }

    private var teamDisplayName: String {
        if let id = team, let preset = TeamCatalog.get(id) { return preset.displayName }
        return TeamCatalog.defaultRunTeam()?.displayName ?? "Default team"
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

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            Text("Runs in your project repo with the selected team and worker.")
                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
        .padding(.leading, 2)
    }

    // MARK: target popover

    private var targetPopoverPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            popHeader("Route this turn", "Team + worker run in the project repo")
            if !locksTeam {
                laneTabs
                defaultTeamRow
                teamList
                customizeFooter
            }
            popHeader("Worker", "Override the resolved worker when needed")
            modelList(appModel.composeBench.map(\.id))
            effortRow(note: "Higher effort = more reasoning time.")
        }
        .padding(6)
        .frame(width: locksTeam ? 300 : 320)
        .background(ALColor.surface)
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

    private var defaultTeamRow: some View {
        Button { team = nil; targetOpen = false } label: {
            HStack(spacing: 10) {
                Image(systemName: "star").font(.system(size: 14)).foregroundStyle(ALColor.accentText)
                    .frame(width: 27, height: 27)
                    .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(TeamCatalog.defaultRunTeam()?.displayName ?? "Default team")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    Text("Your go-to worker — chat or build").font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                }
                Spacer(minLength: 8)
                if team == nil { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.accentText) }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(team == nil ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        }
        .buttonStyle(.plain)
    }

    private var teamList: some View {
        VStack(spacing: 1) {
            ForEach(appModel.composeTeams(for: lane)) { t in
                Button { team = t.id; targetOpen = false } label: { teamRow(t) }.buttonStyle(.plain)
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
