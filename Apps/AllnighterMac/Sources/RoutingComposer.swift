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
    /// Curated starter team (built-in). Ranks above the plain A–Z tail so the picker is
    /// never blank on cold-start. (Until a real curation flag exists, built-in = featured.)
    var isFeatured: Bool = false
}

private struct ComposeFileReference: Identifiable, Equatable {
    var path: String
    var id: String { path }
}

enum PopoverKeyAction { case up, down, enter, escape }

/// Forwards ↑/↓/⏎/esc inside an NSPopover via a local NSEvent monitor — reliable where
/// SwiftUI `.onKeyPress` doesn't fire, and (unlike a first-responder catcher) it does NOT
/// steal focus, so a search field in the same popover keeps working. The handler returns
/// true to consume the event; other keys pass through (so typing still reaches the field).
struct PopoverKeyCatcher: NSViewRepresentable {
    var handle: (PopoverKeyAction) -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.handle = handle
        context.coordinator.install()
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handle: ((PopoverKeyAction) -> Bool)?
        private var monitor: Any?

        func install() {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let action: PopoverKeyAction?
                switch event.keyCode {
                case 126: action = .up
                case 125: action = .down
                case 36, 76: action = .enter
                case 53: action = .escape
                default: action = nil
                }
                if let action, self.handle?(action) == true { return nil }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }

        deinit { remove() }
    }
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
    /// Keyboard/hover navigation in the target popover: which visible row is highlighted.
    @State private var targetHighlight = 0
    @State private var effortOpen = false
    /// Hover highlight in the effort popover (nil = show the current selection).
    @State private var effortHighlight: ComposeEffort?
    @State private var fileSearchOpen = false
    @State private var fileSearchQuery = ""
    /// Project corpus size (cached per @-session) for the "N / total" scope hint.
    @State private var fileTotalCount = 0
    /// The project file corpus, scanned ONCE (off-main) per @-session and then ranked
    /// in-memory per keystroke — so typing never blocks on git/stat.
    @State private var fileSnapshot: ProjectFileCatalog.Snapshot?
    @State private var fileScanRoot: String?
    @State private var fileCandidates: [ProjectFileCatalog.Candidate] = []
    @State private var highlightedFileIndex = 0
    @State private var selectedFileReferences: [ComposeFileReference] = []
    /// Which form the route popover shows — never both at once.
    // Model is the default (the 95% case: chat with a model); Team is the deliberate
    // "delegate to a team" choice. "Model" reads clearer than the old "Worker".
    @State private var targetTab: TargetTab = .model
    enum TargetTab { case model, team }

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
            // @-file suggestions FLOAT above the composer (autocomplete, not a search
            // box): top row selected, ↑/↓ to move, ⏎ to insert, Esc to dismiss.
            if showsFileSuggestions { fileSuggestions }
            box
        }
        .onAppear(perform: seedDefaults)
        .onAppear(perform: consumePendingPrefillIfNeeded)
        .onAppear(perform: updateFileSearchFromText)
        .onAppear {
            #if DEBUG
            if GUIFixture.composeTargetInline { targetTab = .team }
            // Deterministically open the picker over the seeded fixture root (the @Com
            // text comes from ComposeSpecimen; this fixes the query + candidates so the
            // capture never depends on trigger/project-load timing).
            if GUIFixture.composeFileReferenceOpen {
                fileSearchQuery = "Com"
                fileSearchOpen = true
                refreshFileCandidates()
            }
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
            #if DEBUG
            // Proof: keep the seeded picker populated if the project loads after mount.
            if GUIFixture.composeFileReferenceOpen { refreshFileCandidates(); return }
            #endif
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

    /// Proof-only: force the file-reference panel rendered so its ranking/highlight can
    /// be captured in-process (the panel is inline, but the open-state can race the
    /// fixture's async project load).
    private var fileReferenceFixtureOpen: Bool {
        #if DEBUG
        return GUIFixture.composeFileReferenceOpen
        #else
        return false
        #endif
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

    /// Show the floating suggestions only when there's something to pick — an open @
    /// query with matches. No matches ⇒ nothing floats (no empty box).
    private var showsFileSuggestions: Bool {
        (fileSearchOpen || fileReferenceFixtureOpen) && !fileCandidates.isEmpty
    }

    // A floating autocomplete that sits ABOVE the composer (no search box): a compact
    // list of root-relative paths with matched chars highlighted, the top row selected,
    // ↑/↓ to move, ⏎ to insert, Esc to dismiss — exactly the editor-grade @ pattern.
    private var fileSuggestions: some View {
        VStack(spacing: 0) {
            // Quiet scope count, top-right (e.g. "6 / 1469" of project files).
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(fileSearchQuery.isEmpty ? "\(fileCandidates.count)" : "\(fileCandidates.count) / \(fileTotalCount)")
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 3)
            // Hug the rows (candidates are capped at 12) — no over-expanding scroll area,
            // so the popup stays compact like a real autocomplete.
            VStack(spacing: 1) {
                ForEach(Array(fileCandidates.enumerated()), id: \.element.path) { index, candidate in
                    fileCandidateRow(candidate, index: index)
                }
            }
            .padding(.horizontal, 5).padding(.bottom, 5)
        }
        .background(ALColor.raised, in: RoundedRectangle(cornerRadius: ALRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderDefault, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    // One compact row: a chevron marks the selected row, then the root-relative FULL path
    // with the matched characters highlighted (Grok-Build style), middle-truncated so the
    // basename stays visible. No icon, no card, no preview.
    private func fileCandidateRow(_ candidate: ProjectFileCatalog.Candidate, index: Int) -> some View {
        let active = index == highlightedFileIndex
        return Button { selectFileReference(candidate.path) } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(active ? ALColor.textSecondary : .clear)
                    .frame(width: 10)
                Text(highlightedPath(candidate.path, query: fileSearchQuery))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlightedFileIndex = index } }
    }

    /// Root-relative path with the query's matched characters emphasized — a contiguous
    /// substring when present, else the fuzzy subsequence (mirrors the catalog's match).
    private func highlightedPath(_ path: String, query: String) -> AttributedString {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = Set(Self.matchOffsets(query: q, in: path.lowercased()))
        var result = AttributedString()
        for (i, ch) in path.enumerated() {
            var piece = AttributedString(String(ch))
            if matched.contains(i) {
                piece.foregroundColor = ALColor.accent
                piece.font = .system(size: 12.5, weight: .semibold)
            } else {
                piece.foregroundColor = ALColor.textMuted
                piece.font = .system(size: 12.5)
            }
            result += piece
        }
        return result
    }

    private static func matchOffsets(query q: String, in lowerPath: String) -> [Int] {
        guard !q.isEmpty else { return [] }
        if let r = lowerPath.range(of: q) {
            let start = lowerPath.distance(from: lowerPath.startIndex, to: r.lowerBound)
            return Array(start..<(start + q.count))
        }
        var offsets: [Int] = []
        var qi = q.startIndex
        for (i, ch) in lowerPath.enumerated() where qi < q.endIndex && ch == q[qi] {
            offsets.append(i)
            qi = q.index(after: qi)
        }
        return qi == q.endIndex ? offsets : []
    }

    private var bar: some View {
        HStack(spacing: 9) {
            targetChip
            effortChip
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
            // Pinned model: just the model name. Effort lives in its own chip now — do
            // NOT repeat it here (that produced the "… · Med   Med ⌄" duplicate).
            Text(singleModelName).font(ALFont.mono).foregroundStyle(ALColor.textSecondary).lineLimit(1)
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

    private func activeFileSearchRoot() -> String? {
        #if DEBUG
        if let fxRoot = GUIFixture.fileReferenceFixtureRoot() { return fxRoot }
        #endif
        guard let project = projects.activeProject else { return nil }
        return project.normalizedRootPath.isEmpty ? project.localRootPath : project.normalizedRootPath
    }

    private func refreshFileCandidates() {
        guard let root = activeFileSearchRoot() else { fileCandidates = []; highlightedFileIndex = 0; return }
        // Cached snapshot for this root → rank in-memory, instantly.
        if let snap = fileSnapshot, fileScanRoot == root {
            rankFileCandidates(snap)
            return
        }
        // A scan for this root is already in flight — let it complete and rank.
        if fileScanRoot == root { return }
        // First @ in this session: scan ONCE off the main thread (git subprocesses), then
        // hop back to the main actor to cache + rank. Typing never blocks on this.
        fileScanRoot = root
        Task {
            let snap = await Task.detached(priority: .userInitiated) {
                ProjectFileCatalog().snapshot(rootPath: root)
            }.value
            await MainActor.run {
                guard fileSearchOpen || fileReferenceFixtureOpen, fileScanRoot == root else { return }
                fileSnapshot = snap
                fileTotalCount = snap.paths.count
                rankFileCandidates(snap)
            }
        }
    }

    private func rankFileCandidates(_ snapshot: ProjectFileCatalog.Snapshot) {
        let selectedPaths = Set(selectedFileReferences.map(\.path))
        fileCandidates = ProjectFileCatalog()
            .rank(snapshot, query: fileSearchQuery, limit: 12,
                  recentlyReferenced: selectedFileReferences.map(\.path))
            .filter { !selectedPaths.contains($0.path) }
        highlightedFileIndex = min(highlightedFileIndex, max(fileCandidates.count - 1, 0))
    }

    private func closeFileSearch() {
        fileSearchOpen = false
        fileSearchQuery = ""
        fileCandidates = []
        fileTotalCount = 0
        fileSnapshot = nil
        fileScanRoot = nil
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

    // MARK: target popover

    private var targetPopoverPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if locksTeam {
                // Send-to-team launcher: team is fixed, so just override the model.
                popHeader("Model", "Override the resolved model when needed")
                modelList(appModel.composeBench.map(\.id))
            } else {
                targetTabs
                if targetTab == .model {
                    // Auto = the default model, so it lives at the top of the Model tab.
                    defaultTeamRow
                    modelList(appModel.composeBench.map(\.id))
                } else {
                    // Team tab is just teams now — no Auto row → way cleaner.
                    teamSearchField
                    teamPickerBody
                }
            }
        }
        .padding(6)
        .frame(width: locksTeam ? 300 : 320)
        .background(ALColor.surface)
        // ↑/↓/⏎ are handled by an AppKit key monitor (SwiftUI key focus doesn't fire
        // inside an NSPopover). Hover + the default top-row highlight come from `targetHighlight`.
        .overlay(targetKeyMonitor.allowsHitTesting(false))
        .onAppear { targetHighlight = 0 }
        .onChange(of: targetTab) { _, _ in targetHighlight = 0 }
        .onChange(of: teamSearch) { _, _ in targetHighlight = 0 }
    }

    /// AppKit key catcher — reliably receives ↑/↓/⏎/esc inside the NSPopover (which
    /// SwiftUI's `.onKeyPress` does not). Captures value snapshots each render so the
    /// AppKit callback never reads SwiftUI environment.
    private var targetKeyMonitor: some View {
        let items = targetItems
        let count = items.count
        let bench = appModel.composeBench
        let teams = appModel.composeAllTeams()
        return PopoverKeyCatcher { action in
            switch action {
            case .up:
                if count > 0 { targetHighlight = (targetHighlight - 1 + count) % count }
            case .down:
                if count > 0 { targetHighlight = (targetHighlight + 1) % count }
            case .escape:
                targetOpen = false
            case .enter:
                guard items.indices.contains(targetHighlight) else { return true }
                switch items[targetHighlight] {
                case .auto:
                    team = nil; pinnedWorker = nil; targetOpen = false
                case .model(let id):
                    if bench.first(where: { $0.id == id })?.ready == true {
                        pinnedWorker = id; if !locksTeam { team = nil }; targetOpen = false
                    }
                case .team(let id):
                    if let t = teams.first(where: { $0.id == id }) { selectTeam(t) }
                }
            }
            return true
        }
    }

    // One toggle, two forms — Team OR Worker. Lightened from the boxed segmented control
    // to two quiet text tabs (no outer track/border); the selected one carries a subtle
    // pill. The WHOLE tab is the hit target — `Color.clear` isn't hit-tested, so without
    // an explicit `contentShape` only the glyph was tappable.
    private var targetTabs: some View {
        HStack(spacing: 4) {
            ForEach([TargetTab.model, .team], id: \.self) { tab in
                let selected = tab == targetTab
                Button { targetTab = tab } label: {
                    Text(tab == .team ? "Team" : "Model")
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? ALColor.textPrimary : ALColor.textFaint)
                        .padding(.horizontal, 11).frame(height: 24)
                        .background(selected ? ALColor.active : Color.clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 6)
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

    // Empty query → the full roster, ranked so it's NEVER blank: Favorites → Recent →
    // Featured (built-in starters) → the rest A–Z, deduped, with one quiet divider before
    // the A–Z tail. No per-tier labels (stars + order do the work). Non-empty → matches
    // across the whole roster.
    @ViewBuilder private var teamPickerBody: some View {
        let q = teamSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = appModel.composeAllTeams()
        ScrollView {
            VStack(spacing: 1) {
                if q.isEmpty {
                    let ranked = rankedTeams(all)
                    ForEach(ranked.top) { teamButton($0) }
                    if !ranked.rest.isEmpty {
                        Divider().overlay(ALColor.borderSubtle).padding(.horizontal, 9).padding(.vertical, 5)
                        ForEach(ranked.rest) { teamButton($0) }
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
        .frame(minHeight: 196, maxHeight: 240)
    }

    /// Default ordering: Favorites → Recent → Featured (curated built-ins), then the
    /// remaining teams A–Z. `top` is the ranked cluster, `rest` is the A–Z tail (rendered
    /// below a divider). Deduped — each team appears once, in its highest tier.
    private func rankedTeams(_ all: [ComposeTeam]) -> (top: [ComposeTeam], rest: [ComposeTeam]) {
        let favs = all.filter(\.isFavorite)
        var used = Set(favs.map(\.id))
        let recents = recentTeams(from: all).filter { used.insert($0.id).inserted }
        let featured = all.filter { $0.isFeatured && used.insert($0.id).inserted }
        let rest = all
            .filter { !used.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (favs + recents + featured, rest)
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

    /// Auto = the default model. Selected only in true Auto mode (no team, no pin) — a
    /// pinned model below must not leave Auto looking selected too.
    private var isAutoSelected: Bool { team == nil && pinnedWorker == nil }

    // MARK: target keyboard / hover navigation

    /// One navigable target row.
    enum TargetItem: Equatable { case auto, model(String), team(String) }

    /// The teams shown in the Team tab, in render order (ranked, or search results).
    private var visibleTeams: [ComposeTeam] {
        let all = appModel.composeAllTeams()
        let q = teamSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { let r = rankedTeams(all); return r.top + r.rest }
        return all.filter { matchesTeamQuery($0, q) }
    }

    /// The flat, ordered list of selectable rows for the current tab — the index space
    /// that ↑/↓ and hover move through.
    private var targetItems: [TargetItem] {
        if locksTeam { return appModel.composeBench.map { .model($0.id) } }
        if targetTab == .model { return [.auto] + appModel.composeBench.map { .model($0.id) } }
        return visibleTeams.map { .team($0.id) }
    }

    private var highlightedTargetItem: TargetItem? {
        targetItems.indices.contains(targetHighlight) ? targetItems[targetHighlight] : nil
    }

    private func highlightTarget(_ item: TargetItem) {
        if let i = targetItems.firstIndex(of: item) { targetHighlight = i }
    }


    /// One-line row label: bold name + a quiet parenthetical — `Opus 4.8 (Claude)`,
    /// `Code Core (7 workers)`. Collapses the old two-line name/subtitle rows.
    private func rowLabel(_ name: String, _ detail: String, primary: Bool) -> some View {
        HStack(spacing: 5) {
            Text(name).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primary ? ALColor.textPrimary : ALColor.textMuted)
            Text("(\(detail))").font(.system(size: 12))
                .foregroundStyle(ALColor.textFaint)
        }
        .lineLimit(1)
    }

    // "Auto" is pinned to the very top of the Model tab — the default, the 95% case.
    // One line, like every other row: name + a quiet parenthetical.
    private var defaultTeamRow: some View {
        let highlighted = highlightedTargetItem == .auto
        return Button { team = nil; pinnedWorker = nil; targetOpen = false } label: {
            HStack(spacing: 8) {
                Image(systemName: "infinity").font(.system(size: 11)).foregroundStyle(ALColor.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(ALColor.active, in: RoundedRectangle(cornerRadius: 5))
                rowLabel("Auto", autoModelName ?? "Default model", primary: true)
                Spacer(minLength: 8)
                if isAutoSelected { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(highlighted ? ALColor.borderDefault : ALColor.borderSubtle, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlightTarget(.auto) } }
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
        .background(highlightedTargetItem == .team(t.id) ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .onHover { if $0 { highlightTarget(.team(t.id)) } }
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
        HStack(spacing: 8) {
            Image(systemName: t.lane.icon).font(.system(size: 11)).foregroundStyle(ALColor.textMuted)
                .frame(width: 18, height: 18)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 5))
            rowLabel(t.name, t.summary, primary: true)
            Spacer(minLength: 8)
            if team == t.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        .frame(minHeight: 196, maxHeight: 240)
    }

    private func modelRow(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 8) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5).opacity(m.ready ? 1 : 0.5)
            rowLabel(m.name, m.sub, primary: m.ready)
            Spacer(minLength: 8)
            if m.ready {
                if pinnedWorker == m.id { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
            } else if let reason = m.notReadyReason {
                Badge(text: reason, tone: .warning)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlightedTargetItem == .model(m.id) ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        .contentShape(Rectangle())
        .onHover { if m.ready, $0 { highlightTarget(.model(m.id)) } }
    }

    // Effort is its OWN axis — how hard the model reasons, not who runs — so it lives in
    // a standalone chip beside the target chip, not crammed into the target popover.
    private var effortChip: some View {
        Button { effortOpen.toggle() } label: {
            HStack(spacing: 5) {
                Text(effort.label).font(ALFont.mono).foregroundStyle(ALColor.textSecondary)
                Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(ALColor.textFaint)
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(ALColor.subtle, in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Reasoning effort")
        .alPopover(isPresented: $effortOpen, arrowEdge: .top) { effortPopover }
    }

    private var effortPopover: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ComposeEffort.allCases, id: \.self) { e in
                // Highlight follows hover; with no hover, the current effort is highlighted.
                let highlighted = (effortHighlight ?? effort) == e
                Button { effort = e; effortOpen = false } label: {
                    HStack(spacing: 8) {
                        Text(e.label).font(.system(size: 13, weight: .medium)).foregroundStyle(ALColor.textPrimary)
                        Spacer(minLength: 8)
                        if e == effort { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(ALColor.textSecondary) }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(highlighted ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.sm))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { effortHighlight = e } }
            }
        }
        .padding(6)
        .frame(width: 150)
        .background(ALColor.surface)
        .onAppear { effortHighlight = nil }
    }
}
