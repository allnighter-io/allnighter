import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

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
    var fileReferences: [FileReferenceInput] = []
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
    /// The craft this team belongs to — drives the row icon (the picker no longer
    /// filters by lane, so each row carries its own).
    var lane: ComposeLane = .code
}

private struct ComposeFileReference: Identifiable, Equatable {
    var path: String
    var id: String { path }
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
    /// Proof hook: seed the composer with an active file-reference query.
    var initialText: String = ""
    var body: some View {
        VStack {
            Spacer()
            RoutingComposer(team: team, openTarget: openTarget, showsProject: true, initialText: initialText)
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
    /// An EXPLICIT worker override. `nil` (with no team) = **Auto** — the run resolves
    /// the Default-model tier and substitutes across CLIs.
    @State private var pinnedWorker: String?
    @State var effort: ComposeEffort
    @State var lane: ComposeLane
    /// Cached Default-model settings (refreshed on appear) — Auto's tier preview.
    @State private var defaultSettings: DefaultModelSettings = .fresh
    @State private var text: String = ""
    @State private var targetOpen = false
    @State private var fileSearchOpen = false
    @State private var fileSearchQuery = ""
    @State private var fileCandidates: [ProjectFileCatalog.Candidate] = []
    @State private var highlightedFileIndex = 0
    @State private var selectedFileReferences: [ComposeFileReference] = []
    /// Which form the route popover shows — never both at once.
    @State private var targetTab: TargetTab = .team
    enum TargetTab { case team, worker }

    @State private var composerFocused = false
    @State private var editorHeight = ComposeEditorMetrics.minHeight
    /// First-edit latch — fires `onEdit` once (the Pending-review modal un-arms on edit).
    @State private var didEdit = false
    /// Composer team picker search — empty shows Recent + Favorites, non-empty searches
    /// the whole roster (the picker is no longer craft-filtered).
    @State private var teamSearch = ""

    let placeholder: String
    private let big: Bool
    /// Lock the team (Send-to-team launcher modal — team already chosen).
    private let locksTeam: Bool
    private let showsProject: Bool
    /// Editor grow ceiling before it scrolls internally. Taller in the Pending modal.
    private let editorMaxHeight: CGFloat
    var onSend: ((ComposeRouting) -> Void)?
    /// Fired once on the first user edit (Pending review modal un-arms Pending→Draft).
    var onEdit: (() -> Void)?

    init(
        team: String? = nil,
        lane: ComposeLane = .code,
        openTarget: Bool = false,
        big: Bool = false,
        locksTeam: Bool = false,
        showsProject: Bool = false,
        initialText: String = "",
        editorMaxHeight: CGFloat = ComposeEditorMetrics.maxHeight,
        onSend: ((ComposeRouting) -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        _team = State(initialValue: team)
        _effort = State(initialValue: .med)
        _lane = State(initialValue: lane)
        _targetOpen = State(initialValue: openTarget)
        _text = State(initialValue: initialText)
        _composerFocused = State(initialValue: !initialText.isEmpty)
        self.big = big
        self.locksTeam = locksTeam
        self.showsProject = showsProject
        self.editorMaxHeight = editorMaxHeight
        self.onSend = onSend
        self.onEdit = onEdit
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
        .onAppear(perform: updateFileSearchFromText)
        .onAppear {
            #if DEBUG
            if GUIFixture.composeTargetInline, teamSearch.isEmpty { teamSearch = "bug" }
            #endif
        }
        .onChange(of: threads.pendingQuickCaptureText) { _, _ in
            consumePendingPrefillIfNeeded()
        }
        .onChange(of: text) { _, _ in
            updateFileSearchFromText()
            if !didEdit { didEdit = true; onEdit?() }
        }
        .onChange(of: projects.activeProjectId) { _, _ in
            closeFileSearch()
        }
        // Switching teams drops any explicit worker pin so the chip names THAT team's
        // worker, never a stale override.
        .onChange(of: team) { _, _ in pinnedWorker = nil }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onSend != nil
    }

    private func seedDefaults() {
        defaultSettings = DefaultModelSettingsPersistence().load()
        if !locksTeam, team == nil, let preset = TeamCatalog.defaultRunTeam() {
            lane = ComposeLane(rawValue: preset.lane.rawValue) ?? lane
        }
    }

    // MARK: Auto resolution (the chip preview == what the run will do)

    /// Model ids runnable right now — reuse AppModel's canonical availability (ON-bench
    /// AND source ready), the same gate the run path applies, so the Auto chip never
    /// previews a model the run would skip (e.g. an off-bench model whose CLI is up).
    private var sourceReadyIds: Set<ModelID> { Set(appModel.availableModels.map(\.id)) }

    /// What Auto resolves to now — the tier default, or a same-tier substitute when a
    /// CLI is down. nil = the tier is fully down (Auto would wait).
    private var autoModelId: String? {
        SubstitutionResolver.resolveAuto(settings: defaultSettings, readyModelIds: sourceReadyIds).resolvedModelId
    }

    /// The worker the route currently runs: an explicit pin, else the team's worker,
    /// else the tier-resolved Auto model.
    private var selectedWorkerId: String? {
        if let pinnedWorker { return pinnedWorker }
        if team != nil { return resolvedWorkerId(forTeam: team) }
        return autoModelId
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
                    maxHeight: editorMaxHeight,
                    onCommand: handleEditorCommand
                )
                .padding(.horizontal, 10).padding(.top, 6)
                .frame(height: editorHeight)
            }
            if !selectedFileReferences.isEmpty {
                fileReferenceChips
            }
            if fileSearchOpen {
                fileReferencePanel
            }
            bar
            #if DEBUG
            // Proof-only: the team picker is a native NSPopover (uncapturable in-process),
            // so render the redesigned panel inline for the GUI proof.
            if GUIFixture.composeTargetInline {
                Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
                targetPopoverPanel
            }
            #endif
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var selectedFileInputs: [FileReferenceInput] {
        selectedFileReferences.map { FileReferenceInput(path: $0.path) }
    }

    private var fileReferenceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedFileReferences) { ref in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(ALColor.textMuted)
                        Text(ref.path)
                            .font(ALFont.monoSm)
                            .foregroundStyle(ALColor.textSecondary)
                            .lineLimit(1)
                        Button { removeFileReference(ref.path) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ALColor.textFaint)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(ALColor.subtle, in: Capsule())
                    .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 5)
            .padding(.bottom, 1)
        }
    }

    private var fileReferencePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(ALColor.textFaint)
                Text("Search Project files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALColor.textSecondary)
                if !fileSearchQuery.isEmpty {
                    Text("·")
                        .font(ALFont.monoSm)
                        .foregroundStyle(ALColor.textFaint)
                    Text(fileSearchQuery)
                        .font(ALFont.monoSm)
                        .foregroundStyle(ALColor.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)

            if fileCandidates.isEmpty {
                Text(projects.activeProject == nil ? "No Project selected" : "No matching files")
                    .font(.system(size: 12))
                    .foregroundStyle(ALColor.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(fileCandidates.enumerated()), id: \.element.path) { index, candidate in
                            fileCandidateRow(candidate, index: index)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 184)
            }
        }
        .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .padding(.horizontal, 11)
        .padding(.top, 5)
    }

    private func fileCandidateRow(_ candidate: ProjectFileCatalog.Candidate, index: Int) -> some View {
        let active = index == highlightedFileIndex
        let basename = URL(fileURLWithPath: candidate.path).lastPathComponent
        let directory = parentPath(candidate.path)
        return Button { selectFileReference(candidate.path) } label: {
            HStack(spacing: 9) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(active ? ALColor.textSecondary : ALColor.textMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(basename)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ALColor.textPrimary)
                        .lineLimit(1)
                    if !directory.isEmpty {
                        Text(directory)
                            .font(ALFont.monoSm)
                            .foregroundStyle(ALColor.textFaint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if active {
                    Image(systemName: "return")
                        .font(.system(size: 10))
                        .foregroundStyle(ALColor.textFaint)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlightedFileIndex = index } }
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
        } else if pinnedWorker == nil {
            // Auto: name the mode AND the model it resolves to, so the user can tell
            // they're in Auto and not pinned to that model (founder: "Auto · <model>").
            Image(systemName: "infinity").font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
            Text("Auto").font(ALFont.mono).foregroundStyle(ALColor.textSecondary)
            if let name = autoModelName {
                Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
                Text(name).font(ALFont.mono).foregroundStyle(ALColor.textMuted).lineLimit(1)
            }
        } else {
            Text(singleModelName).font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
            Text("·").font(ALFont.mono).foregroundStyle(ALColor.textFaint)
            Text(effort.label).font(ALFont.mono).foregroundStyle(ALColor.textFaint)
        }
    }

    /// The model the single-model route runs — the tier-resolved Auto model, or an
    /// explicit pin. Equals what the run will actually execute.
    private var singleModelName: String {
        appModel.composeBench.first(where: { $0.id == selectedWorkerId })?.name ?? "Auto"
    }

    /// The model name Auto resolves to right now (nil when the tier is fully down and
    /// Auto would wait — the chip then reads just "Auto").
    private var autoModelName: String? {
        guard let id = autoModelId else { return nil }
        return appModel.composeBench.first { $0.id == id }?.name
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
        // Auto (no team, no pin) sends an EMPTY worker so the run resolves the tier
        // default and substitutes across CLIs. A team or an explicit pin sends a
        // concrete worker (exact, no substitution).
        let toSend: String
        if team != nil {
            toSend = (pinnedWorker ?? resolvedWorkerId(forTeam: team)) ?? ""
        } else {
            toSend = pinnedWorker ?? ""
        }
        onSend?(ComposeRouting(
            team: team,
            to: toSend,
            effort: effort,
            lane: lane,
            text: body,
            fileReferences: selectedFileInputs
        ))
        text = ""
        selectedFileReferences = []
        closeFileSearch()
        targetOpen = false
        editorHeight = ComposeEditorMetrics.minHeight
    }

    private func handleEditorCommand(_ command: ALTextEditorCommand) -> Bool {
        guard fileSearchOpen else { return false }
        switch command {
        case .returnKey:
            guard fileCandidates.indices.contains(highlightedFileIndex) else { return false }
            selectFileReference(fileCandidates[highlightedFileIndex].path)
            return true
        case .escape:
            closeFileSearch()
            return true
        case .moveUp:
            moveFileHighlight(-1)
            return true
        case .moveDown:
            moveFileHighlight(1)
            return true
        }
    }

    private func moveFileHighlight(_ delta: Int) {
        guard !fileCandidates.isEmpty else { return }
        highlightedFileIndex = (highlightedFileIndex + delta + fileCandidates.count) % fileCandidates.count
    }

    private func updateFileSearchFromText() {
        guard let trigger = activeFileTrigger(in: text) else {
            closeFileSearch()
            return
        }
        if selectedFileReferences.contains(where: { $0.path == trigger.query }) {
            closeFileSearch()
            return
        }
        fileSearchQuery = trigger.query
        fileSearchOpen = true
        refreshFileCandidates()
    }

    private func refreshFileCandidates() {
        guard let project = projects.activeProject else {
            fileCandidates = []
            highlightedFileIndex = 0
            return
        }
        let selectedPaths = Set(selectedFileReferences.map(\.path))
        let root = project.normalizedRootPath.isEmpty ? project.localRootPath : project.normalizedRootPath
        fileCandidates = ProjectFileCatalog().candidates(
            rootPath: root,
            query: fileSearchQuery,
            limit: 12,
            recentlyReferenced: selectedFileReferences.map(\.path)
        )
        .filter { !selectedPaths.contains($0.path) }
        highlightedFileIndex = min(highlightedFileIndex, max(fileCandidates.count - 1, 0))
    }

    private func closeFileSearch() {
        fileSearchOpen = false
        fileSearchQuery = ""
        fileCandidates = []
        highlightedFileIndex = 0
    }

    private func selectFileReference(_ path: String) {
        if !selectedFileReferences.contains(where: { $0.path == path }) {
            selectedFileReferences.append(ComposeFileReference(path: path))
        }
        if let range = activeFileTrigger(in: text)?.range {
            text.replaceSubrange(range, with: "@\(path)")
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "@\(path)"
        } else {
            text += " @\(path)"
        }
        closeFileSearch()
        composerFocused = true
    }

    private func removeFileReference(_ path: String) {
        selectedFileReferences.removeAll { $0.path == path }
        text = text.replacingOccurrences(of: "@\(path)", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        updateFileSearchFromText()
    }

    private func activeFileTrigger(in value: String) -> (range: Range<String.Index>, query: String)? {
        var start = value.endIndex
        while start > value.startIndex {
            let previous = value.index(before: start)
            if value[previous].isWhitespace { break }
            start = previous
        }
        let token = value[start..<value.endIndex]
        guard token.first == "@", !token.dropFirst().contains("@") else { return nil }
        return (start..<value.endIndex, String(token.dropFirst()))
    }

    private func parentPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/")
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
                    defaultTeamRow
                    teamSearchField
                    teamPickerBody
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

    // Search field sits directly under Auto — answering both modes instantly: "I know
    // what I want" (type) and "show me my bench" (Recent + Favorites below).
    private var teamSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            TextField("Search teams…", text: $teamSearch)
                .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(ALColor.textPrimary)
            if !teamSearch.isEmpty {
                Button { teamSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 2)
    }

    // Empty query → Recent (max 3) + Favorites. Non-empty → matches across the whole
    // roster. Non-favorites stay hidden until searched (favorites are the default surface).
    @ViewBuilder private var teamPickerBody: some View {
        let q = teamSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = appModel.composeAllTeams()
        ScrollView {
            VStack(spacing: 1) {
                if q.isEmpty {
                    let recents = recentTeams(from: all)
                    let recentIds = Set(recents.map(\.id))
                    if !recents.isEmpty {
                        teamSectionLabel("RECENT")
                        ForEach(recents) { teamButton($0) }
                    }
                    teamSectionLabel("FAVORITES")
                    let favs = all.filter { $0.isFavorite && !recentIds.contains($0.id) }
                    if favs.isEmpty {
                        teamPickerEmpty("No favorites yet — star a team to pin it here.")
                    } else {
                        ForEach(favs) { teamButton($0) }
                    }
                } else {
                    let results = all.filter { matchesTeamQuery($0, q) }
                    if results.isEmpty {
                        teamPickerEmpty("No teams found")
                    } else {
                        ForEach(results) { teamButton($0) }
                    }
                }
            }
        }
        .frame(maxHeight: 208)
    }

    private func teamPickerEmpty(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 8)
    }

    private func recentTeams(from all: [ComposeTeam]) -> [ComposeTeam] {
        appModel.recentTeamIds.compactMap { id in all.first { $0.id == id } }
    }

    /// Match name, craft, summary, and the team's resolved worker/model — no special
    /// boosts for any vocabulary; it ranks only because the user typed it.
    private func matchesTeamQuery(_ t: ComposeTeam, _ q: String) -> Bool {
        if t.name.lowercased().contains(q) { return true }
        if t.summary.lowercased().contains(q) { return true }
        if t.lane.label.lowercased().contains(q) { return true }
        if let worker = resolvedWorkerId(forTeam: t.id),
           let m = appModel.composeBench.first(where: { $0.id == worker }) {
            if m.name.lowercased().contains(q) || m.cli.lowercased().contains(q) { return true }
        }
        return false
    }

    // "Auto" is pinned to the very top — the default route, the 95% case.
    private var defaultTeamRow: some View {
        Button { team = nil; pinnedWorker = nil; targetOpen = false } label: {
            HStack(spacing: 10) {
                Image(systemName: "infinity").font(.system(size: 13)).foregroundStyle(ALColor.textSecondary)
                    .frame(width: 27, height: 27)
                    .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    Text("Default model").font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
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

    private func teamSectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.top, 6).padding(.bottom, 2)
    }

    private func teamButton(_ t: ComposeTeam) -> some View {
        HStack(spacing: 6) {
            Button { selectTeam(t) } label: { teamRowBody(t) }.buttonStyle(.plain)
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

    /// Select a team: pin it, sync the lane to its craft (no lane tabs anymore), and
    /// record it for the Recent section.
    private func selectTeam(_ t: ComposeTeam) {
        team = t.id
        lane = t.lane
        appModel.noteRecentTeam(t.id)
        targetOpen = false
    }

    private func teamRowBody(_ t: ComposeTeam) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.lane.icon).font(.system(size: 14)).foregroundStyle(ALColor.textMuted)
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
                        Button {
                            if m.ready { pinnedWorker = id; if !locksTeam { team = nil }; targetOpen = false }
                        } label: { modelRow(m) }
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
                if selectedWorkerId == m.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
            } else if let reason = m.notReadyReason {
                Badge(text: reason, tone: .warning)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedWorkerId == m.id ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
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
