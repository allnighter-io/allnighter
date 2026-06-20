import SwiftUI
import AllnighterCore
import AllnighterEngine

// The clean conversation-workspace home (docs/phases/wiring compose-routing).
// CR4a: real thread rail + send creates/opens conversations; marketing empty
// state stays for a cold bench with no runs yet.

struct HomeView: View {
    @Environment(ThreadsViewModel.self) private var threads

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar()
                .frame(width: 300)
            Rectangle().fill(ALColor.borderSubtle).frame(width: 1)
            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    private var sections: (pinned: [WorkThread], groups: [ThreadsPresenter.ProjectGroup]) {
        ThreadsPresenter.projectSections(threads.threads, projects: projects.projects, search: search)
    }

    private var archivedSections: [ThreadsPresenter.TriageSection] {
        let archived = ThreadsPresenter.triagedArchived(threads.threads)
        let filtered = archived.filter { ThreadsPresenter.matchesSearch($0, query: search) }
        guard !filtered.isEmpty else { return [] }
        return [ThreadsPresenter.TriageSection(id: "archive", title: "Archived", threads: filtered)]
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
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ALColor.subtle)
        .onChange(of: commands.focusRenameTick) { _, _ in
            if let id = threads.selectedThreadId { renameThreadId = id }
        }
        .onChange(of: commands.focusSearchTick) { _, _ in searchFocused = true }
        .onAppear(perform: refreshArmedPending)
        .onChange(of: threads.threads.count) { _, _ in refreshArmedPending() }
    }

    // MARK: Projects rail (PRJ-S14)

    private var projectsRail: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !sections.pinned.isEmpty {
                    railSectionHeader("Pinned")
                    ForEach(sections.pinned) { row($0) }
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
                        let shown = expanded.contains(group.id) ? group.threads : Array(group.threads.prefix(4))
                        ForEach(shown) { row($0) }
                        if group.threads.count > 4 && !expanded.contains(group.id) {
                            moreRow(group.threads.count - 4, group: group.id)
                        }
                        if group.threads.isEmpty {
                            Text("No conversations").font(.system(size: 11)).foregroundStyle(ALColor.textFaint)
                                .padding(.horizontal, 28).padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 12)
        }
    }

    private func row(_ thread: WorkThread) -> some View {
        ProjectThreadRow(
            thread: thread,
            selected: thread.id == threads.selectedThreadId,
            armedPending: armedPendingThreadIds.contains(thread.id)
        ) {
            threads.select(thread)
        }
    }

    /// Read the armed (.pending) items from the Pending store and collect their bound
    /// thread ids — the same `PendingQueueJSON` the CLI/MCP project, no GUI-local truth.
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

            if archivedSections.isEmpty {
                Spacer(minLength: 0)
                Text("No archived conversations")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ALColor.textFaint)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(archivedSections) { section in
                            ForEach(section.threads) { thread in
                                ConversationRow(
                                    thread: thread,
                                    selected: thread.id == threads.selectedThreadId,
                                    renaming: renameThreadId == thread.id,
                                    onEndRename: { renameThreadId = nil },
                                    onRename: { renameThreadId = thread.id },
                                    inArchiveView: true
                                ) {
                                    threads.select(thread)
                                }
                            }
                        }
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
    let thread: WorkThread
    let selected: Bool
    /// True when an armed Pending item targets this thread (neutral dot, not amber).
    var armedPending: Bool = false
    let onTap: () -> Void
    @State private var hovering = false

    /// The single SSOT row state (shared with CLI/MCP via `ThreadStateDerivation`).
    private var state: ThreadDisplayState {
        ThreadStateDerivation.displayState(thread: thread, hasPendingItem: armedPending)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                stateDot
                Text(thread.title)
                    .font(.system(size: 13, weight: state == .replied ? .semibold : .regular))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering {
                    HStack(spacing: 2) {
                        IconButton(systemImage: thread.isPinned ? "pin.slash" : "pin", accessibilityLabel: thread.isPinned ? "Unpin" : "Pin", small: true) {
                            threads.togglePin(for: thread)
                        }
                        IconButton(systemImage: "archivebox", accessibilityLabel: "Archive", small: true) {
                            threads.archiveThread(thread.id)
                        }
                    }
                } else {
                    Text(thread.updatedAt, format: .relative(presentation: .numeric))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(ALColor.textFaint)
                }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(selected ? ALColor.active : (hovering ? ALColor.hover : Color.clear),
                        in: RoundedRectangle(cornerRadius: ALRadius.md))
            .overlay(alignment: .leading) {
                // A draft is "nothing of importance yet" — it must stay subtle even when
                // selected: the quiet active background marks it, never an amber rail.
                if selected && state != .draft {
                    RoundedRectangle(cornerRadius: 1.5).fill(ALColor.accent).frame(width: 2.5).padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .threadRowContextMenu(thread: thread)
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

/// A project section header: chevron · folder · name · aggregate unread dot · `+`.
private struct ProjectGroupHeader: View {
    let group: ThreadsPresenter.ProjectGroup
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
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ALColor.textSecondary).lineLimit(1)
                    if group.hasUnread {
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

private struct ConversationRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread
    let selected: Bool
    var renaming: Bool = false
    var onEndRename: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var inArchiveView: Bool = false
    let onTap: () -> Void
    @State private var editTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                rowGlyph
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if renaming {
                            TextField("Title", text: $editTitle, onCommit: commitRename)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .semibold))
                                .focused($titleFocused)
                                .onAppear {
                                    editTitle = thread.title
                                    titleFocused = true
                                }
                        } else {
                            Text(thread.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ALColor.textPrimary)
                                .lineLimit(1)
                        }
                        ThreadRailComponents.PinMarker(pinned: thread.isPinned)
                    }
                    HStack(spacing: 6) {
                        if let status = ThreadsPresenter.conversationStatus(for: thread) {
                            ConversationStatusPill(status: status)
                        }
                        Text(thread.updatedAt, format: .relative(presentation: .numeric))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ALColor.textFaint)
                    }
                }
                Spacer(minLength: 0)
                ThreadRailComponents.UnreadLight(thread: thread)
                    .frame(width: 10)
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ALColor.active : Color.clear, in: RoundedRectangle(cornerRadius: ALRadius.md))
        }
        .buttonStyle(.plain)
        .threadRowContextMenu(thread: thread, inArchiveView: inArchiveView, onRename: onRename)
        .onChange(of: renaming) { _, isRenaming in
            if isRenaming {
                editTitle = thread.title
                titleFocused = true
            }
        }
    }

    private func commitRename() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threads.renameThread(thread.id, title: trimmed)
        onEndRename?()
    }

    @ViewBuilder
    private var rowGlyph: some View {
        let workerId = thread.lastWorkerId ?? thread.defaultWorkerId
        if let workerId, let model = appModel.models.first(where: { $0.id == workerId }) {
            DriverBrandGlyph(driverId: model.driverId, boxSize: 28, iconSize: 14, cornerRadius: 7)
        } else {
            AllnighterGlyph(size: 15)
                .frame(width: 28, height: 28)
                .background(ALColor.active, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct ConversationStatusPill: View {
    let status: ThreadsPresenter.ConversationStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(labelColor)
        }
    }

    private var dotColor: Color {
        switch status {
        case .running: ALPalette.blue400
        case .exit0: ALPalette.green400
        case .exit1: ALPalette.red400
        default: ALColor.textFaint
        }
    }

    private var labelColor: Color {
        switch status {
        case .running: ALPalette.blue400
        case .boardReady, .specReady: ALColor.accentText
        case .exit0: ALPalette.green400
        case .exit1: ALPalette.red400
        default: ALColor.textMuted
        }
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

// MARK: - New run (threads exist, none selected)

private struct HomeNewRunPane: View {
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(AppModel.self) private var appModel

    // One readiness number, CLI-based — the same source as the title-bar badge, so
    // "N ready" never disagrees between the header and the empty state.
    private var readyCount: Int { appModel.readyToolCount }
    private var totalCount: Int { appModel.totalToolCount }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                AllnighterGlyph(size: 38)
                Text("Start a run")
                    .font(.system(size: 25, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(ALColor.textPrimary)
                Text("One message plus an optional team and worker, running in the selected repo root.")
                    .font(.system(size: 13.5)).foregroundStyle(ALColor.textMuted)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 486)
                HStack(spacing: 8) {
                    Circle().fill(readyCount > 0 ? ALPalette.green500 : ALColor.textFaint).frame(width: 6, height: 6)
                    Text(readyCount == totalCount ? "\(readyCount) CLIs ready" : "\(readyCount)/\(totalCount) CLIs ready")
                        .font(ALFont.monoSm).foregroundStyle(ALColor.textMuted)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
            RoutingComposer(
                big: true,
                showsProject: true,
                onSend: { threads.sendRouting($0, createThread: true) }
            )
            .frame(maxWidth: 640)
            .padding(.horizontal, 28).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
    }
}
