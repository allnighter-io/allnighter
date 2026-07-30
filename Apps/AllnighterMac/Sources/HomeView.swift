import SwiftUI
import AllnighterCore
import AllnighterEngine

// The clean conversation-workspace home (docs/phases/wiring compose-routing).
// CR4a: real thread rail + send creates/opens conversations; marketing empty
// state stays for a cold bench with no runs yet.

struct HomeView: View {
    @Environment(ThreadsViewModel.self) private var threads
    /// The team run whose full Factory Floor reader is open (over the workspace). Owned by
    /// RootView so a top-bar route command (Inbox/Teams) can dismiss it — the Floor is a
    /// deep surface that must yield to navigation.
    @Binding var floorRun: TeamRun?
    /// Floor next-move handoffs (bug #4): (synthesis, team name). RootView routes + seeds
    /// the next composer's attachment.
    var onAskAnotherTeam: (String, String) -> Void = { _, _ in }
    var onContinueWithAuto: (String, String) -> Void = { _, _ in }
    /// DEBUG-only: open the developer GUI-routes sheet (sidebar footer link).
    var onOpenDevRoutes: () -> Void = {}
    /// R-S08: owned by RootView (mirrors `floorRun`) so a GUI-proof deep-link
    /// (`GUIFixture.opensRelayLaunch`) can force the sheet open deterministically at
    /// launch, without HomeSidebar racing `ProjectsViewModel`'s fixture seeding.
    @Binding var relayLaunchRequest: RelayLaunchRequest?

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(onOpenDevRoutes: onOpenDevRoutes, relayLaunchRequest: $relayLaunchRequest)
                .frame(width: 300)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.openFloor, OpenFloorAction { floorRun = $0 })
        .environment(\.openLoopLaunch, OpenLoopLaunchAction { kickoff, projectId in
            relayLaunchRequest = RelayLaunchRequest(projectId: projectId, kickoffMessage: kickoff)
        })
        .overlay {
            if let floorRun {
                FactoryFloorView(
                    run: floorRun,
                    onBack: { self.floorRun = nil },
                    onAskAnotherTeam: onAskAnotherTeam,
                    onContinueWithAuto: onContinueWithAuto
                )
                .background(ALColor.base)
                .transition(.opacity)
            }
        }
        #if DEBUG
        // GUI Visual Proof Gate: a `.sheet()` is a genuinely separate NSWindow, invisible
        // to the in-process content-view snapshot the proof harness uses (the same class
        // of gotcha as an NSMenu/NSPopover — see RoutingComposer's `composeTargetInline`).
        // Render the SAME view inline, over the workspace, only for this fixture.
        .overlay {
            if GUIFixture.opensRelayLaunch, let request = relayLaunchRequest {
                ALColor.overlay.ignoresSafeArea()
                RelayLaunchView(request: request)
                    .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.xxl))
                    .shadow(radius: 24)
            }
        }
        #endif
    }

    @ViewBuilder
    private var mainPane: some View {
        if threads.selectedThread != nil {
            ThreadView()
        } else if threads.threads.isEmpty {
            HomeMarketingEmptyState()
        } else {
            HomeNewRunPane()
        }
    }
}

// MARK: - Left rail

private struct HomeSidebar: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(ProjectsViewModel.self) private var projects
    @Environment(CommandCenter.self) private var commands
    @Environment(AppModel.self) private var appModel
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var renameThreadId: String?
    @State private var collapsed: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var newChatHover = false
    /// Thread ids with an armed Pending item — drives the neutral pending row dot.
    @State private var armedPendingThreadIds: Set<String> = []
    /// DEBUG-only: opens the developer GUI-routes sheet from the sidebar footer.
    var onOpenDevRoutes: () -> Void = {}
    /// R-S08: the project a "Start relay" tap (or a GUI-proof deep-link) opened the
    /// launch sheet for. Owned by RootView (see `HomeView`'s doc comment).
    @Binding var relayLaunchRequest: RelayLaunchRequest?

    private var sections: (pinned: [ThreadRailRowState], groups: [ThreadsPresenter.ProjectRowGroup]) {
        ThreadsPresenter.projectSections(threads.railRows, projects: projects.projects, search: search)
    }

    private var archivedSearchRows: [ThreadRailRowState] {
        ThreadsPresenter.archivedSearchMatches(threads.railRows, search: search)
    }

    private var archivedBrowseRows: [ThreadRailRowState] {
        ThreadsPresenter.archivedRailRows(threads.railRows, search: search)
    }

    private var isEmptyFloor: Bool {
        projects.projects.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                // Quiet compose row — same calm weight as Search below it, not a loud
                // filled CTA (founder: "10x more muted, like Search").
                Button { threads.newRun() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
                        Text("New chat").font(.system(size: 12.5, weight: .medium)).foregroundStyle(ALColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(newChatHover ? ALColor.hover : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { newChatHover = $0 }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(ALColor.textFaint)
                    TextField("Search conversations", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ALColor.textPrimary)
                        .focused($searchFocused)
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(ALColor.input, in: RoundedRectangle(cornerRadius: ALRadius.md))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.md).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            if threads.showingArchive {
                archiveRail
            } else if isEmptyFloor {
                Spacer(minLength: 0); projectsEmpty; Spacer(minLength: 0)
            } else {
                projectsRail
            }

            if !threads.showingArchive {
                archiveEntry
            }

            #if DEBUG
            devRoutesEntry
            #endif
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
        .onChange(of: commands.focusRenameTick) { _, _ in
            if let id = threads.selectedThreadId { renameThreadId = id }
        }
        .onChange(of: commands.focusSearchTick) { _, _ in searchFocused = true }
        .onAppear(perform: refreshArmedPending)
        .onChange(of: threads.railRows.count) { _, _ in refreshArmedPending() }
        .sheet(item: $relayLaunchRequest) { request in
            RelayLaunchView(request: request)
        }
    }

    #if DEBUG
    /// Developer-only entry at the very bottom of the rail — opens the GUI-routes /
    /// bench-scenarios sheet. The Settings gear now opens real Settings, so this is the
    /// only door to the dev sheet, and it ships only in DEBUG builds.
    @State private var devRoutesHover = false
    private var devRoutesEntry: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            Button(action: onOpenDevRoutes) {
                HStack(spacing: 7) {
                    Image(systemName: "hammer").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                    Text("Developer · GUI routes")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(ALColor.textFaint)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).frame(height: 34)
                .background(devRoutesHover ? ALColor.hover : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { devRoutesHover = $0 }
            .help("DEBUG only — GUI routes & bench scenarios")
        }
    }
    #endif

    // MARK: Projects rail (PRJ-S14)

    private var projectsRail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !sections.pinned.isEmpty {
                    railSectionHeader("Pinned")
                    ForEach(sections.pinned) { row($0, chip: projectName(for: $0)) }
                }
                projectsSectionHeader
                ForEach(sections.groups) { group in
                    ProjectGroupHeader(
                        group: group,
                        collapsed: collapsed.contains(group.id),
                        onToggle: { toggle(group.id) },
                        onNewAgent: { newAgent(in: group.project.id) }
                    )
                    if !collapsed.contains(group.id) {
                        let shown = expanded.contains(group.id) ? group.rows : Array(group.rows.prefix(4))
                        // Indent threads to align under the project name (chevron + folder icon
                        // width), matching how Finder/Cursor/Codex nest items in a folder. The
                        // indent is passed INTO the row so its full width stays tappable.
                        ForEach(shown) { row($0, indent: 16) }
                        if group.rows.count > 4 && !expanded.contains(group.id) {
                            moreRow(group.rows.count - 4, group: group.id)
                        }
                        if group.rows.isEmpty {
                            Text("No conversations").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                                .padding(.horizontal, 28).padding(.vertical, 3)
                        }
                    }
                }
                if !archivedSearchRows.isEmpty {
                    railSectionHeader("Archived")
                    ForEach(archivedSearchRows) { archivedRow($0) }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 12)
        }
    }

    private func row(_ row: ThreadRailRowState, chip: String? = nil, indent: CGFloat = 0) -> some View {
        ProjectThreadRow(
            row: row,
            selected: row.id == threads.selectedThreadId,
            projectChip: chip,
            indent: indent,
            armedPending: armedPendingThreadIds.contains(row.id),
            renaming: renameThreadId == row.id,
            onRename: { renameThreadId = row.id },
            onEndRename: { renameThreadId = nil }
        ) {
            threads.select(threadId: row.id)
        }
    }

    private func archivedRow(_ row: ThreadRailRowState) -> some View {
        ArchivedThreadRow(
            row: row,
            projectName: projectName(for: row),
            selected: row.id == threads.selectedThreadId
        ) {
            threads.select(threadId: row.id)
        }
    }

    /// The project's display name for a pinned row's folder chip.
    private func projectName(for row: ThreadRailRowState) -> String? {
        guard let pid = row.projectId else { return nil }
        return projects.projects.first { $0.id == pid }?.displayName
    }

    /// Read the armed (.pending) items from the Pending store and collect their bound
    /// thread ids — the same `PendingQueueJSON` the CLI projects, no GUI-local truth.
    private func refreshArmedPending() {
        let service = PendingService(store: PendingStore(), models: appModel.models)
        let queue = try? service.queueJSON()
        armedPendingThreadIds = Set(
            (queue?.projects ?? []).flatMap { $0.pending }.compactMap { $0.pendingItem.threadId }
        )
    }

    private var projectsSectionHeader: some View {
        HStack {
            Text("PROJECTS").font(.system(size: 10, weight: .semibold)).tracking(0.9)
                .foregroundStyle(ALColor.textFaint)
            Spacer()
            IconButton(systemImage: "folder.badge.plus", accessibilityLabel: "New project", small: true) {
                projects.addProjectViaPicker()
            }
        }
        .padding(.horizontal, 9).padding(.top, 12).padding(.bottom, 2)
    }

    private func moreRow(_ n: Int, group: String) -> some View {
        // "N more" is just older chats you probably don't care about — it must NOT
        // scream. Neutral/muted, never amber (color is earned; this isn't it).
        Button { expanded.insert(group) } label: {
            Text("\(n) more")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(ALColor.textMuted)
                .padding(.leading, 28).frame(height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func newAgent(in projectId: String) {
        projects.select(projectId)
        threads.currentProjectId = projectId
        threads.newRun()
    }

    private var projectsEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus").font(.system(size: 26)).foregroundStyle(ALColor.textFaint)
            Text("No projects yet")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textSecondary)
            Text("Add a local folder or git repo to start managing work.")
                .font(.system(size: 11.5)).foregroundStyle(ALColor.textFaint)
                .multilineTextAlignment(.center).frame(maxWidth: 200).lineSpacing(2)
            Button { projects.addProjectViaPicker() } label: {
                Label("Add project", systemImage: "plus").font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.alLight)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 14)
    }

    private var archiveRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    threads.showingArchive = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ALColor.textMuted)
                Spacer()
                Text("Archive")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ALColor.textSecondary)
            }
            .padding(.horizontal, 14).padding(.bottom, 8)

            if archivedBrowseRows.isEmpty {
                Spacer(minLength: 0)
                Text("No archived conversations")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.textFaint)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(archivedBrowseRows) { archivedRow($0) }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 12)
                }
            }
        }
    }

    private var archiveEntry: some View {
        Button {
            threads.showingArchive = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                Text("Archive")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !threads.archivedThreads.isEmpty {
                    Text("\(threads.archivedThreads.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                }
            }
            .foregroundStyle(ALColor.textMuted)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(ALColor.borderSubtle).frame(height: 1) }
    }

    private func railSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.6)
            .foregroundStyle(ALColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.top, 10).padding(.bottom, 4)
            .background(ALColor.subtle)
    }

}

// MARK: - Project-grouped rail rows (PRJ-S14)

/// A single-line thread row: unread dot · title · time, with the active amber rail.
/// On hover, the time is replaced by pin + archive actions.
private struct ProjectThreadRow: View {
    @Environment(ThreadsViewModel.self) private var threads
    let row: ThreadRailRowState
    let selected: Bool
    /// For a PINNED row (shown outside its project group): the project's name, rendered as a
    /// folder chip in place of the timestamp so you still know where it lives. nil elsewhere.
    var projectChip: String? = nil
    /// Leading indent for threads nested under a project group (aligns under the folder name).
    /// Applied INSIDE the row's hit area so the indent gutter still selects the thread.
    var indent: CGFloat = 0
    /// True when an armed Pending item targets this thread (neutral dot, not amber).
    var armedPending: Bool = false
    /// Inline-rename is parent-driven (shared SSOT with ⌘R + the context menu), so only one
    /// row edits at a time and the title field tracks the selected thread.
    var renaming: Bool = false
    var onRename: (() -> Void)? = nil
    var onEndRename: (() -> Void)? = nil
    let onTap: () -> Void
    @State private var hovering = false
    @State private var editTitle = ""
    @FocusState private var titleFocused: Bool

    /// The single SSOT row state — precomputed thread facts + the live armed-Pending fact.
    private var state: ThreadDisplayState {
        row.displayState(armedPending: armedPending)
    }

    /// Codex-style compact age: "now" / "5m" / "9h" / "2d" / "3w" / "5mo" / "2y".
    static func compactAge(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "now" }
        let m = Int(s) / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        let d = h / 24
        if d < 7 { return "\(d)d" }
        if d < 30 { return "\(d / 7)w" }
        if d < 365 { return "\(d / 30)mo" }
        return "\(d / 365)y"
    }

    var body: some View {
        Group {
            if renaming {
                // TextField must not live inside a Button — Space would activate the row tap.
                rowContent
            } else {
                Button(action: onTap) { rowContent }
                    .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
        // Double-click anywhere on the row opens the inline editor.
        .simultaneousGesture(TapGesture(count: 2).onEnded { onRename?() })
        .threadRowContextMenu(threadId: row.id, isPinned: row.isPinned, isArchived: row.isArchived,
                              onRename: onRename)
        .onChange(of: renaming) { _, isRenaming in
            if isRenaming {
                editTitle = row.title
                titleFocused = true
            }
        }
        .onChange(of: titleFocused) { _, focused in
            // Click away (lost focus while still in rename mode) commits, like Finder.
            if !focused && renaming { commitRename() }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            stateDot
            if renaming {
                // Double-click to rename (Cursor/Finder behaviour). Commit on Return or blur.
                TextField("Title", text: $editTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ALColor.textPrimary)
                    .focused($titleFocused)
                    .onExitCommand { onEndRename?() }   // Esc cancels
            } else {
                Text(row.title)
                    // Unread (.replied) reads via bright color + the dot — never bold too.
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if renaming {
                EmptyView()
            } else if hovering {
                HStack(spacing: 2) {
                    IconButton(systemImage: row.isPinned ? "pin.slash" : "pin", accessibilityLabel: row.isPinned ? "Unpin" : "Pin", small: true) {
                        threads.togglePin(threadId: row.id)
                    }
                    IconButton(systemImage: "archivebox", accessibilityLabel: "Archive", small: true) {
                        threads.archiveThread(row.id)
                    }
                }
            } else if let projectChip {
                HStack(spacing: 3) {
                    Image(systemName: "folder").font(.system(size: 9)).foregroundStyle(ALColor.textFaint)
                    Text(projectChip).font(.system(size: 10)).foregroundStyle(ALColor.textFaint).lineLimit(1)
                }
            } else {
                Text(Self.compactAge(row.updatedAt))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        // Selection is marked by the shaded background alone — no accent rail (less busy,
        // and no amber line clashing with other-colored status dots).
        .background(selected ? ALColor.active : (hovering ? ALColor.hover : Color.clear),
                    in: RoundedRectangle(cornerRadius: ALRadius.md))
        // Indent the pill, then make the WHOLE width (indent gutter included) the hit area —
        // applying the indent here, inside the Button's contentShape, means clicks in the
        // gutter still select the thread (the bug was indenting the row from outside).
        .padding(.leading, indent)
        .contentShape(Rectangle())
    }

    private func commitRename() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != row.title {
            threads.renameThread(row.id, title: trimmed)
        }
        onEndRename?()
    }

    /// 4-state leading dot. Color is earned: amber ONLY for a replied/unread thread,
    /// blue ONLY for a live run; a draft is a quiet dotted ring (nothing has happened),
    /// pending is a neutral filled dot, idle is empty.
    @ViewBuilder private var stateDot: some View {
        switch state {
        case .draft:
            Circle().strokeBorder(ALColor.textFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 1.6]))
                .frame(width: 7, height: 7)
        case .pending:
            Circle().fill(ALColor.textMuted).frame(width: 7, height: 7)
        case .running:
            Circle().fill(ALPalette.blue500).frame(width: 7, height: 7)
        case .replied:
            Circle().fill(ALColor.accent).frame(width: 7, height: 7)
        case .idle:
            Circle().fill(Color.clear).frame(width: 7, height: 7)
        }
    }

    private var titleColor: Color {
        // A draft stays quiet even when selected — never brightened to look important.
        if state == .draft { return ALColor.textMuted }
        if selected || state == .replied { return ALColor.textPrimary }
        if state == .idle { return ALColor.textMuted }
        return ALColor.textSecondary
    }
}

/// A project section header: chevron · folder · name · aggregate unread / loops roll-up · `+`.
private struct ProjectGroupHeader: View {
    let group: ThreadsPresenter.ProjectRowGroup
    let collapsed: Bool
    let onToggle: () -> Void
    let onNewAgent: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                HStack(spacing: 7) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(ALColor.textFaint).frame(width: 9)
                    Image(systemName: "folder")
                        .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                    Text(group.title)
                        // Folder names are structure, not content — dimmed (not bright white);
                        // hierarchy comes from the weight, not the brightness.
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textMuted).lineLimit(1)
                    // ATL-S05: one project-level "N loops need you" over per-row historical noise.
                    // Zero renders nothing (never "0 loops"). Ordinary unread keeps the amber dot.
                    if let loopsLabel = group.loopsNeedingYouLabel {
                        Text(loopsLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ALColor.accent)
                            .lineLimit(1)
                    } else if group.hasUnread {
                        Circle().fill(ALColor.accent).frame(width: 6, height: 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            if let onNewAgent {
                IconButton(systemImage: "plus", accessibilityLabel: "New agent in project", small: true, action: onNewAgent)
            }
        }
        .padding(.horizontal, 9).padding(.top, 9).padding(.bottom, 3)
    }
}

// MARK: - Archived rail rows

/// Neutral graveyard row: title, then project + age — no status dots, pills, or brand color.
private struct ArchivedThreadRow: View {
    let row: ThreadRailRowState
    let projectName: String?
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(selected ? ALColor.textPrimary : ALColor.textMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let projectName {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                                .foregroundStyle(ALColor.textFaint)
                            Text(projectName)
                                .font(.system(size: 10))
                                .foregroundStyle(ALColor.textFaint)
                                .lineLimit(1)
                        }
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(ALColor.textFaint)
                    }
                    Text(ProjectThreadRow.compactAge(row.updatedAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ALColor.textFaint)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? ALColor.active : (hovering ? ALColor.hover : Color.clear),
                        in: RoundedRectangle(cornerRadius: ALRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .threadRowContextMenu(threadId: row.id, isPinned: row.isPinned, isArchived: true)
    }
}

// MARK: - Marketing empty state ("You already pay for the team")

private struct HomeMarketingEmptyState: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    private var bench: [ComposeBenchModel] { appModel.composeBench }
    private let capabilities: [(icon: String, title: String, blurb: String)] = [
        ("message", "Ask", "Ask the bench a question — “token bucket or sliding window for rate limiting?”"),
        ("rectangle.stack", "Team", "Drop a screenshot — “make this profile feel premium and clean” → a board of options."),
        ("hammer", "Build", "Point an agent at your repo — “add the 429 + Retry-After path to the limiter.”"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AllnighterGlyph(size: 40)
                    .padding(.top, 40)
                Text("You already pay for the team.")
                    .font(.system(size: 26, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(ALColor.textPrimary)
                Text("Allnighter puts the AI tools you already subscribe to on one bench. Ask one, ask them all, or hand the work to an agent — and route any turn to anyone.")
                    .font(.system(size: 13.5)).foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 600)

                benchChips
                modeCards
                RoutingComposer(
                    big: true,
                    showsProject: true,
                    onSend: { threads.sendRouting($0, createThread: true) }
                )
                .padding(.top, 4)
                hint
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.bottom, 40)
        }
        .background(ALColor.base)
    }

    private var benchChips: some View {
        let rows = [Array(bench.prefix(3)), Array(bench.suffix(from: min(3, bench.count)))]
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { m in benchChip(m) }
                }
            }
        }
        .padding(.top, 6)
    }

    private func benchChip(_ m: ComposeBenchModel) -> some View {
        HStack(spacing: 8) {
            DriverBrandGlyph(driverId: m.driverId, boxSize: 18, iconSize: 11, cornerRadius: 5)
            Text(m.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
            Text(m.cli).font(ALFont.monoSm).foregroundStyle(ALColor.textFaint)
            Circle().fill(m.ready ? ALPalette.green500 : ALColor.textFaint).frame(width: 6, height: 6)
        }
        .padding(.horizontal, 11).frame(height: 34)
        .background(ALColor.raised, in: Capsule())
        .overlay { Capsule().strokeBorder(ALColor.borderDefault, lineWidth: 1) }
    }

    private var modeCards: some View {
        HStack(spacing: 12) {
            ForEach(Array(capabilities.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon).font(.system(size: 15)).foregroundStyle(ALColor.accentText)
                        Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ALColor.textPrimary)
                    }
                    Text(item.blurb).font(.system(size: 11.5)).foregroundStyle(ALColor.textMuted)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ALColor.surface, in: RoundedRectangle(cornerRadius: ALRadius.lg))
                .overlay { RoundedRectangle(cornerRadius: ALRadius.lg).strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
            }
        }
        .padding(.top, 4)
    }

    private var hint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
            Text("Runs in your project repo with the selected team and worker.")
                .font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
        }
    }
}

// MARK: - New run (threads exist, none selected) — capacity strip is the launch surface

private struct HomeNewRunPane: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel
    /// Seeded at construction so fixture captures never race live acquire on first paint.
    @State private var capacity = HomeNewRunPane.makeCapacityModel()

    private var notReadyOrParked: Set<String> {
        let parked = appModel.parkedDriverIds
        var down = Set(parked)
        for record in appModel.toolStatuses where !record.status.isSmokeReady {
            down.insert(record.driverId)
            // Capacity source id for Antigravity is `agy`; setup uses `antigravity`.
            if record.driverId == "antigravity" { down.insert("agy") }
        }
        return down
    }

    var body: some View {
        VStack(spacing: 0) {
            CapacityStripView(model: capacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            RoutingComposer(
                big: true,
                showsProject: true,
                onSend: { threads.sendRouting($0, createThread: true) }
            )
            .frame(maxWidth: 640)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .onAppear {
            if !capacity.isFixtureSeeded {
                capacity.loadLive(notReadyOrParked: notReadyOrParked)
            } else {
                capacity.updateNotReadyOrParked(notReadyOrParked.union(GUIFixture.capacityNotReadyOrParked))
            }
        }
        .onChange(of: appModel.toolStatuses.count) { _, _ in
            capacity.updateNotReadyOrParked(notReadyOrParked)
        }
    }

    @MainActor
    private static func makeCapacityModel() -> CapacityStripModel {
        let model = CapacityStripModel()
        #if DEBUG
        if GUIFixture.seedsCapacityStrip {
            model.seedFixture(
                windows: CapacityStripFixtures.mixedWindows(),
                now: CapacityStripFixtures.now,
                notReadyOrParked: GUIFixture.capacityNotReadyOrParked,
                refreshingSource: GUIFixture.capacityRefreshingSource
            )
        }
        #endif
        return model
    }
}
