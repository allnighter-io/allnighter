import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine

// Unified routing composer (Unified Run Model). One surface: message + optional
// team + worker + effort. Default send runs the Default Team in the project repo.
// Types: RoutingComposerTypes.swift; attachment tiles: ComposerAttachmentTile.swift.

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
    @Environment(AppModel.self) var appModel
    @Environment(ThreadsViewModel.self) var threads
    @Environment(ProjectsViewModel.self) var projects
    @Environment(CommandCenter.self) private var commands
    @Environment(\.openLoopLaunch) var openLoopLaunch
    @State var team: String?
    /// An EXPLICIT worker override. `nil` (with no team) = **Auto** — the run resolves
    /// the Default-model tier and substitutes across CLIs.
    @State var pinnedModelId: String?
    @State var effort: ComposeEffort
    @State var lane: ComposeLane
    /// Cached Default-model settings (refreshed on appear) — Auto's tier preview.
    @State var defaultSettings: DefaultModelSettings = .fresh
    @State var text: String = ""
    @State var targetOpen = false
    /// Keyboard/hover navigation in the target popover: which visible row is highlighted.
    @State var targetHighlight = 0
    @State private var effortOpen = false
    /// Hover highlight in the effort popover (nil = show the current selection).
    @State private var effortHighlight: ComposeEffort?
    /// Model-row effort popover — effort for a specific bench seat (nil = closed).
    @State var modelEditModelId: String?
    @State var fileSearchOpen = false
    @State var fileSearchQuery = ""
    /// Project corpus size (cached per @-session) for the "N / total" scope hint.
    @State var fileTotalCount = 0
    /// The project file corpus, scanned ONCE (off-main) per @-session and then ranked
    /// in-memory per keystroke — so typing never blocks on git/stat.
    @State var fileSnapshot: ProjectFileCatalog.Snapshot?
    @State var fileScanRoot: String?
    @State var fileScanning = false
    @State var fileCandidates: [ProjectFileCatalog.Candidate] = []
    @State var highlightedFileIndex = 0
    @State var selectedFileReferences: [ComposeFileReference] = []
    /// Pasted/picked images, frozen to temp files, shown as thumbnail chips and sent
    /// with the run. Thumbnails are cached by id (NSImage isn't part of the Equatable
    /// routing payload).
    @State var attachments: [ComposeAttachment] = []
    @State var attachmentThumbs: [String: NSImage] = [:]
    /// The Floor-handoff context already adopted into this composer (so it's added once).
    @State private var adoptedContextId: UUID?
    /// Which form the route popover shows — never both at once.
    // Model is the default (the 95% case: chat with a model); Team is the deliberate
    // "delegate to a team" choice. "Model" reads clearer than the old "Agent".
    @State var targetTab: TargetTab = .model
    enum TargetTab: Hashable { case model, team, loop }

    @State var composerFocused = false
    @State var editorHeight = ComposeEditorMetrics.minHeight
    /// First-edit latch — fires `onEdit` once (the Pending-review modal un-arms on edit).
    @State private var didEdit = false
    /// Composer team picker search — empty shows Recent + Favorites, non-empty searches
    /// the whole roster (the picker is no longer craft-filtered).
    @State var teamSearch = ""
    /// Snapshot of `composeAllTeams()` taken when the target popover opens — avoids
    /// rebuilding the full roster on every hover/keystroke re-render.
    @State var pickerTeams: [ComposeTeam] = []
    /// Unassigned tier is collapsed by default so edge seats don't dominate browse.
    @State var unassignedSectionCollapsed = true

    let placeholder: String
    private let big: Bool
    /// Lock the team (Send-to-team launcher modal — team already chosen).
    let locksTeam: Bool
    private let showsProject: Bool
    /// Editor grow ceiling before it scrolls internally. Taller in the Pending modal.
    private let editorMaxHeight: CGFloat
    var onSend: ((ComposeRouting) -> Void)?
    /// Fired once on the first user edit (Pending review modal un-arms Pending→Draft).
    var onEdit: (() -> Void)?
    /// Thread-local model to pin when no explicit override — `lastModelId` / default.
    private let continuationModelId: String?

    init(
        team: String? = nil,
        lane: ComposeLane = .code,
        openTarget: Bool = false,
        big: Bool = false,
        locksTeam: Bool = false,
        showsProject: Bool = false,
        initialText: String = "",
        continuationModelId: String? = nil,
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
        _pinnedModelId = State(initialValue: continuationModelId)
        self.big = big
        self.locksTeam = locksTeam
        self.showsProject = showsProject
        self.continuationModelId = continuationModelId
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
        .onAppear(perform: adoptPendingComposerContextIfNeeded)
        .onAppear(perform: updateFileSearchFromText)
        .onAppear {
            #if DEBUG
            if GUIFixture.composeTargetInline { targetTab = .team }
            if GUIFixture.composeLoopTab { targetTab = .loop }
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
        .onChange(of: threads.pendingComposerContext) { _, _ in
            adoptPendingComposerContextIfNeeded()
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
        .onChange(of: team) { _, _ in
            pinnedModelId = nil
            modelEditModelId = nil
            if team == nil { effortOpen = false }
        }
        .onChange(of: targetOpen) { _, open in
            guard open else {
                modelEditModelId = nil
                return
            }
            defaultSettings = DefaultModelSettingsPersistence().load()
            targetHighlight = 0
            refreshPickerTeams()
            unassignedSectionCollapsed = !(pinnedModelId.map { defaultSettings.tiers.isUnassigned($0) } ?? false)
            if targetTab == .model || locksTeam {
                appModel.refreshCapacityCooldowns()
            }
        }
        // ⌘L — focus the composer editor from anywhere (only a real send composer).
        .onChange(of: commands.focusComposerTick) { _, _ in
            if onSend != nil { composerFocused = true }
        }
        // ⌘/ — open the model/team routing picker on the active send composer.
        .onChange(of: commands.openRoutePickerTick) { _, _ in
            if onSend != nil { targetOpen = true }
        }
        .onAppear { adoptContinuationModelIfNeeded() }
        .onChange(of: threads.loopComposerClearTick) { _, _ in
            if targetTab == .loop { text = "" }
        }
    }

    /// Pin the bench model this thread last spoke through so the chip survives turn
    /// settlement, empty→conversation transitions, and thread switches.
    private func adoptContinuationModelIfNeeded() {
        guard !locksTeam, team == nil, let id = continuationModelId,
              appModel.composeBench.contains(where: { $0.id == id }) else { return }
        pinBenchModel(id)
        targetTab = .model
    }

    func pinBenchModel(_ id: String) {
        pinnedModelId = id
        if let raw = ModelCatalog.benchDefaultEffort(for: id)?.rawValue,
           let level = ComposeEffort(rawValue: raw) {
            effort = level
        }
    }


    private func seedDefaults() {
        defaultSettings = DefaultModelSettingsPersistence().load()
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

    /// Adopt a Floor handoff (synthesis) as a visible attachment chip (bug #4). Only a real
    /// send composer adopts; the synthesis is written to a .txt and delivered as context on
    /// send (the next team/Auto starts from the prior result, not from scratch).
    private func adoptPendingComposerContextIfNeeded() {
        guard onSend != nil, let ctx = threads.pendingComposerContext, adoptedContextId != ctx.id else { return }
        adoptedContextId = ctx.id
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-composer-freeze", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("synthesis-\(ctx.id.uuidString).txt")
        guard (try? ctx.text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        attachments.append(ComposeAttachment(id: UUID().uuidString, fileURL: url, displayName: ctx.label, kind: .text))
        composerFocused = true
        threads.pendingComposerContext = nil
    }

    // MARK: composer box

    private var box: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(effectivePlaceholder).font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                        .padding(.horizontal, 14).padding(.top, 8).allowsHitTesting(false)
                }
                ALTextEditor(
                    text: $text,
                    contentHeight: $editorHeight,
                    isFocused: $composerFocused,
                    maxHeight: editorMaxHeight,
                    onCommand: handleEditorCommand,
                    onReturn: handleReturn,
                    onPasteImage: captureImage,
                    onPasteLongText: captureLongText
                )
                .padding(.horizontal, 10).padding(.top, 6)
                .frame(height: editorHeight)
            }
            if !attachments.isEmpty {
                attachmentChips
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

    var selectedFileInputs: [FileReferenceInput] {
        selectedFileReferences.map { FileReferenceInput(path: $0.path) }
    }


    // Cursor-style attachment row: images are bigger thumbnail tiles (no label, hover-X
    // top-right, click to view); a captured .txt keeps a compact doc chip. The attachment is
    // the durable thing; it travels with the run to every worker.
    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(attachments) { att in
                    ComposerAttachmentTile(
                        attachment: att,
                        thumb: attachmentThumbs[att.id],
                        onRemove: { removeAttachment(att) },
                        onOpen: { openAttachment(att) }
                    )
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    /// Freeze a pasted clipboard image to a temp PNG and add a chip. Returns true so the
    /// text view consumes the paste (no beep, no empty insert). `name` is the Finder
    /// filename for a copied image file, else "Pasted image".
    private func captureImage(_ image: NSImage, name: String) -> Bool {
        guard let frozen = ComposerImageFreezer.freeze(image: image) else { return false }
        let displayName = name.isEmpty ? frozen.name : name
        addAttachment(fileURL: frozen.url, displayName: displayName, thumb: frozen.thumb)
        return true
    }

    /// A long paste → capture to a temp .txt and add a chip, keeping the editor clean.
    /// The captured text is delivered to every worker as run context on send.
    private func captureLongText(_ text: String) -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alln-composer-freeze", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("paste-\(UUID().uuidString).txt")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return false }
        let att = ComposeAttachment(
            id: UUID().uuidString, fileURL: url,
            displayName: ComposerPasteContract.chipLabel(charCount: text.count), kind: .text)
        attachments.append(att)
        composerFocused = true
        return true
    }

    /// Paperclip → pick image files. Each is frozen to a temp PNG and added as a chip.
    func pickImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .bmp, .heic, .image]
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let frozen = ComposerImageFreezer.freeze(fileURL: url) else { continue }
            addAttachment(fileURL: frozen.url, displayName: frozen.name, thumb: frozen.thumb)
        }
    }

    private func addAttachment(fileURL: URL, displayName: String, thumb: NSImage?) {
        let att = ComposeAttachment(id: UUID().uuidString, fileURL: fileURL, displayName: displayName, kind: .image)
        attachments.append(att)
        if let thumb { attachmentThumbs[att.id] = thumb }
        composerFocused = true
    }

    private func removeAttachment(_ att: ComposeAttachment) {
        attachments.removeAll { $0.id == att.id }
        attachmentThumbs[att.id] = nil
        try? FileManager.default.removeItem(at: att.fileURL)
    }

    /// Click an attachment to view it — opens the frozen file in the default viewer
    /// (Preview for images, the editor for a captured .txt).
    private func openAttachment(_ att: ComposeAttachment) {
        NSWorkspace.shared.open(att.fileURL)
    }





    // Team runs only — model routes show effort in the target chip + row pill.
    var effortChip: some View {
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
        .alPopover(isPresented: $effortOpen, arrowEdge: .top) {
            effortEditPanel(onDismiss: { effortOpen = false })
        }
    }

    func effortEditPanel(onDismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reasoning effort")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ALColor.textFaint)
                .padding(.horizontal, 4)
            effortPickerRows(onDismiss: onDismiss)
        }
        .padding(6)
        .frame(width: 150)
        .background(ALColor.surface)
        .overlay(effortKeyMonitor(onDismiss: onDismiss).allowsHitTesting(false))
        .onAppear { effortHighlight = nil }
    }

    private func effortPickerRows(onDismiss: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(ComposeEffort.allCases, id: \.self) { e in
                let highlighted = (effortHighlight ?? effort) == e
                Button {
                    effort = e
                    onDismiss()
                } label: {
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
    }

    /// ↑/↓ move through Low/Med/High, ⏎ selects, esc closes — same AppKit key monitor
    /// the target popover uses (SwiftUI key focus doesn't fire inside an NSPopover).
    private func effortKeyMonitor(onDismiss: @escaping () -> Void) -> some View {
        let all = ComposeEffort.allCases
        return PopoverKeyCatcher { action in
            let current = effortHighlight ?? effort
            let idx = all.firstIndex(of: current) ?? 0
            switch action {
            case .up: effortHighlight = all[(idx - 1 + all.count) % all.count]
            case .down: effortHighlight = all[(idx + 1) % all.count]
            case .enter: effort = effortHighlight ?? effort; onDismiss()
            case .escape: onDismiss()
            case .tab: return false
            }
            return true
        }
    }
}
