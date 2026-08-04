import SwiftUI
import AppKit
import AllnighterCore
import AllnighterEngine
import AgentOSTeam

// Conversation thread pane (docs/phases/wiring/compose-routing, reference/app.jsx
// ThreadPane + NewPane). CR4a: userMessage turns + docked RoutingComposer; worker
// replies land in CR4b.

struct ThreadView: View {
    @Environment(ThreadsViewModel.self) private var threads

    var body: some View {
        if let thread = threads.selectedThread {
            ThreadPaneShell(thread: thread)
        }
    }
}

// MARK: - Thread shell (one composer — survives empty→conversation)

private struct ThreadPaneShell: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    private var isEmpty: Bool { thread.turns.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty {
                ThreadEmptyStateBody(thread: thread)
            } else {
                ThreadConversationBody(thread: thread)
            }
            if thread.isArchived {
                archivedComposerBar
            } else {
                ThreadDockedComposer(thread: thread, big: isEmpty)
                    .frame(maxWidth: isEmpty ? 640 : 680)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, isEmpty ? 28 : 20)
                    .padding(.vertical, isEmpty ? 28 : 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ALColor.base)
        .overlay {
            if thread.isArchived && isEmpty {
                archivedComposerOverlay
            }
        }
    }

    private var archivedComposerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox").foregroundStyle(ALColor.textFaint)
            Text("Unarchive to reply")
                .font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
            Spacer()
            Button("Unarchive") { threads.unarchiveThread(thread.id) }
                .buttonStyle(.alLight)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var archivedComposerOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "archivebox").foregroundStyle(ALColor.textFaint)
                Text("Unarchive to reply").font(.system(size: 13)).foregroundStyle(ALColor.textMuted)
                Spacer()
                Button("Unarchive") { threads.unarchiveThread(thread.id) }
                    .buttonStyle(.alLight)
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(ALColor.base.opacity(0.92))
        }
    }
}

// MARK: - Empty thread ("Start a run")

private struct ThreadEmptyStateBody: View {
    @Environment(AppModel.self) private var appModel
    let thread: WorkThread

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
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .disabled(thread.isArchived)
    }
}

// MARK: - Thread with turns

private struct ThreadConversationBody: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread

    var body: some View {
        VStack(spacing: 0) {
            ThreadPaneHeader(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
            ThreadTurnTimeline(thread: thread)
            Rectangle().fill(ALColor.borderSubtle).frame(height: 1)
        }
        // ⌥⌘R toggles the whole conversation between rich markdown and raw selectable
        // source. A zero-size button just to own the keyboard shortcut.
        .background {
            Button("") { threads.showRawAnswers.toggle() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Docked composer (thread-scoped continuation)

/// One composer per thread — pins the last model used so session continuation survives
/// turn settlement, empty→conversation transitions, and rail switches.
private struct ThreadDockedComposer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread
    var big: Bool = false

    private var continuationModelId: String? {
        ThreadsPresenter.continuationModelId(
            for: thread,
            benchModelIds: Set(appModel.composeBench.map(\.id))
        )
    }

    var body: some View {
        RoutingComposer(
            big: big,
            continuationModelId: continuationModelId,
            onSend: { threads.sendRouting($0) }
        )
        .id(thread.id)
    }
}

private struct ThreadPaneHeader: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ThreadsViewModel.self) private var threads
    @Environment(CommandCenter.self) private var commands
    let thread: WorkThread
    @State private var editTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if thread.isArchived {
                Text(thread.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .lineLimit(1)
                Text("Archived")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ALColor.textMuted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(ALColor.surface, in: Capsule())
            } else {
                TextField("Title", text: $editTitle, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ALColor.textPrimary)
                    .focused($titleFocused)
            }
            if let lane = inferredLane {
                laneChip(lane)
            }
            RelayThreadChrome(loopId: thread.id)
            Spacer(minLength: 8)
            if thread.isArchived {
                Button("Unarchive") { threads.unarchiveThread(thread.id) }
                    .buttonStyle(.alLight)
            } else {
                Button { threads.togglePin(for: thread) } label: {
                    Image(systemName: thread.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ALColor.textMuted)
                .help(thread.isPinned ? "Unpin" : "Pin")
                Button("Archive") { threads.archiveThread(thread.id) }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ALColor.textMuted)
                    .buttonStyle(.plain)
            }
            // Who you're talking to — the model name(s), not a CLI logo. The name is
            // what actually tells you who answered (founder: "10x more valuable").
            if !routedModelNames.isEmpty {
                let names = routedModelNames
                Text(names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " +\(names.count - 2)" : ""))
                    .font(ALFont.monoSm).foregroundStyle(ALColor.textFaint).lineLimit(1)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .onAppear { editTitle = thread.title }
        .onChange(of: thread.title) { _, title in editTitle = title }
        .onChange(of: commands.focusRenameTick) { _, _ in titleFocused = true }
    }

    private func commitRename() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threads.renameThread(thread.id, title: trimmed)
    }

    // A normal chat/code run gets NO lane chip — it's just a conversation (founder).
    // Only the genuinely distinct Design surface (an image board) is badged.
    private var inferredLane: ComposeLane? {
        if thread.turns.contains(where: { $0.kind == .designBoard }) { return .design }
        return nil
    }

    private var routedWorkerIds: [String] {
        var seen = Set<String>()
        return thread.turns.compactMap(\.modelId).filter { seen.insert($0).inserted }
    }

    /// Distinct model display names that have answered in this thread. A worker id is
    /// `modelId#instanceIndex` (Agent.makeID), so strip the suffix before resolving.
    /// Resolve against the full model catalog (not just the live bench) so the name
    /// shows even for a model that isn't currently benched — and dedupe by name.
    private var routedModelNames: [String] {
        var seen = Set<String>()
        return routedWorkerIds.compactMap { wid -> String? in
            let modelId = wid.split(separator: "#").first.map(String.init) ?? wid
            guard let name = appModel.models.first(where: { $0.id == modelId })?.displayName else { return nil }
            return seen.insert(name).inserted ? name : nil
        }
    }

    private func laneChip(_ lane: ComposeLane) -> some View {
        HStack(spacing: 4) {
            Image(systemName: lane.icon).font(.system(size: 11))
            Text(lane.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(lane == .design ? ALColor.accentText : ALColor.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(lane == .design ? ALColor.active : ALColor.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(ALColor.borderSubtle, lineWidth: 1) }
    }
}

private struct ThreadTurnTimeline: View {
    @Environment(ThreadsViewModel.self) private var threads
    let thread: WorkThread
    /// RLS-S04: true while the user is parked at the bottom — gates live follow-scroll so a
    /// streaming answer keeps itself in view, but a manual scroll-up is never fought.
    @State private var atBottom = true
    private static let bottomAnchorId = "__timeline_bottom__"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(thread.turns) { turn in
                            ThreadTurnRow(turn: turn, isLastTurn: turn.id == thread.turns.last?.id)
                                .id(turn.id)
                                .timelineTurnFrame(turnId: turn.id)
                        }
                        // Bottom sentinel — reports the content's bottom edge so live
                        // follow-scroll only fires when the user is already at the bottom.
                        Color.clear.frame(height: 1)
                            .id(Self.bottomAnchorId)
                            .background(GeometryReader { g in
                                Color.clear.preference(
                                    key: TimelineBottomSentinelKey.self,
                                    value: g.frame(in: .global).maxY)
                            })
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .timelineVisibilityTracking(thread: thread)
                .onPreferenceChange(TimelineBottomSentinelKey.self) { sentinelMaxY in
                    atBottom = TimelineScrollPolicy.isAtBottom(
                        contentBottomY: sentinelMaxY, viewportBottomY: outer.frame(in: .global).maxY)
                }
                .onAppear { scrollTimelineToOpenPosition(proxy: proxy) }
                .onChange(of: thread.id) { _, _ in scrollTimelineToOpenPosition(proxy: proxy) }
                .onChange(of: thread.turns.count) { _, _ in
                    TimelineScrollPolicy.scrollOnTurnCountChange(
                        proxy: proxy,
                        thread: thread,
                        suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll,
                        forceScrollToBottomAfterSend: threads.forceScrollToBottomAfterSendActive(),
                        bottomAnchorId: Self.bottomAnchorId
                    )
                }
                .onChange(of: TimelineScrollPolicy.liveContentSignal(for: thread)) { _, _ in
                    // RLS-S04: follow the streaming answer as it grows — but only when the
                    // user is at the bottom, and without animation so the follow stays tight.
                    guard !GUIFixture.suppressUnreadAutoScroll else { return }
                    if threads.forceScrollToBottomAfterSendActive() || atBottom {
                        TimelineScrollPolicy.scrollToBottom(
                            proxy: proxy,
                            bottomAnchorId: Self.bottomAnchorId,
                            animated: false
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollTimelineToOpenPosition(proxy: ScrollViewProxy) {
        TimelineScrollPolicy.scrollOnThreadOpen(
            proxy: proxy,
            pendingTarget: threads.consumePendingScrollTarget(),
            suppressAutoScroll: GUIFixture.suppressUnreadAutoScroll,
            bottomAnchorId: Self.bottomAnchorId
        )
    }
}


